"""Adaptive exploration loop: generate -> validate -> select -> execute ->
compare -> cluster -> reproduce -> minimize -> diagnose -> report.

Selection (per round of `batch` scenarios):
  score(candidate) = novelty(candidate) + UCB(family)
  novelty = share of the candidate's coverage features never *executed*
  UCB     = mean new-issue yield of the family + c * sqrt(ln N / n_family)
Each family is capped at `max_share` of a round and every family with
candidates gets at least one slot, so the loop cannot fixate on the
subsystem that is failing most.

Results are appended to `results.jsonl` after every batch; an interrupted run
keeps every finished batch and `--resume` continues from it.
"""
from __future__ import annotations

import gzip
import json
import math
import os
import random
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path

from . import generate as gen
from .catalog import COMPONENTS, PROPERTIES
from .compare import compare
from .diagnose import cluster, diagnose, fingerprint
from .execute import run_chrome, run_nativa
from .minimize import minimize
from .report import build_issue_report, llm_brief, summary_markdown, write_json, write_text
from .schema import check_scenario

ROOT = Path(__file__).resolve().parents[4]
AUDIT = ROOT / "debug" / "artifacts" / "audit"
LEDGER = AUDIT / "ledger.json"
EXEC_FAMILIES = ["basic", "combinatorial", "random", "adversarial", "invalid", "interaction",
                 "mutation", "regression"]


def git_state() -> dict:
    def run(*args):
        try:
            return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True,
                                  timeout=20).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return ""
    dirty = bool(run("status", "--porcelain", "--", "packages", "debug/harness"))
    return {"git_commit": run("rev-parse", "--short", "HEAD") or "unknown", "git_dirty": dirty,
            "generator_version": gen.GENERATOR_VERSION}


class Runner:
    """Runs scenarios on both engines with a per-run cache keyed by content."""

    def __init__(self, work: Path, log=print, nativa_fn=None, chrome_fn=None):
        self.work = work
        self.log = log
        self.nativa_fn = nativa_fn or run_nativa
        self.chrome_fn = chrome_fn or run_chrome
        self.cache: dict[str, tuple] = {}
        self.batches = 0
        self.engine = None
        self.max_rss_kb = 0

    def observe(self, scenarios: list[dict]) -> dict[str, tuple]:
        todo = [s for s in scenarios if gen.content_hash(s) not in self.cache]
        if todo:
            self.batches += 1
            work = self.work / f"batch-{self.batches:04d}"
            t0 = time.monotonic()
            chrome = self.chrome_fn(todo, work / "chrome", log=self.log)
            t1 = time.monotonic()
            nativa = self.nativa_fn(todo, work / "nativa", log=self.log)
            t2 = time.monotonic()
            self.log(f"[batch {self.batches}] {len(todo)} scenarios · chromium {t1 - t0:.1f}s · "
                     f"nativax {t2 - t1:.1f}s")
            for s in todo:
                n = nativa.get(s["scenario_id"]) or {"status": "crash", "error": "no result", "states": []}
                if n.get("engine"):
                    self.engine = n["engine"]
                rss = (n.get("rss_kb") or {}).get("after") or 0
                self.max_rss_kb = max(self.max_rss_kb, rss)
                self.cache[gen.content_hash(s)] = (n, chrome.get(s["scenario_id"]))
            shutil.rmtree(work / "nativa" / "pages", ignore_errors=True)
        return {s["scenario_id"]: self.cache[gen.content_hash(s)] for s in scenarios}

    def evaluate(self, scenarios):
        obs = self.observe(scenarios)
        return {sid: compare(next(s for s in scenarios if s["scenario_id"] == sid), n, c, ROOT)
                for sid, (n, c) in obs.items()}

    def fingerprints(self, scenarios):
        return {sid: {fingerprint(f) for f in comp["findings"] if f.get("primary", True)}
                for sid, comp in self.evaluate(scenarios).items()}


class Coverage:
    def __init__(self):
        self.generated, self.executed, self.verified = set(), set(), set()

    def table(self):
        def dim(prefix):
            return {k: len({f for f in getattr(self, k) if f.startswith(prefix)})
                    for k in ("generated", "executed", "verified")}
        executable = [c for c, s in COMPONENTS.items() if s["executable"]]
        rows = {
            "componentes": {**dim("type:"), "universe": len(executable)},
            "propiedades": {**dim("prop:"), "universe": len(PROPERTIES)},
            "componente×propiedad": {**dim("prop_on:"), "universe": len(executable) * len(PROPERTIES)},
            "valores": {**dim("value:"), "universe": sum(len(v) for d in PROPERTIES.values() for v in d.values())},
            "pares de propiedades": {**dim("pair:"), "universe": len(PROPERTIES) * (len(PROPERTIES) - 1) // 2},
            "anidamiento padre>hijo": {**dim("nest:"), "universe": None},
            "acciones": {**dim("action:"), "universe": 7},
            "transiciones": {**dim("transition:"), "universe": 49},
            "profundidad": {**dim("depth:"), "universe": 11},
            "filas pairwise": {**dim("pairwise_row:"), "universe": gen.combinatorial_size()},
        }
        return rows


class Explorer:
    def __init__(self, *, budget=200, batch=40, seed=1, families=None, max_share=0.35,
                 minimize_top=5, reproduce=True, time_limit_s=None, run_id=None, log=print,
                 runner_factory=None, home: Path | None = None, publish: bool = True):
        self.budget, self.batch, self.seed = budget, batch, seed
        self.families = families or EXEC_FAMILIES
        self.max_share, self.minimize_top, self.reproduce = max_share, minimize_top, reproduce
        self.time_limit_s = time_limit_s
        self.log = log
        self.rng = random.Random(seed)
        self.run_id = run_id or datetime.now().strftime("%Y%m%dT%H%M%S") + f"-s{seed}"
        # `home` holds runs/, latest/ and ledger.json; benchmarks and tests use
        # their own home so they never touch the real ledger. `publish`
        # writes progress/reports/audit-latest.md.
        self.home = home or AUDIT
        self.publish = publish
        self.out = self.home / "runs" / self.run_id
        self.out.mkdir(parents=True, exist_ok=True)
        self.runner = (runner_factory or (lambda w, l: Runner(w, l)))(self.out / "work", log)
        self.cursors = {f: seed * 100003 for f in gen.FAMILIES}
        self.coverage = Coverage()
        self.stats = {f: {"executed": 0, "ms": 0.0, "first_found": 0} for f in self.families}
        self.results: list[dict] = []
        self.scenarios: dict[str, dict] = {}
        self.known_fps: set[str] = set()
        self.counters = {"generated": 0, "rejected": 0, "rejected_expected": 0,
                         "rejected_unexpected": 0, "validator_escapes": 0}
        self.parents: list[dict] = []
        self._pooled: set[str] = set()
        self.regression_queue = gen.regressions()
        self.started = time.monotonic()
        self.started_at = datetime.now().isoformat(timespec="seconds")

    # ------------------------------------------------------------ candidates
    def _next(self, family) -> dict | None:
        if family == "mutation":
            if not self.parents:
                return None
            failing = [p for p in self.parents if p.get("_failed")]
            pool = failing if failing and self.rng.random() < 0.6 else self.parents
            parent = {k: v for k, v in self.rng.choice(pool).items() if not k.startswith("_")}
            self.cursors.setdefault("mutation", 0)
            self.cursors["mutation"] += 1
            return gen.mutate(parent, self.cursors["mutation"])
        if family == "regression":
            return self.regression_queue.pop(0) if self.regression_queue else None
        self.cursors[family] += 1
        return gen.FAMILIES[family](self.cursors[family])

    def _admit(self, scenario) -> bool:
        self.counters["generated"] += 1
        errors = check_scenario(scenario)
        feats = scenario_features(scenario)
        scenario["_features"] = feats
        if scenario.get("category") == "schema_invalid":
            if errors:
                self.counters["rejected"] += 1
                self.counters["rejected_expected"] += 1
            else:
                self.counters["validator_escapes"] += 1
                self.log(f"[validator] deliberately invalid scenario accepted: {scenario['scenario_id']}")
            return False
        if errors:
            self.counters["rejected"] += 1
            self.counters["rejected_unexpected"] += 1
            self.log(f"[validator] {scenario['scenario_id']} rejected: {errors[:2]}")
            return False
        # Same content generated twice (two mutations can converge): one run.
        if scenario["scenario_id"] in self.scenarios or scenario["scenario_id"] in self._pooled:
            return False
        self._pooled.add(scenario["scenario_id"])
        self.coverage.generated |= feats
        return True

    def _ucb(self, family, total):
        s = self.stats[family]
        if s["executed"] == 0:
            return 1.0
        mean = s["first_found"] / s["executed"]
        return mean + 0.5 * math.sqrt(math.log(max(total, 2)) / s["executed"])

    def _select(self) -> list[dict]:
        pool = []
        for family in self.families:
            for _ in range(max(2, self.batch // 2) if family != "regression" else self.batch):
                cand = self._next(family)
                if cand is None:
                    break
                if self._admit(cand):
                    pool.append(cand)
        # Deliberate negatives: a few per round, validated only.
        for _ in range(max(1, self.batch // 10)):
            self._admit(self._next("schema_invalid"))
        total = sum(s["executed"] for s in self.stats.values())
        cap = max(1, int(self.batch * self.max_share))

        def parts(c):
            feats = c["_features"]
            novelty = len(feats - self.coverage.executed) / max(1, len(feats))
            bonus = 2.0 if c.get("family") == "regression" else 0.0
            ucb = self._ucb(c.get("family"), total)
            return {"novelty": round(novelty, 4), "ucb": round(ucb, 4), "bonus": bonus,
                    "score": round(novelty + ucb + bonus, 4), "features": len(feats),
                    "new_features": len(feats - self.coverage.executed)}

        scored = [(parts(c), c) for c in pool]
        scored.sort(key=lambda pc: pc[0]["score"], reverse=True)
        chosen, per, reasons = [], {}, {}
        # one slot per family first (exploration floor), then by score
        for family in self.families:
            pick = next((c for _, c in scored if c.get("family") == family), None)
            if pick is not None and len(chosen) < self.batch:
                chosen.append(pick)
                per[family] = 1
                reasons[pick["scenario_id"]] = "exploration floor (first slot of its family)"
        for _, c in scored:
            sid = c["scenario_id"]
            if sid in reasons:
                continue
            if len(chosen) >= self.batch:
                reasons[sid] = "discarded: batch full"
                continue
            fam = c.get("family")
            if per.get(fam, 0) >= cap and fam != "regression":
                reasons[sid] = f"discarded: family cap {cap} reached"
                continue
            chosen.append(c)
            per[fam] = per.get(fam, 0) + 1
            reasons[sid] = "selected by score rank"
        for c in chosen:
            self.coverage.executed |= c["_features"]
        # Every decision is recorded so the selection can be explained later.
        self.round = getattr(self, "round", 0) + 1
        chosen_ids = {c["scenario_id"] for c in chosen}
        with (self.out / "selection.jsonl").open("a") as fh:
            for rank, (sc, c) in enumerate(scored):
                fh.write(json.dumps({
                    "round": self.round, "rank": rank, "scenario_id": c["scenario_id"],
                    "family": c.get("family"), "category": c.get("category"),
                    **sc, "chosen": c["scenario_id"] in chosen_ids,
                    "reason": reasons.get(c["scenario_id"]), "cap": cap,
                    "executed_before": total,
                }) + "\n")
        return chosen

    # ------------------------------------------------------------------- run
    def run(self) -> dict:
        self.log(f"[audit] run {self.run_id}: budget {self.budget}, batch {self.batch}, seed {self.seed}")
        results_file = self.out / "results.jsonl"
        while len(self.results) < self.budget:
            if self.time_limit_s and time.monotonic() - self.started > self.time_limit_s:
                self.log("[audit] time limit reached")
                break
            chosen = self._select()[: self.budget - len(self.results)]
            if not chosen:
                break
            clean = [{k: v for k, v in c.items() if not k.startswith("_")} for c in chosen]
            obs = self.runner.observe(clean)
            # Raw observations let `audit.py reanalyze` re-run the oracles
            # without executing anything again.
            with gzip.open(self.out / "observations.jsonl.gz", "at") as gz:
                for scen in clean:
                    n, c = obs[scen["scenario_id"]]
                    gz.write(json.dumps({"scenario": scen, "nativa": n, "chrome": c},
                                        ensure_ascii=False) + "\n")
            with results_file.open("a") as fh:
                for scen, raw in zip(clean, chosen):
                    n, c = obs[scen["scenario_id"]]
                    comp = compare(scen, n, c, ROOT)
                    fam = scen.get("family")
                    st = self.stats.setdefault(fam, {"executed": 0, "ms": 0.0, "first_found": 0})
                    st["executed"] += 1
                    st["ms"] += (n.get("timings") or {}).get("total_ms") or 0
                    new = {fingerprint(f) for f in comp["findings"] if f.get("primary", True)} - self.known_fps
                    st["first_found"] += len(new)
                    self.known_fps |= new
                    if n.get("status") == "ok" and (c or {}).get("status") == "ok":
                        self.coverage.verified |= raw["_features"]
                    raw["_failed"] = comp["status"] == "failed"
                    self.parents.append(raw)
                    self.scenarios[scen["scenario_id"]] = scen
                    item = {"scenario": scen, "comparison": comp,
                            "timings": n.get("timings"), "engine": n.get("engine"),
                            "nativa_status": n.get("status"), "reference_status": (c or {}).get("status")}
                    self.results.append(item)
                    fh.write(json.dumps(item, ensure_ascii=False, default=sorted) + "\n")
                fh.flush()
                os.fsync(fh.fileno())
            self._checkpoint()
            failed = sum(1 for r in self.results if r["comparison"]["status"] == "failed")
            self.log(f"[audit] [{len(self.results)}/{self.budget}] executed · {failed} with defects · "
                     f"{len(self.known_fps)} unique fingerprints")
        return self.finish()

    def reanalyze(self, run_dir: Path) -> dict:
        """Recomputes comparisons, issues and reports from saved observations."""
        with gzip.open(run_dir / "observations.jsonl.gz", "rt") as gz:
            rows = [json.loads(line) for line in gz if line.strip()]
        for row in rows:
            scen, n, c = row["scenario"], row["nativa"], row["chrome"]
            self.runner.cache[gen.content_hash(scen)] = (n, c)
            comp = compare(scen, n, c, ROOT)
            fam = scen.get("family")
            st = self.stats.setdefault(fam, {"executed": 0, "ms": 0.0, "first_found": 0})
            st["executed"] += 1
            st["ms"] += (n.get("timings") or {}).get("total_ms") or 0
            new = {fingerprint(f) for f in comp["findings"] if f.get("primary", True)} - self.known_fps
            st["first_found"] += len(new)
            self.known_fps |= new
            feats = scenario_features(scen)
            self.coverage.generated |= feats
            self.coverage.executed |= feats
            if n.get("status") == "ok" and (c or {}).get("status") == "ok":
                self.coverage.verified |= feats
            self.scenarios[scen["scenario_id"]] = scen
            self.results.append({"scenario": scen, "comparison": comp, "timings": n.get("timings"),
                                 "engine": n.get("engine"), "nativa_status": n.get("status"),
                                 "reference_status": (c or {}).get("status")})
        # Generation counters live only in the original run's metrics.
        for name in ("summary.json", "state.json"):
            try:
                data = json.loads((run_dir / name).read_text())
            except (OSError, ValueError):
                continue
            src = data.get("metrics") or data.get("counters") or {}
            for key in self.counters:
                if key in src:
                    self.counters[key] = src[key]
            break
        self.log(f"[reanalyze] {len(rows)} saved observations from {run_dir}")
        return self.finish()

    def _checkpoint(self):
        write_json(self.out / "state.json", {
            "run_id": self.run_id, "seed": self.seed, "budget": self.budget, "batch": self.batch,
            "executed": len(self.results), "cursors": self.cursors, "counters": self.counters,
            "updated_at": datetime.now().isoformat(timespec="seconds")})

    def finish(self) -> dict:
        system = {**git_state(), "engine": self.runner.engine}
        issues = cluster(self.results)
        ledger_path = self.home / "ledger.json"
        ledger = _load_ledger(ledger_path)
        order = sorted(issues.values(), key=lambda i: ({"critical": 0, "high": 1, "medium": 2, "low": 3,
                                                        "info": 4}[i["severity"]], -len(i["occurrences"])))
        reproducible: dict[str, bool | None] = {i["issue_id"]: None for i in order}
        if self.reproduce and order:
            # Fresh observation (cache bypassed) of the first scenario of each issue.
            fresh = Runner(self.out / "reproduce", self.log, self.runner.nativa_fn, self.runner.chrome_fn)
            firsts = {i["issue_id"]: self.scenarios[i["occurrences"][0]["scenario_id"]] for i in order}
            uniq = list({s["scenario_id"]: s for s in firsts.values()}.values())
            fps = fresh.fingerprints(uniq)
            for iid, s in firsts.items():
                reproducible[iid] = issues[iid]["fingerprint"] in fps.get(s["scenario_id"], set())
        minimizations: dict[str, dict] = {}
        for issue in [i for i in order if i["kind"] != "oracle_conflict"
                      and reproducible.get(i["issue_id"]) is not False][: self.minimize_top]:
            first = issue["occurrences"][0]
            scen = self.scenarios[first["scenario_id"]]
            keep = {x for x in (first["finding"].get("element_id"), "screen_main") if x}
            self.log(f"[minimize] {issue['issue_id']} {issue['fingerprint'][:70]}")
            try:
                minimizations[issue["issue_id"]] = minimize(scen, issue["fingerprint"], self.runner.fingerprints,
                                                            keep, log=self.log)
            except Exception as error:  # a failed minimization must not lose the run
                self.log(f"[minimize] {issue['issue_id']} failed: {error}")
        reports = []
        issues_dir = self.out / "issues"
        for issue in order:
            iid = issue["issue_id"]
            first = issue["occurrences"][0]
            if issue["kind"] == "style":
                same_el = [f for f in next(r for r in self.results
                                           if r["scenario"]["scenario_id"] == first["scenario_id"])
                           ["comparison"]["findings"]
                           if f["kind"] == "geometry" and f["element_id"] == first["finding"]["element_id"]]
                issue["_geometry_matches"] = not same_el
            entry = ledger.get(iid)
            novelty = "new" if entry is None else ("regression" if entry.get("status") == "fixed" else "known")
            diag = diagnose(issue, self.scenarios, minimizations.get(iid))
            report = build_issue_report(issue, diag, run_id=self.run_id, scenarios=self.scenarios,
                                        system=system, minimization=minimizations.get(iid),
                                        novelty=novelty, reproducible=reproducible.get(iid))
            write_json(issues_dir / f"{iid}.json", report)
            write_text(issues_dir / f"{iid}.md", llm_brief(report))
            reports.append(report)
            ledger[iid] = {"fingerprint": issue["fingerprint"], "status": "open",
                           "first_seen": (entry or {}).get("first_seen", self.run_id),
                           "last_seen": self.run_id, "severity": issue["severity"],
                           "kind": issue["kind"], "subsystem": issue["subsystem"]}
        summary = self._summary(system, reports, issues)
        write_json(self.out / "summary.json", summary)
        write_json(self.out / "metrics.json", summary["metrics"])
        write_json(self.out / "coverage.json", {"table": summary["coverage"],
                                                "executed_features": sorted(self.coverage.executed)})
        write_text(self.out / "summary.md", summary_markdown(summary, reports))
        write_json(ledger_path, ledger)
        latest = self.home / "latest"
        tmp = self.home / "latest.tmp"
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.copytree(self.out, tmp, ignore=shutil.ignore_patterns("work", "reproduce"))
        shutil.rmtree(latest, ignore_errors=True)
        tmp.rename(latest)
        if self.publish:
            report_md = ROOT / "progress" / "reports" / "audit-latest.md"
            write_text(report_md, summary_markdown(summary, reports).replace(
                "](issues/", "](../../debug/artifacts/audit/latest/issues/"))
        self.log(f"[audit] done: {len(reports)} issues · summary {latest / 'summary.md'}")
        return summary

    def _summary(self, system, reports, issues):
        wall = time.monotonic() - self.started
        statuses = [r["comparison"]["status"] for r in self.results]
        findings = sum(len(r["comparison"]["findings"]) for r in self.results)
        defect_reports = [r for r in reports if r["status"] == "failed"]
        complete = [r for r in defect_reports if r["reproduction"]["reproducible"] and r["evidence"]["finding"]]
        localized = [r for r in defect_reports if r["location"]["json_path"] or r["location"]["source_file"]]
        metrics = {
            **self.counters,
            "valid": sum(1 for r in self.results if r["scenario"]["category"] in ("valid", "boundary")),
            "invalid_content": sum(1 for r in self.results if r["scenario"]["category"] == "invalid_content"),
            "executed": len(self.results),
            "verified": sum(1 for r in self.results if r["nativa_status"] == "ok" and r["reference_status"] == "ok"),
            "passed": statuses.count("passed"), "failed": statuses.count("failed"),
            "inconclusive": statuses.count("inconclusive"),
            "findings": findings,
            "unique_issues": len(defect_reports),
            "oracle_conflicts": len(reports) - len(defect_reports),
            "duplicates_grouped": sum(len(i["occurrences"]) for i in issues.values()) - len(issues),
            "new_issues": sum(1 for r in defect_reports if r["novelty"] == "new"),
            "regressions": sum(1 for r in defect_reports if r["novelty"] == "regression"),
            "reproducible": sum(1 for r in defect_reports if r["reproduction"]["reproducible"]),
            "not_reproducible": sum(1 for r in defect_reports if r["reproduction"]["reproducible"] is False),
            "minimized": sum(1 for r in defect_reports if r["reproduction"]["minimized"]),
            "reports_complete_pct": round(100 * len(complete) / len(defect_reports), 1) if defect_reports else None,
            "reports_localized_pct": round(100 * len(localized) / len(defect_reports), 1) if defect_reports else None,
            "wall_s": round(wall, 1),
            "issues_per_minute": round(len(defect_reports) / (wall / 60), 3) if wall > 0 else 0,
            "batches": self.runner.batches,
            "max_rss_mb": round(self.runner.max_rss_kb / 1024) if self.runner.max_rss_kb else None,
            "mean_ms_by_subsystem": _ms_by_subsystem(self.results),
        }
        strategies = {f: {"executed": s["executed"], "mean_ms": s["ms"] / s["executed"] if s["executed"] else 0,
                          "first_found": s["first_found"],
                          "yield": s["first_found"] / s["executed"] if s["executed"] else 0}
                      for f, s in self.stats.items()}
        limitations = [
            "Chromium es la referencia; donde difiere de la especificación, la auditoría lo reporta como defecto de NativaX.",
            "Clicks en la referencia son eventos sintéticos en el mismo punto (elementFromPoint); "
            "Tab usa un modelo de recorrido de foco; otras teclas no se reproducen en la referencia.",
            "Los colores se comparan por estilo computado; no hay comparación de píxeles en esta auditoría "
            "(eso lo mide el juez visual).",
            "Imágenes no ejecutables: el arnés no pasa imageResolver.",
        ]
        if self.counters["validator_escapes"]:
            limitations.append(f"{self.counters['validator_escapes']} escenarios inválidos deliberados "
                               "pasaron la validación: defecto del propio motor.")
        return {"run_id": self.run_id, "seed": self.seed, "system": system,
                "started_at": self.started_at, "finished_at": datetime.now().isoformat(timespec="seconds"),
                "config": {"budget": self.budget, "batch": self.batch, "families": self.families,
                           "max_share": self.max_share, "minimize_top": self.minimize_top},
                "metrics": metrics, "coverage": self.coverage.table(), "strategies": strategies,
                "issues": [{"issue_id": r["issue_id"], "severity": r["severity"], "kind": r["classification"]["kind"],
                            "subsystem": r["classification"]["subsystem"],
                            "component_types": r["classification"]["component_types"],
                            "property": r["classification"]["property"], "count": r["occurrences"]["count"],
                            "status": r["status"], "novelty": r["novelty"],
                            "minimized": r["reproduction"]["minimized"],
                            "reproducible": r["reproduction"]["reproducible"],
                            "confidence": r["confidence"]["level"],
                            "message": r["evidence"]["message"][:200]} for r in reports],
                "limitations": limitations}


def scenario_features(scenario) -> set[str]:
    feats = gen.features(scenario)
    if scenario.get("family") == "combinatorial":
        feats.add("pairwise_row:" + scenario["title"].split("_")[-1])
    return feats


def _ms_by_subsystem(results):
    acc: dict[str, list] = {}
    for r in results:
        ms = (r.get("timings") or {}).get("total_ms")
        if not ms:
            continue
        for tag in r["scenario"].get("tags") or []:
            acc.setdefault(tag, []).append(ms)
    return {k: round(sum(v) / len(v)) for k, v in sorted(acc.items()) if len(v) >= 3}


def _load_ledger(path: Path = LEDGER) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}

"""Read-only data layer for the audit GUI.

A *report unit* is one run folder written by `nxaudit` (`summary.json`,
`metrics.json`, `coverage.json`, `results.jsonl`, `observations.jsonl.gz`,
`selection.jsonl`, `state.json`, `issues/NX-*.{json,md}`, and for benchmark
runs `benchmark.json` / `self-check.json`). Units are discovered recursively
under any root folder, so runs can be organised in arbitrary subfolders.

Rules:
  * nothing here writes inside a unit (files are opened for reading only);
  * every unit is loaded on its own; nothing is merged across units;
  * a missing or corrupt file is reported as such, never replaced by data
    from another unit or by a default.
"""
from __future__ import annotations

import gzip
import json
import os
import statistics
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIT_DIR = ROOT / "debug" / "engines" / "bug_detection"
sys.path.insert(0, str(AUDIT_DIR))

from nxaudit.diagnose import fingerprint  # noqa: E402  (engine's own function)
from nxaudit.generate import features  # noqa: E402

UNIT_MARKERS = ("summary.json", "results.jsonl", "state.json")
# Engine scratch folders inside a unit: never units themselves.
SKIP_DIRS = {"work", "reproduce", "pages", "chrome", "nativa", "latest.tmp", "__pycache__"}
SEVERITIES = ["critical", "high", "medium", "low", "info"]


def is_unit(path: Path) -> bool:
    return any((path / m).exists() for m in UNIT_MARKERS)


@dataclass
class Loaded:
    """A value read from a file, or why it could not be read."""
    value: object = None
    error: str | None = None
    source: str | None = None
    skipped_lines: int = 0

    @property
    def ok(self):
        return self.error is None


def read_json(path: Path) -> Loaded:
    if not path.exists():
        return Loaded(error="no disponible (el archivo no existe)", source=str(path))
    try:
        with path.open("r", encoding="utf-8") as fh:
            return Loaded(json.load(fh), source=str(path))
    except (OSError, ValueError) as error:
        return Loaded(error=f"corrupto o ilegible: {error}", source=str(path))


def read_jsonl(path: Path, gz: bool = False) -> Loaded:
    if not path.exists():
        return Loaded(value=[], error="no disponible (el archivo no existe)", source=str(path))
    rows, bad = [], 0
    try:
        opener = gzip.open(path, "rt", encoding="utf-8") if gz else path.open("r", encoding="utf-8")
        with opener as fh:
            for line in fh:
                if not line.strip():
                    continue
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    bad += 1  # a run interrupted mid-write leaves a partial last line
    except (OSError, EOFError) as error:
        return Loaded(value=rows, error=f"lectura interrumpida: {error}", source=str(path), skipped_lines=bad)
    return Loaded(value=rows, source=str(path), skipped_lines=bad)


@dataclass
class UnitMeta:
    path: Path
    name: str
    kind: str
    status: str            # complete | incomplete | corrupt
    health: str            # error | warn | ok | unknown
    run_id: str | None = None
    started_at: str | None = None
    finished_at: str | None = None
    executed: int | None = None
    issues: int | None = None
    critical_high: int | None = None
    commit: str | None = None
    alias_of: str | None = None
    mtime: float = 0.0
    note: str = ""


def unit_kind(path: Path) -> str:
    parts = path.parts
    for name in ("self-check", "benchmark"):
        if name in parts or path.name.startswith(name):
            return name
    return "auditoría"


def unit_meta(path: Path) -> UnitMeta:
    kind = unit_kind(path)
    try:
        mtime = path.stat().st_mtime
    except OSError:
        mtime = 0.0
    summary = read_json(path / "summary.json")
    if summary.ok and isinstance(summary.value, dict):
        s = summary.value
        m = s.get("metrics") or {}
        issues = [i for i in s.get("issues") or [] if i.get("status") == "failed"]
        ch = sum(1 for i in issues if i.get("severity") in ("critical", "high"))
        health = "error" if ch else ("warn" if issues else "ok")
        alias = None
        if path.name == "latest" and s.get("run_id"):
            alias = s["run_id"]
        return UnitMeta(path, path.name, kind, "complete", health, s.get("run_id"), s.get("started_at"),
                        s.get("finished_at"), m.get("executed"), len(issues), ch,
                        (s.get("system") or {}).get("git_commit"), alias, mtime)
    state = read_json(path / "state.json")
    if state.ok and isinstance(state.value, dict):
        st = state.value
        return UnitMeta(path, path.name, kind, "incomplete", "unknown", st.get("run_id"), None,
                        st.get("updated_at"), st.get("executed"), None, None, None, None, mtime,
                        "sin summary.json: ejecución en curso o interrumpida")
    note = summary.error if summary.error and "no existe" not in summary.error else \
        "sin summary.json ni state.json"
    return UnitMeta(path, path.name, kind, "corrupt" if summary.error and "corrupto" in summary.error
                    else "incomplete", "unknown", None, mtime=mtime, note=note)


def child_dirs(path: Path) -> list[Path]:
    try:
        return sorted((p for p in path.iterdir() if p.is_dir() and p.name not in SKIP_DIRS),
                      key=lambda p: p.name)
    except OSError:
        return []


def discover(root: Path, limit: int = 100000) -> list[Path]:
    """All unit folders under `root` (a unit's own subfolders are not walked)."""
    out = []
    stack = [root]
    while stack and len(out) < limit:
        d = stack.pop()
        if is_unit(d):
            out.append(d)
            continue
        stack.extend(reversed(child_dirs(d)))
    return out


def percentiles(values, ps=(50, 90, 95, 99)):
    vals = sorted(v for v in values if isinstance(v, (int, float)))
    if not vals:
        return {f"p{p}": None for p in ps}
    out = {}
    for p in ps:
        k = (len(vals) - 1) * p / 100
        lo, hi = int(k), min(int(k) + 1, len(vals) - 1)
        out[f"p{p}"] = vals[lo] + (vals[hi] - vals[lo]) * (k - lo)
    return out


class Unit:
    """One report unit. Every accessor reads only this unit's folder."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.meta = unit_meta(self.path)
        self._cache: dict[str, object] = {}

    def _get(self, key, fn):
        if key not in self._cache:
            self._cache[key] = fn()
        return self._cache[key]

    # raw files ------------------------------------------------------------
    def summary(self) -> Loaded:
        return self._get("summary", lambda: read_json(self.path / "summary.json"))

    def metrics(self) -> Loaded:
        return self._get("metrics", lambda: read_json(self.path / "metrics.json"))

    def coverage(self) -> Loaded:
        return self._get("coverage", lambda: read_json(self.path / "coverage.json"))

    def state(self) -> Loaded:
        return self._get("state", lambda: read_json(self.path / "state.json"))

    def benchmark(self) -> Loaded:
        for name in ("benchmark.json", "self-check.json"):
            if (self.path / name).exists():
                return self._get("bench", lambda n=name: read_json(self.path / n))
        return Loaded(error="no disponible (no es una ejecución de benchmark/self-check)")

    def raw_results(self) -> Loaded:
        return self._get("results", lambda: read_jsonl(self.path / "results.jsonl"))

    def selection(self) -> Loaded:
        return self._get("selection", lambda: read_jsonl(self.path / "selection.jsonl"))

    def observations(self) -> Loaded:
        def load():
            got = read_jsonl(self.path / "observations.jsonl.gz", gz=True)
            got.value = {r["scenario"]["scenario_id"]: r for r in got.value or []
                         if isinstance(r, dict) and "scenario" in r}
            return got
        return self._get("observations", load)

    def issues(self) -> dict[str, Loaded]:
        def load():
            d = self.path / "issues"
            if not d.exists():
                return {}
            return {p.stem: read_json(p) for p in sorted(d.glob("NX-*.json"))}
        return self._get("issues", load)

    def issue_markdown(self, issue_id: str) -> Loaded:
        p = self.path / "issues" / f"{issue_id}.md"
        if not p.exists():
            return Loaded(error="no disponible")
        try:
            return Loaded(p.read_text(encoding="utf-8"), source=str(p))
        except OSError as error:
            return Loaded(error=str(error))

    def files(self) -> list[dict]:
        out = []
        for dirpath, dirnames, filenames in os.walk(self.path):
            dirnames[:] = [d for d in dirnames if d not in ("pages",)]
            for name in filenames:
                p = Path(dirpath) / name
                try:
                    st = p.stat()
                except OSError:
                    continue
                out.append({"path": str(p.relative_to(self.path)), "size": st.st_size,
                            "modified": datetime.fromtimestamp(st.st_mtime).isoformat(timespec="seconds"),
                            "abs": str(p)})
        return sorted(out, key=lambda r: r["path"])

    # derived (from this unit only) ---------------------------------------
    def fingerprint_index(self) -> dict[str, str]:
        def build():
            out = {}
            for iid, got in self.issues().items():
                if got.ok and isinstance(got.value, dict) and got.value.get("fingerprint"):
                    out[got.value["fingerprint"]] = iid
            return out
        return self._get("fpindex", build)

    def rows(self) -> list[dict]:
        """One flat row per executed scenario, for tables and filters."""
        def build():
            idx = self.fingerprint_index()
            out = []
            for i, r in enumerate(self.raw_results().value or []):
                if not isinstance(r, dict) or "scenario" not in r:
                    continue
                s = r["scenario"]
                comp = r.get("comparison") or {}
                findings = comp.get("findings") or []
                primary = [f for f in findings if f.get("primary", True)]
                fps = {fingerprint(f) for f in primary}
                timings = r.get("timings") or {}
                out.append({
                    "order": i, "scenario_id": s.get("scenario_id"), "family": s.get("family"),
                    "category": s.get("category"), "status": comp.get("status"),
                    "nativa_status": r.get("nativa_status"), "reference_status": r.get("reference_status"),
                    "seed": s.get("seed"), "assertions": len(s.get("assertions") or []),
                    "actions": len(s.get("actions") or []),
                    "findings": len(findings), "primary": len(primary),
                    "errors": sum(1 for f in findings if f.get("kind") in ("crash", "script_error")),
                    "issues": sorted(idx[f] for f in fps if f in idx),
                    "subsystems": sorted({f.get("subsystem") for f in primary if f.get("subsystem")}),
                    "total_ms": timings.get("total_ms"), "mount_ms": timings.get("mount_ms"),
                    "settle_ms": timings.get("settle_ms"), "actions_ms": timings.get("actions_ms"),
                    "engine": r.get("engine"), "tags": s.get("tags") or [],
                    "generator_version": (s.get("source") or {}).get("generator_version"),
                    "title": s.get("title"),
                    # coverage features of the scenario, for component/property filters
                    "_features": features(s),
                })
            return out
        return self._get("rows", build)

    def scenario(self, scenario_id: str) -> dict | None:
        for r in self.raw_results().value or []:
            if isinstance(r, dict) and (r.get("scenario") or {}).get("scenario_id") == scenario_id:
                return r
        # minimized / original cases embedded in issue reports
        for got in self.issues().values():
            rep = got.value if got.ok else None
            if not isinstance(rep, dict):
                continue
            for key in ("scenario", "minimal_scenario"):
                s = (rep.get("reproduction") or {}).get(key)
                if isinstance(s, dict) and s.get("scenario_id") == scenario_id:
                    return {"scenario": s, "comparison": None, "embedded_in": rep.get("issue_id")}
        return None

    def issue_rows(self) -> list[dict]:
        def build():
            out = []
            for iid, got in self.issues().items():
                if not got.ok or not isinstance(got.value, dict):
                    out.append({"issue_id": iid, "error": got.error})
                    continue
                r = got.value
                c = r.get("classification") or {}
                rep = r.get("reproduction") or {}
                mini = rep.get("minimization") or {}
                out.append({
                    "issue_id": iid, "severity": r.get("severity"), "status": r.get("status"),
                    "novelty": r.get("novelty"), "kind": c.get("kind"), "subsystem": c.get("subsystem"),
                    "stage": c.get("stage"), "component": ", ".join((c.get("component_types") or [])[:4]),
                    "property": c.get("property"), "count": (r.get("occurrences") or {}).get("count"),
                    "scenarios": len((r.get("occurrences") or {}).get("scenarios") or []),
                    "reproducible": rep.get("reproducible"), "minimized": rep.get("minimized"),
                    "min_size": f"{mini.get('start_size')}→{mini.get('final_size')}" if mini else None,
                    "confidence": (r.get("confidence") or {}).get("level"),
                    "root_cause": (r.get("root_cause") or {}).get("status"),
                    "fixed": (r.get("verification") or {}).get("fix_applied"),
                    "message": (r.get("evidence") or {}).get("message"),
                    "fingerprint": r.get("fingerprint"), "kind_group": (r.get("fingerprint") or "").split("|")[0],
                    "has_trace": bool((r.get("location") or {}).get("source_file")),
                })
            order = {s: i for i, s in enumerate(SEVERITIES)}
            # Same order the engine writes them: severity, then occurrences.
            out.sort(key=lambda x: (order.get(x.get("severity"), 9), -(x.get("count") or 0)))
            return out
        return self._get("issue_rows", build)

    def durations(self) -> dict:
        rows = self.rows()
        per_family: dict[str, list] = {}
        for r in rows:
            per_family.setdefault(r["family"] or "—", []).append(r["total_ms"])
        stages = {k: [r[k] for r in rows if r.get(k) is not None]
                  for k in ("mount_ms", "settle_ms", "actions_ms", "total_ms")}
        return {
            "total": percentiles([r["total_ms"] for r in rows]),
            "measured": sum(1 for r in rows if r["total_ms"] is not None),
            "rows": len(rows),
            "stage_mean": {k: (statistics.mean(v) if v else None) for k, v in stages.items()},
            "per_family": {f: {"n": len(v), **percentiles(v),
                               "mean": statistics.mean([x for x in v if x is not None]) if any(
                                   x is not None for x in v) else None}
                           for f, v in sorted(per_family.items())},
        }

    def discovery_curve(self) -> list[tuple[int, int]]:
        """Cumulative unique primary fingerprints in execution order (derived
        from results.jsonl with the engine's fingerprint function)."""
        seen, out = set(), []
        for r in self.raw_results().value or []:
            for f in (r.get("comparison") or {}).get("findings") or []:
                if f.get("primary", True):
                    seen.add(fingerprint(f))
            out.append((len(out) + 1, len(seen)))
        return out

    def discovery_by_family(self) -> dict[str, list[tuple[int, int]]]:
        """Per family: cumulative fingerprints it found first, by execution order."""
        seen, out, counts = set(), {}, {}
        for i, r in enumerate(self.raw_results().value or []):
            fam = (r.get("scenario") or {}).get("family") or "—"
            for f in (r.get("comparison") or {}).get("findings") or []:
                if f.get("primary", True):
                    fp = fingerprint(f)
                    if fp not in seen:
                        seen.add(fp)
                        counts[fam] = counts.get(fam, 0) + 1
            for name in set(counts) | {fam}:
                out.setdefault(name, []).append((i + 1, counts.get(name, 0)))
        return out

    def component_property_matrix(self) -> dict:
        exec_counts: dict[tuple, int] = {}
        for r in self.raw_results().value or []:
            for feat in features(r.get("scenario") or {}):
                if feat.startswith("prop_on:"):
                    _, comp, prop = feat.split(":", 2)
                    exec_counts[(comp, prop)] = exec_counts.get((comp, prop), 0) + 1
                elif feat.startswith("type:"):
                    exec_counts[(feat[5:], "*")] = exec_counts.get((feat[5:], "*"), 0) + 1
        issue_counts: dict[tuple, int] = {}
        for row in self.issue_rows():
            for comp in (row.get("component") or "").split(", "):
                if comp:
                    key = (comp, row.get("property") or "*")
                    issue_counts[key] = issue_counts.get(key, 0) + 1
        return {"executed": exec_counts, "issues": issue_counts}


def home_of(unit_path: Path) -> Path | None:
    """The engine home that holds a unit's ledger.json (shared by its runs)."""
    for p in [unit_path, *unit_path.parents]:
        if (p / "ledger.json").exists():
            return p
        if p == ROOT:
            break
    return None


def compare_units(a: Unit, b: Unit) -> dict:
    """Explicit two-unit comparison; both origins stay identified."""
    sa, sb = a.summary().value or {}, b.summary().value or {}
    ma, mb = sa.get("metrics") or {}, sb.get("metrics") or {}
    keys = sorted(set(ma) | set(mb))
    metric_rows = []
    for k in keys:
        va, vb = ma.get(k), mb.get(k)
        if isinstance(va, dict) or isinstance(vb, dict):
            continue
        delta = vb - va if isinstance(va, (int, float)) and isinstance(vb, (int, float)) else None
        metric_rows.append({"metric": k, "a": va, "b": vb, "delta": delta})
    ia = {r["issue_id"]: r for r in a.issue_rows() if "error" not in r}
    ib = {r["issue_id"]: r for r in b.issue_rows() if "error" not in r}
    config_diff = []
    for key, va, vb in (
        ("budget", (sa.get("config") or {}).get("budget"), (sb.get("config") or {}).get("budget")),
        ("batch", (sa.get("config") or {}).get("batch"), (sb.get("config") or {}).get("batch")),
        ("families", (sa.get("config") or {}).get("families"), (sb.get("config") or {}).get("families")),
        ("seed", sa.get("seed"), sb.get("seed")),
        ("git_commit", (sa.get("system") or {}).get("git_commit"), (sb.get("system") or {}).get("git_commit")),
        ("git_dirty", (sa.get("system") or {}).get("git_dirty"), (sb.get("system") or {}).get("git_dirty")),
        ("generator_version", (sa.get("system") or {}).get("generator_version"),
         (sb.get("system") or {}).get("generator_version")),
        ("engine", (sa.get("system") or {}).get("engine"), (sb.get("system") or {}).get("engine")),
        ("kind", a.meta.kind, b.meta.kind),
    ):
        if va != vb:
            config_diff.append({"field": key, "a": va, "b": vb})
    cov_a = (sa.get("coverage") or {})
    cov_b = (sb.get("coverage") or {})
    coverage_rows = [{"dimension": d, "a": (cov_a.get(d) or {}).get("verified"),
                      "b": (cov_b.get(d) or {}).get("verified"),
                      "universe": (cov_b.get(d) or cov_a.get(d) or {}).get("universe")}
                     for d in sorted(set(cov_a) | set(cov_b))]
    sa_ids = {r["scenario_id"] for r in a.rows()}
    sb_ids = {r["scenario_id"] for r in b.rows()}
    strat = []
    for fam in sorted(set(sa.get("strategies") or {}) | set(sb.get("strategies") or {})):
        x = (sa.get("strategies") or {}).get(fam) or {}
        y = (sb.get("strategies") or {}).get(fam) or {}
        strat.append({"family": fam, "a_executed": x.get("executed"), "b_executed": y.get("executed"),
                      "a_yield": x.get("yield"), "b_yield": y.get("yield")})
    return {
        "a": str(a.path), "b": str(b.path),
        "metrics": metric_rows,
        "issues_only_a": sorted(set(ia) - set(ib)),       # absent in B (resolved or not exercised)
        "issues_only_b": sorted(set(ib) - set(ia)),       # new in B
        "issues_both": sorted(set(ia) & set(ib)),
        "regressions_b": sorted(i for i, r in ib.items() if r.get("novelty") == "regression"),
        "config_diff": config_diff,
        "comparable": not config_diff,
        "coverage": coverage_rows,
        "strategies": strat,
        "scenarios_shared": len(sa_ids & sb_ids),
        "scenarios_only_a": len(sa_ids - sb_ids),
        "scenarios_only_b": len(sb_ids - sa_ids),
    }


def global_search(units: list[Unit], query: str, limit: int = 500) -> list[dict]:
    """Search ids/messages/fingerprints/titles/element ids inside each unit,
    returning hits labelled with the unit they come from."""
    q = query.strip().lower()
    out = []
    if not q:
        return out
    for u in units:
        if q in u.meta.name.lower() or q in (u.meta.run_id or "").lower():
            out.append({"unit": str(u.path), "type": "informe", "id": u.meta.name, "text": u.meta.note or ""})
        for r in u.issue_rows():
            hay = " ".join(str(r.get(k) or "") for k in ("issue_id", "message", "fingerprint", "component",
                                                       "property", "subsystem")).lower()
            if q in hay:
                out.append({"unit": str(u.path), "type": "defecto", "id": r["issue_id"],
                            "text": (r.get("message") or "")[:120]})
        raw = [x for x in u.raw_results().value or [] if isinstance(x, dict) and "scenario" in x]
        for r, x in zip(u.rows(), raw):
            hay = " ".join([r["scenario_id"] or "", r.get("title") or "", " ".join(r["issues"]),
                            " ".join(r["tags"])]).lower()
            if q in hay:
                out.append({"unit": str(u.path), "type": "escenario", "id": r["scenario_id"],
                            "text": f"{r['status']} · {r['family']}"})
            elif q in json.dumps(x["scenario"].get("screen"), ensure_ascii=False).lower():
                out.append({"unit": str(u.path), "type": "escenario", "id": r["scenario_id"],
                            "text": "coincidencia dentro de la pantalla JSON"})
            if len(out) >= limit:
                return out
    return out

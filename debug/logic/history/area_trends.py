"""Did conformance, memory and security improve or get worse?

Pure functions over the runs already on disk; the dashboard only draws what
they return. Two runs are compared only when they measured the same set
(same suite and test count for conformance, same case ids for memory and
security); every result is deterministic pass/fail, so any change in the
pass count is a real change and no noise threshold applies.

    series = conformance_series(Path("debug/artifacts/conformance/results"))
    status = conformance_status(series)
    runs = bench_series(Path("debug/benchmarks/leaks"), "leaks")
    status = bench_status(runs)
"""
from __future__ import annotations

import json
from pathlib import Path

IMPROVED, REGRESSED, MIXED, SAME, NOT_ENOUGH = "improved", "regressed", "mixed", "same", "not_enough_data"


def _load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _verdict(fixed: list, broken: list, delta: int = 0) -> str:
    """Tests that started passing and tests that stopped passing both count:
    a net gain that breaks other tests is "mixed", never "improved"."""
    if fixed and broken:
        return MIXED
    if broken or delta < 0:
        return REGRESSED
    return IMPROVED if fixed or delta > 0 else SAME


# ------------------------------------------------------------- conformance
def conformance_series(results_dir: Path) -> dict[str, list[dict]]:
    """{suite: [run, …]} oldest first; run = {at, file, total, pass, rate, results}."""
    out: dict[str, list[dict]] = {}
    for path in sorted(results_dir.glob("*.summary.json")) if results_dir.exists() else []:
        data = _load(path)
        if not isinstance(data, dict) or not data.get("suite"):
            continue
        counts = data.get("counts") or {}
        total = data.get("total") or sum(v for v in counts.values() if isinstance(v, int))
        results = data.get("resultsFile") or path.name.replace(".summary.json", ".jsonl")
        out.setdefault(data["suite"], []).append({
            "at": str(data.get("startedAt") or path.stem),
            "file": str(path),
            "total": total,
            "pass": counts.get("PASS", 0),
            "rate": data.get("passRate"),
            "results": str(path.parent / results),
        })
    for runs in out.values():
        runs.sort(key=lambda r: r["at"])
    return out


def _statuses(jsonl: str) -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        with open(jsonl, encoding="utf-8") as fh:
            for line in fh:
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if isinstance(row, dict) and row.get("id") is not None:
                    out[str(row["id"])] = str(row.get("status")).upper()
    except OSError:
        pass
    return out


def flips(older: dict[str, str], newer: dict[str, str]) -> tuple[list[str], list[str]]:
    """(fixed, broken): ids that became PASS, ids that stopped being PASS."""
    fixed = sorted(i for i, s in newer.items() if s == "PASS" and older.get(i) not in (None, "PASS"))
    broken = sorted(i for i, s in newer.items() if s != "PASS" and older.get(i) == "PASS")
    return fixed, broken


def conformance_status(series: dict[str, list[dict]]) -> dict:
    """Per suite: latest vs the previous run with the same test count.

    Returns {verdict, suites: [{suite, verdict, before, after, total, delta,
    fixed, broken, trend: [(at, rate)…], skipped}]}. The overall verdict is
    regressed if any suite regressed, else mixed if any suite is mixed, else
    improved if some improved, same if all compared suites are equal.
    """
    suites = []
    for suite, runs in sorted(series.items()):
        last = runs[-1]
        same = [r for r in runs if r["total"] == last["total"]]
        row = {"suite": suite, "total": last["total"], "after": last["pass"], "rate": last["rate"],
               "trend": [(r["at"], r["rate"]) for r in same], "skipped": len(runs) - len(same),
               "at": last["at"]}
        if len(same) < 2:
            row.update(verdict=NOT_ENOUGH, before=None, delta=None, fixed=[], broken=[])
        else:
            prev = same[-2]
            fixed, broken = flips(_statuses(prev["results"]), _statuses(last["results"]))
            delta = last["pass"] - prev["pass"]
            row.update(verdict=_verdict(fixed, broken, delta), before=prev["pass"], delta=delta, fixed=fixed,
                       broken=broken, prev_at=prev["at"])
        suites.append(row)
    return {"verdict": _overall([s["verdict"] for s in suites]), "suites": suites}


def _overall(verdicts: list[str]) -> str:
    compared = [v for v in verdicts if v != NOT_ENOUGH]
    if not compared:
        return NOT_ENOUGH
    for v in (REGRESSED, MIXED):
        if v in compared:
            return v
    return IMPROVED if IMPROVED in compared else SAME


# ---------------------------------------------------- memory and security
def bench_series(area_dir: Path, prefix: str) -> list[dict]:
    """Runs oldest first; run = {run, at, file, statuses {id: STATUS}}."""
    out = []
    for run in sorted(p for p in area_dir.glob("*") if p.is_dir()) if area_dir.exists() else []:
        files = sorted(run.glob(f"{prefix}-*.json"))
        data = _load(files[-1]) if files else None
        if not isinstance(data, dict):
            continue
        statuses = {str(r.get("id")): str(r.get("status")).upper()
                    for r in data.get("results") or [] if isinstance(r, dict)}
        out.append({"run": run.name, "at": str((data.get("metadata") or {}).get("timestamp") or run.name),
                    "file": str(files[-1]), "statuses": statuses})
    return out


def bench_status(runs: list[dict]) -> dict:
    """Latest full run vs the previous run of the same case set.

    The reference is the newest run that covers the most cases (an `--only`
    run of one case is not the state of the area). SKIP is neither pass nor
    fail and is left out of the rate.
    """
    if not runs:
        return {"verdict": NOT_ENOUGH, "runs": 0}
    size = max(len(r["statuses"]) for r in runs)
    full = [r for r in runs if len(r["statuses"]) == size]
    last = full[-1]
    same = [r for r in full if set(r["statuses"]) == set(last["statuses"])]

    def rate(r):
        judged = [s for s in r["statuses"].values() if s != "SKIP"]
        return round(100 * sum(1 for s in judged if s == "PASS") / len(judged), 2) if judged else None

    out = {"cases": size, "run": last["run"], "at": last["at"], "rate": rate(last),
           "pass": sum(1 for s in last["statuses"].values() if s == "PASS"),
           "fail": sorted(i for i, s in last["statuses"].items() if s in ("FAIL", "ERROR")),
           "trend": [(r["at"], rate(r)) for r in same], "skipped": len(runs) - len(same), "runs": len(runs)}
    if len(same) < 2:
        out.update(verdict=NOT_ENOUGH, fixed=[], broken=[])
        return out
    prev = same[-2]
    fixed, broken = flips(prev["statuses"], last["statuses"])
    out.update(verdict=_verdict(fixed, broken), fixed=fixed, broken=broken,
               prev_run=prev["run"], prev_at=prev["at"])
    return out

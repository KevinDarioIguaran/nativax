"""Persistent history for NativaX laboratory runs.

Snapshots are written as JSON under ``debug/history/runs/``. Each snapshot
records when the run happened, which git commit/branch it came from, which
sections were executed and the pass/fail/blocked/error outcome of every case.
"""
from __future__ import annotations

import datetime
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEBUG = HERE.parent
ROOT = DEBUG.parent
RUNS = HERE / "runs"
INDEX = HERE / "index.json"
LATEST = HERE / "latest.json"


def git_info() -> dict:
    def _run(*args):
        try:
            return subprocess.check_output(
                ["git", *args], cwd=ROOT, stderr=subprocess.DEVNULL,
                text=True).strip()
        except Exception:
            return ""
    return {
        "branch": _run("rev-parse", "--abbrev-ref", "HEAD"),
        "commit": _run("rev-parse", "HEAD"),
        "short": _run("rev-parse", "--short", "HEAD"),
        "dirty": bool(_run("status", "--porcelain")),
    }


def _slug(now: datetime.datetime, info: dict) -> str:
    return now.strftime("%Y%m%dT%H%M%SZ") + "-" + (info.get("short") or "nogit")


def save_run(results, *, sections, elapsed, command=None, label=None) -> Path:
    RUNS.mkdir(parents=True, exist_ok=True)
    now = datetime.datetime.now(datetime.timezone.utc)
    info = git_info()
    run_id = _slug(now, info)
    cases = {}
    for r in results:
        cases[r.cid] = {
            "section": r.section,
            "name": r.name,
            "status": r.status,
            "message": r.message,
            "duration_ms": round(r.duration_ms, 2),
        }
    sections_summary = {}
    for sec in sections:
        sec_results = [r for r in results if r.section == sec]
        from collections import Counter
        c = Counter(r.status for r in sec_results)
        sections_summary[str(sec)] = {
            "pass": c.get("pass", 0),
            "fail": c.get("fail", 0),
            "blocked": c.get("blocked", 0),
            "error": c.get("error", 0),
            "total": len(sec_results),
        }
    totals = {
        "pass": sum(v["pass"] for v in sections_summary.values()),
        "fail": sum(v["fail"] for v in sections_summary.values()),
        "blocked": sum(v["blocked"] for v in sections_summary.values()),
        "error": sum(v["error"] for v in sections_summary.values()),
        "total": len(results),
    }
    snapshot = {
        "run_id": run_id,
        "timestamp": now.isoformat(),
        "label": label,
        "command": command,
        "git": info,
        "elapsed_seconds": round(elapsed, 2),
        "sections": sections_summary,
        "totals": totals,
        "cases": cases,
    }
    path = RUNS / f"{run_id}.json"
    path.write_text(json.dumps(snapshot, indent=2) + "\n")
    LATEST.write_text(json.dumps(snapshot, indent=2) + "\n")
    # update index
    index = []
    if INDEX.exists():
        try:
            index = json.loads(INDEX.read_text())
        except Exception:
            index = []
    index.append({
        "run_id": run_id,
        "timestamp": snapshot["timestamp"],
        "git": info,
        "totals": totals,
        "path": str(path.relative_to(ROOT)),
    })
    INDEX.write_text(json.dumps(index, indent=2) + "\n")
    # Compact, AI-oriented digest (not meant for humans): only non-pass cases
    # and deltas vs the previous run, single-line JSON to save tokens.
    prev = None
    if len(index) >= 2:
        try:
            prev = load_run(index[-2]["run_id"])
        except Exception:
            prev = None
    nonpass = []
    for cid, info in cases.items():
        if info["status"] != "pass":
            nonpass.append({"id": cid, "section": info["section"],
                           "status": info["status"], "message": info["message"]})
    delta = {"improved": [], "regressed": [], "unblocked": [], "newly_blocked": []}
    if prev:
        prev_cases = prev.get("cases", {})
        for cid in set(prev_cases) | set(cases):
            os_ = prev_cases.get(cid, {}).get("status")
            ns_ = cases.get(cid, {}).get("status")
            if not os_ or not ns_ or os_ == ns_:
                continue
            if os_ in ("fail", "error", "blocked") and ns_ == "pass":
                delta["improved"].append(cid)
            elif os_ == "pass" and ns_ in ("fail", "error", "blocked"):
                delta["regressed"].append(cid)
            if os_ == "blocked" and ns_ != "blocked":
                delta["unblocked"].append(cid)
            if os_ != "blocked" and ns_ == "blocked":
                delta["newly_blocked"].append(cid)
    digest = {
        "run_id": run_id,
        "timestamp": snapshot["timestamp"],
        "git": info.get("short"),
        "totals": totals,
        "sections": sections_summary,
        "nonpass": nonpass,
        "delta_vs_prev": delta,
    }
    digest_path = HERE / "ai_digest.json"
    digest_path.write_text(json.dumps(digest, separators=(",", ":")) + "\n")
    snapshot["ai_digest"] = str(digest_path.relative_to(ROOT))

    return path


def list_runs() -> list[dict]:
    if not INDEX.exists():
        return []
    try:
        return json.loads(INDEX.read_text())
    except Exception:
        return []


def load_run(ref: str) -> dict:
    """Load a run by run_id, path, or 'latest'."""
    if ref == "latest":
        if not LATEST.exists():
            raise FileNotFoundError("no latest run recorded")
        return json.loads(LATEST.read_text())
    p = Path(ref)
    if not p.is_absolute():
        p = ROOT / ref
    if p.exists():
        return json.loads(p.read_text())
    # search by run_id
    for entry in list_runs():
        if entry.get("run_id") == ref:
            cand = ROOT / entry["path"]
            if cand.exists():
                return json.loads(cand.read_text())
    raise FileNotFoundError(f"run not found: {ref}")


def compare(old_ref: str, new_ref: str = "latest") -> int:
    old = load_run(old_ref)
    new = load_run(new_ref)
    print(f"OLD: {old['run_id']}  {old['timestamp']}  git={old['git'].get('short')}  totals={old['totals']}")
    print(f"NEW: {new['run_id']}  {new['timestamp']}  git={new['git'].get('short')}  totals={new['totals']}")
    # totals delta
    for key in ("pass", "fail", "blocked", "error", "total"):
        d = new["totals"].get(key, 0) - old["totals"].get(key, 0)
        if d:
            print(f"  {key}: {old['totals'].get(key,0)} -> {new['totals'].get(key,0)} ({d:+d})")
    # per-case transitions
    old_cases = old.get("cases", {})
    new_cases = new.get("cases", {})
    improved = []
    regressed = []
    newly_blocked = []
    unblocked = []
    for cid in sorted(set(old_cases) | set(new_cases)):
        os_ = old_cases.get(cid, {}).get("status")
        ns_ = new_cases.get(cid, {}).get("status")
        if os_ == ns_ or os_ is None or ns_ is None:
            continue
        if os_ in ("fail", "error", "blocked") and ns_ == "pass":
            improved.append((cid, os_, ns_))
        elif os_ == "pass" and ns_ in ("fail", "error", "blocked"):
            regressed.append((cid, os_, ns_))
        if os_ != "blocked" and ns_ == "blocked":
            newly_blocked.append(cid)
        if os_ == "blocked" and ns_ != "blocked":
            unblocked.append(cid)
    if improved:
        print(f"\nImproved ({len(improved)}):")
        for cid, a, b in improved:
            print(f"  {cid}: {a} -> {b}")
    if regressed:
        print(f"\nRegressed ({len(regressed)}):")
        for cid, a, b in regressed:
            print(f"  {cid}: {a} -> {b}")
    if unblocked:
        print(f"\nUnblocked ({len(unblocked)}): {', '.join(unblocked)}")
    if newly_blocked:
        print(f"\nNewly blocked ({len(newly_blocked)}): {', '.join(newly_blocked)}")
    if not (improved or regressed or unblocked or newly_blocked):
        print("\nNo per-case status changes.")
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] == "list":
        for e in list_runs():
            print(f"{e['run_id']}  {e['timestamp']}  pass={e['totals']['pass']} "
                  f"fail={e['totals']['fail']} blocked={e['totals']['blocked']} "
                  f"error={e['totals']['error']}")
        return 0
    if argv[0] == "compare":
        old = argv[1] if len(argv) > 1 else None
        new = argv[2] if len(argv) > 2 else "latest"
        if old is None:
            runs = list_runs()
            if len(runs) < 2:
                print("need at least two runs to compare", file=sys.stderr)
                return 1
            old = runs[-2]["run_id"]
        return compare(old, new)
    if argv[0] == "show":
        ref = argv[1] if len(argv) > 1 else "latest"
        data = load_run(ref)
        print(json.dumps(data["totals"], indent=2))
        print("sections:")
        for sec, v in data["sections"].items():
            print(f"  section {sec}: {v}")
        return 0
    print("usage: history.py [list|compare [old] [new]|show [ref]]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

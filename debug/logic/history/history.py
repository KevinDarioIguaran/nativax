#!/usr/bin/env python3
"""Run history for NativaX visual/perf measurements.

Stores immutable JSON snapshots of a run and compares them against the previous
run. The point is to answer "did it get better or worse?" with concrete
per-page/per-scenario deltas, not with a single score.
"""
from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VISUAL_DIR = ROOT / "debug" / "artifacts" / "visual"
PERF_DIR = ROOT / "debug" / "artifacts" / "perf"


def _git_commit() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return "unknown"


def _stamp() -> str:
    return datetime.now().strftime("%Y%m%dT%H%M%S")


def _area_dir(area: str) -> Path:
    if area == "visual":
        return VISUAL_DIR / "history"
    if area == "perf":
        return PERF_DIR / "history"
    raise ValueError(f"unknown area: {area}")


def _source_path(area: str) -> Path:
    if area == "visual":
        return VISUAL_DIR / "latest" / "results.json"
    if area == "perf":
        return PERF_DIR / "latest" / "results.json"
    raise ValueError(f"unknown area: {area}")


def _summary(area: str, payload: dict) -> dict:
    if area == "visual":
        rows = payload.get("rows") or []
        scored = [r for r in rows if isinstance(r.get("overall"), (int, float))]
        return {
            "pages": len(rows),
            "pass": sum(1 for r in rows if r.get("verdict") == "PASS"),
            "warn": sum(1 for r in rows if r.get("verdict") == "WARN"),
            "fail": sum(1 for r in rows if r.get("verdict") == "FAIL"),
            "invalid": sum(1 for r in rows if r.get("verdict") == "INVALID"),
            "mean_overall": (
                sum(r["overall"] for r in scored) / len(scored) if scored else None
            ),
            "mean_position": _mean([r.get("position") for r in rows]),
            "mean_layout": _mean([r.get("layout") for r in rows]),
            "mean_color": _mean([r.get("color") for r in rows]),
            "mean_design": _mean([r.get("design") for r in rows]),
            "mismatched_pct": _mean([r.get("mismatched_pct") for r in rows]),
            "mean_delta_e": _mean([r.get("mean_delta_e") for r in rows]),
            "ink_mismatch_pct": _mean([r.get("ink_mismatch_pct") for r in rows]),
        }
    rows = payload.get("results") or []
    ok_rows = [
        row for row in rows
        if (row.get("nativax") or {}).get("status") == "ok"
        and (row.get("chromium") or {}).get("status") == "ok"
    ]
    return {
        "scenarios": len(rows),
        "pass": sum(1 for r in rows if r.get("verdict") == "PASS"),
        "warn": sum(1 for r in rows if r.get("verdict") == "WARN"),
        "fail": sum(1 for r in rows if r.get("verdict") == "FAIL"),
        "invalid": sum(1 for r in rows if r.get("verdict") == "INVALID"),
        "mean_work_ratio": _mean([
            ((_work(r, "nativax") / _work(r, "chromium"))
             if _work(r, "chromium") > 0.0001 else None)
            for r in ok_rows
        ]),
        "max_frame_p95": _max([_frame(r, "p95") for r in ok_rows]),
        "max_frame_max": _max([_frame(r, "max") for r in ok_rows]),
        "mean_rss_peak_mb": _mean([_rss(r) for r in ok_rows]),
    }


def _mean(values):
    values = [v for v in values if isinstance(v, (int, float))]
    return sum(values) / len(values) if values else None


def _work(row, engine):
    data = row.get(engine) or {}
    return float(data.get("scenario_ms") or 0) + float(data.get("render_ms") or 0)


def _frame(row, key):
    value = ((row.get("nativax") or {}).get("frame_ms") or {}).get(key)
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _rss(row):
    value = (row.get("nativax") or {}).get("rss_peak_mb")
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _max(values):
    values = [v for v in values if v is not None]
    return max(values) if values else None


def record(area: str, source: Path | None = None, out: Path | None = None) -> Path:
    source = source or _source_path(area)
    if not source.exists():
        raise FileNotFoundError(source)
    payload = json.loads(source.read_text())
    out = out or _area_dir(area)
    out.mkdir(parents=True, exist_ok=True)
    stamp = _stamp()
    snapshot = {
        "area": area,
        "recorded_at": datetime.now().isoformat(timespec="seconds"),
        "git_commit": _git_commit(),
        "source": str(source),
        "summary": _summary(area, payload),
        "rows": payload.get("rows") or payload.get("results") or [],
    }
    destination = out / f"{stamp}.json"
    tmp = destination.with_suffix(".tmp")
    tmp.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False))
    tmp.replace(destination)
    return destination


def _load(area: str, directory: Path | None = None) -> list[Path]:
    directory = directory or _area_dir(area)
    if not directory.exists():
        return []
    return sorted(directory.glob("*.json"), key=lambda p: p.stat().st_mtime_ns)


def list_runs(area: str, directory: Path | None = None) -> list[dict]:
    runs = []
    for path in _load(area, directory):
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        runs.append({
            "file": str(path),
            "recorded_at": data.get("recorded_at"),
            "git_commit": data.get("git_commit"),
            "summary": data.get("summary") or {},
        })
    return runs


def _identity(row: dict, area: str) -> str:
    if area == "visual":
        return str(row.get("page"))
    return str(row.get("scenario"))


def _visual_delta(previous: dict, current: dict) -> list[dict]:
    previous_rows = {_identity(row, "visual"): row for row in previous.get("rows", [])}
    deltas = []
    for row in current.get("rows", []):
        old = previous_rows.get(_identity(row, "visual"))
        if not old:
            continue
        delta = {
            "id": _identity(row, "visual"),
            "overall": _delta(row.get("overall"), old.get("overall")),
            "position": _delta(row.get("position"), old.get("position")),
            "layout": _delta(row.get("layout"), old.get("layout")),
            "color": _delta(row.get("color"), old.get("color")),
            "design": _delta(row.get("design"), old.get("design")),
            "mismatched_pct": _delta(row.get("mismatched_pct"), old.get("mismatched_pct")),
            "ink_mismatch_pct": _delta(row.get("ink_mismatch_pct"), old.get("ink_mismatch_pct")),
            "mean_delta_e": _delta(row.get("mean_delta_e"), old.get("mean_delta_e")),
            "verdict": row.get("verdict"),
            "previous_verdict": old.get("verdict"),
        }
        if any(value is not None and value != 0 for key, value in delta.items() if key.endswith(("overall", "position", "layout", "color", "design", "mismatched_pct", "ink_mismatch_pct", "mean_delta_e"))):
            deltas.append(delta)
    return deltas


def _perf_delta(previous: dict, current: dict) -> list[dict]:
    previous_rows = {_identity(row, "perf"): row for row in previous.get("results", [])}
    deltas = []
    for row in current.get("results", []):
        old = previous_rows.get(_identity(row, "perf"))
        if not old:
            continue
        old_ratio = _work(old, "nativax") / _work(old, "chromium") if _work(old, "chromium") > 0.0001 else None
        new_ratio = _work(row, "nativax") / _work(row, "chromium") if _work(row, "chromium") > 0.0001 else None
        delta = {
            "id": _identity(row, "perf"),
            "verdict": row.get("verdict"),
            "previous_verdict": old.get("verdict"),
            "work_ratio": _delta(new_ratio, old_ratio),
            "nativa_ms": _delta(_work(row, "nativax"), _work(old, "nativax")),
            "chromium_ms": _delta(_work(row, "chromium"), _work(old, "chromium")),
            "p95_ms": _delta(_frame(row, "p95"), _frame(old, "p95")),
            "rss_peak_mb": _delta(_rss(row), _rss(old)),
        }
        if any(value is not None and value != 0 for key, value in delta.items() if key.endswith(("ratio", "ms", "mb"))):
            deltas.append(delta)
    return deltas


def _delta(new, old):
    try:
        n = float(new)
        o = float(old)
    except (TypeError, ValueError):
        return None
    if not (n == n and o == o):
        return None
    return round(n - o, 6)


def compare(area: str, directory: Path | None = None) -> dict:
    runs = _load(area, directory)
    if len(runs) < 2:
        raise RuntimeError(f"need at least two runs for {area}, found {len(runs)}")
    previous = json.loads(runs[-2].read_text())
    current = json.loads(runs[-1].read_text())
    if area == "visual":
        deltas = _visual_delta(previous, current)
    else:
        deltas = _perf_delta(previous, current)
    return {
        "area": area,
        "previous": previous.get("recorded_at"),
        "current": current.get("recorded_at"),
        "previous_commit": previous.get("git_commit"),
        "current_commit": current.get("git_commit"),
        "summary_previous": previous.get("summary"),
        "summary_current": current.get("summary"),
        "deltas": deltas,
    }


def _summary_delta_text(previous, current) -> list[str]:
    lines = []
    for key in sorted(set(previous or {}) | set(current or {})):
        p = previous.get(key) if isinstance(previous, dict) else None
        c = current.get(key) if isinstance(current, dict) else None
        delta = _delta(c, p)
        if delta is None and p == c:
            continue
        if isinstance(c, float):
            c = round(c, 3)
        if isinstance(p, float):
            p = round(p, 3)
        lines.append(f"- {key}: {p} → {c}" + (f" ({delta:+})" if delta is not None else ""))
    return lines


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    record_parser = sub.add_parser("record", help="Store a JSON snapshot")
    record_parser.add_argument("--area", required=True, choices=("visual", "perf"))
    record_parser.add_argument("--source")
    record_parser.add_argument("--out")
    list_parser = sub.add_parser("list", help="List stored snapshots")
    list_parser.add_argument("--area", required=True, choices=("visual", "perf"))
    list_parser.add_argument("--dir")
    compare_parser = sub.add_parser("compare", help="Compare the last two snapshots")
    compare_parser.add_argument("--area", required=True, choices=("visual", "perf"))
    compare_parser.add_argument("--dir")
    compare_parser.add_argument("--json", action="store_true")
    compare_parser.add_argument("--all", action="store_true", help="print all changed cases")
    self_parser = sub.add_parser("self-check", help="Run deterministic controls")
    args = parser.parse_args()

    if args.command == "record":
        destination = record(
            args.area,
            Path(args.source) if args.source else None,
            Path(args.out) if args.out else None,
        )
        print(destination)
        return 0
    if args.command == "list":
        for run in list_runs(args.area, Path(args.dir) if args.dir else None):
            print(f"{run['recorded_at']}  {run['git_commit']}  {run['summary']}")
        return 0
    if args.command == "compare":
        result = compare(args.area, Path(args.dir) if args.dir else None)
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(f"Área: {result['area']}")
            print(f"Anterior: {result['previous']} ({result['previous_commit']})")
            print(f"Actual:   {result['current']} ({result['current_commit']})")
            print("Resumen:")
            for line in _summary_delta_text(
                result["summary_previous"], result["summary_current"]
            ):
                print(line)
            print(f"Casos cambiados: {len(result['deltas'])}")
            for delta in result["deltas"][: (None if args.all else 20)]:
                print(json.dumps(delta, ensure_ascii=False))
        return 0
    if args.command == "self-check":
        previous = {"rows": [
            {"page": "a", "overall": 50, "position": 40, "layout": 50,
             "color": 60, "design": 90, "mismatched_pct": 20,
             "ink_mismatch_pct": 50, "mean_delta_e": 2},
        ]}
        current = {"rows": [
            {"page": "a", "overall": 60, "position": 50, "layout": 60,
             "color": 70, "design": 95, "mismatched_pct": 10,
             "ink_mismatch_pct": 40, "mean_delta_e": 1.5},
            {"page": "b", "overall": 80, "position": 70, "layout": 80,
             "color": 85, "design": 95, "mismatched_pct": 5,
             "ink_mismatch_pct": 10, "mean_delta_e": 1},
        ]}
        snapshot = _area_dir("visual")
        snapshot.mkdir(parents=True, exist_ok=True)
        old = snapshot / "selfcheck-old.json"
        new = snapshot / "selfcheck-new.json"
        old.write_text(json.dumps({"area": "visual", "recorded_at": "old", "git_commit": "old", "summary": _summary("visual", previous), "rows": previous["rows"]}))
        new.write_text(json.dumps({"area": "visual", "recorded_at": "new", "git_commit": "new", "summary": _summary("visual", current), "rows": current["rows"]}))
        # compare by temporary directory would need two files; instead exercise delta logic.
        deltas = _visual_delta(previous, current)
        assert len(deltas) == 1, deltas
        assert deltas[0]["overall"] == 10
        assert deltas[0]["id"] == "a"
        print("history self-check OK")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

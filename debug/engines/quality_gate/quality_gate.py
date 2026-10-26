#!/usr/bin/env python3
"""Headless quality gate for NativaX.

Runs (or reuses) the visual judge, the performance suite and the compatibility
suites, compares the result with a saved baseline and prints a machine-readable
verdict. Designed for an AI/CI to answer "is it better or worse?" without a UI.

    python3 debug/engines/quality_gate/quality_gate.py --run          # full run + comparison
    python3 debug/engines/quality_gate/quality_gate.py                # reuse latest artifacts
    python3 debug/engines/quality_gate/quality_gate.py --compat none  # visual + performance only
    python3 debug/engines/quality_gate/quality_gate.py --json         # JSON on stdout

    python3 debug/engines/quality_gate/quality_gate.py --out /tmp/gate   # write gate.json/.md there
    python3 debug/engines/quality_gate/quality_gate.py --current a.json b.json c.json  # repeated runs

Nothing is written unless asked: ``--out DIR`` writes gate.json, gate.md and
snapshot.json, ``--write-baseline PATH`` writes the current snapshot as a
baseline. ``--legacy-outputs`` restores the old behaviour (overwrite the
tracked progress/reports/quality-gate-latest.{json,md} and create the default
baseline when it is missing); perf_gui still reads that Markdown file.

Statuses per metric: improved, regressed, unchanged, inconclusive,
not_comparable (see gate_compare.py and
debug/architecture/metrics-gate-compat.md).

Exit codes: 0 = unchanged, improved, inconclusive or no baseline;
2 = regressed; 3 = missing measurements; 4 = not comparable; 64 = usage.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gate_compare  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
VISUAL_DIR = ROOT / ".visual" / "latest"
VISUAL_FALLBACK = ROOT / ".visual" / "runs" / "50projects50days"
PERF_DIR = ROOT / ".perf" / "latest"
RESULTS_DIR = ROOT / ".conformance" / "results"
BASELINE_DEFAULT = ROOT / "progress" / "reports" / "quality-baseline.json"
# Written only with --legacy-outputs (tracked files).
LEGACY_JSON = ROOT / "progress" / "reports" / "quality-gate-latest.json"
LEGACY_MD = ROOT / "progress" / "reports" / "quality-gate-latest.md"

VERDICTS = ("PASS", "WARN", "FAIL", "INVALID")


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def mean(values):
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def run(command, cwd, label):
    print(f"[gate] {label} ...", flush=True)
    started = datetime.now()
    result = subprocess.run(command, cwd=cwd)
    elapsed = (datetime.now() - started).total_seconds()
    print(f"[gate] {label}: exit {result.returncode} in {elapsed:.1f}s", flush=True)
    return result.returncode == 0


def visual_snapshot():
    source = None
    for candidate in (VISUAL_DIR / "results.json", VISUAL_FALLBACK / "results.json"):
        data = load_json(candidate)
        if data and data.get("rows"):
            source = candidate
            break
    if source is None:
        return None
    data = load_json(source)
    rows = data.get("rows") or []
    categories = {}
    for key in ("overall", "position", "layout", "color", "design"):
        categories[key] = mean([row.get(key) for row in rows])
    pixels = sum(row.get("pixels") or 0 for row in rows)
    mismatched = sum(row.get("mismatched_pixels") or 0 for row in rows)
    verdicts = {v: sum(1 for row in rows if row.get("verdict") == v) for v in VERDICTS}
    images = 0
    for row in rows:
        for key in ("chrome_png", "nativax_png", "diff_png"):
            if row.get(key) and Path(row[key]).exists():
                images += 1
    pages = [row.get("page") for row in rows]
    context = {
        "catalog_size": len(rows),
        "catalog_digest": gate_compare.digest(pages),
        "tool_version": data.get("version"),
        "reference": data.get("reference"),
        "viewport": data.get("viewport"),
        "scheme": data.get("scheme"),
        "suites": sorted({str(row.get("suite")) for row in rows if row.get("suite")}),
    }
    return {
        "context": context,
        "source": str(source),
        "pages": len(rows),
        "verdicts": verdicts,
        "categories": categories,
        "pixels": pixels,
        "mismatched_pixels": mismatched,
        "mismatched_pct": (100 * mismatched / pixels) if pixels else None,
        "mean_delta_e": mean([row.get("mean_delta_e") for row in rows]),
        "mean_ink_pct": mean([row.get("ink_mismatch_pct") for row in rows]),
        "images": images,
        "worst": sorted(
            ({"page": row.get("page"), "overall": row.get("overall"), "verdict": row.get("verdict")}
             for row in rows),
            key=lambda row: row.get("overall") or 0,
        )[:5],
    }


def perf_snapshot():
    data = load_json(PERF_DIR / "results.json")
    if not data:
        return None
    rows = data.get("results") or []
    work = {}
    ratios = {}
    for row in rows:
        nativa = row.get("nativax") or {}
        chromium = row.get("chromium") or {}
        ok = nativa.get("status") == "ok" and chromium.get("status") == "ok"
        nwork = (nativa.get("scenario_ms") or 0) + (nativa.get("render_ms") or 0)
        cwork = (chromium.get("scenario_ms") or 0) + (chromium.get("render_ms") or 0)
        work[row.get("scenario")] = nwork
        if ok and cwork > 0.0001:
            ratios[row.get("scenario")] = nwork / cwork
    app = load_json(PERF_DIR / "app-idle.json") or load_json(ROOT / ".perf" / "app-idle.json")
    context = {
        "catalog_size": len(rows),
        "catalog_digest": gate_compare.digest(row.get("scenario") for row in rows),
        "tool_version": data.get("version"),
        "reference": data.get("chrome"),
        "viewport": data.get("viewport"),
        "targets": data.get("targets"),
        "command": data.get("command"),
        "engine": sorted({str((row.get("nativax") or {}).get("engine"))
                          for row in rows if (row.get("nativax") or {}).get("engine")}),
    }
    return {
        "context": context,
        "scenarios": len(rows),
        "verdicts": {v: sum(1 for row in rows if row.get("verdict") == v) for v in VERDICTS},
        "work": work,
        "ratios": ratios,
        "idle": {
            "rss_mb": app.get("rss_tail_mb"),
            "cpu_pct": app.get("cpu_tail_pct"),
            "gpu_pct": app.get("gpu_busy_pct"),
            "status": app.get("status"),
        } if app else None,
    }


def newest_summary(prefix, exclude=()):
    files = [
        path
        for path in RESULTS_DIR.glob(f"{prefix}-*.summary.json")
        if not any(token in path.name for token in exclude)
    ]
    if not files:
        return None
    path = max(files, key=lambda p: p.stat().st_mtime)
    data = load_json(path)
    if not data:
        return None
    counts = data.get("counts") or {}
    return {
        "suite": data.get("suite") or prefix,
        "passRate": data.get("passRate"),
        "counts": counts,
        "command": data.get("command"),
        "startedAt": data.get("startedAt"),
        "path": str(path),
        **{key: data[key] for key in ("suiteCommit", "runnerVersion") if key in data},
    }


def compat_snapshot():
    suites = {
        "test262": newest_summary("test262"),
        "html5lib": newest_summary("html5lib"),
        "url": newest_summary("wpt-url"),
        "html_tree": newest_summary("wpt-html-tree"),
        "wpt": newest_summary("wpt", exclude=("wpt-url", "wpt-html-tree")),
    }
    suites = {name: value for name, value in suites.items() if value}
    return suites or None


def run_compat(mode):
    if mode == "none":
        return
    cwd = ROOT / "debug" / "engines" / "compatibility"
    if not (ROOT / ".conformance" / "suites").exists():
        print("[gate] compatibility suites not downloaded; skipping")
        return
    if mode == "full":
        run(["dart", "run", "bin/run_all.dart"], cwd, "compat full")
        return
    # Fast but meaningful: JS language, tokenizer, tree construction, URL and
    # a bounded DOM slice. Test262 takes ~1 minute on this machine.
    run(["dart", "run", "bin/run_html5lib.dart"], cwd, "compat html5lib")
    run(["dart", "run", "bin/run_html_tree.dart"], cwd, "compat tree")
    run(["dart", "run", "bin/run_url.dart"], cwd, "compat url")
    run(["dart", "run", "bin/run_test262.dart"], cwd, "compat test262")
    run(
        ["dart", "run", "bin/run_wpt.dart", "--dirs", "dom/nodes", "--limit", "200"],
        cwd,
        "compat wpt dom/nodes (200)",
    )


def environment_class():
    """Coarse machine class: OS, architecture, logical CPUs, CPU model.

    It describes the machine running the gate; artifacts reused from another
    machine are not detected (documented limitation)."""
    model = platform.processor() or ""
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                model = line.split(":", 1)[1].strip()
                break
    except OSError:
        pass
    return f"{platform.system()}-{platform.machine()}-{os.cpu_count()}cpu-{model or 'unknown'}"


def build_snapshot(baseline_path):
    visual = visual_snapshot()
    perf = perf_snapshot()
    context = {"global": {"environment_class": environment_class()}}
    if visual:
        context["visual"] = visual.pop("context")
    if perf:
        context["performance"] = perf.pop("context")
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "context": context,
        "visual": visual,
        "perf": perf,
        "compat": compat_snapshot(),
        "baseline_path": str(baseline_path),
    }


compare = gate_compare.compare


def markdown(snapshot, comparison):
    visual = snapshot.get("visual") or {}
    perf = snapshot.get("perf") or {}
    compat = snapshot.get("compat") or {}
    lines = [
        "# Quality gate: comparison with the baseline",
        "",
        f"- Generated: {snapshot.get('generated_at')}",
        f"- Verdict: **{comparison['verdict']}**",
        f"- Baseline: `{snapshot.get('baseline_path')}`",
    ]
    if snapshot.get("repeats"):
        lines.append(f"- Repeated runs aggregated: {snapshot['repeats']}")
    counts = comparison.get("counts") or {}
    if counts:
        lines.append("- Metrics: " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    lines += ["", "## Current state", "", "| Area | Metric | Value |", "|---|---|---:|"]
    if visual:
        categories = visual.get("categories") or {}
        lines += [
            f"| Visual | Pages | {visual.get('pages')} |",
            f"| Visual | Mean fidelity | {_fmt(categories.get('overall'))} % |",
            f"| Visual | Position / layout / color / design | "
            f"{_fmt(categories.get('position'))} / {_fmt(categories.get('layout'))} / "
            f"{_fmt(categories.get('color'))} / {_fmt(categories.get('design'))} % |",
            f"| Visual | Pixels with ΔE>2 | {visual.get('mismatched_pixels')} / {visual.get('pixels')} |",
        ]
    if perf:
        verdicts = perf.get("verdicts") or {}
        idle = perf.get("idle") or {}
        lines += [
            f"| Performance | Scenarios PASS/FAIL | {verdicts.get('PASS', 0)} / {verdicts.get('FAIL', 0)} |",
            f"| Performance | App idle RSS / CPU | {_fmt(idle.get('rss_mb'))} MB / {_fmt(idle.get('cpu_pct'))} % |",
        ]
    for name, data in compat.items():
        lines.append(f"| Compatibility | {name} | {_fmt(data.get('passRate'))} % |")

    lines += ["", "## Comparability", ""]
    areas = comparison.get("areas") or {}
    if comparison["verdict"] == "no_baseline":
        lines.append("No baseline was found; nothing was compared.")
    for area, info in sorted(areas.items()):
        state = "comparable" if info["comparable"] else "**not comparable**"
        lines.append(f"- {area}: {state}")
        for reason in info["reasons"]:
            lines.append(f"  - {reason}")
        if info.get("unverified"):
            lines.append(f"  - unverified (recorded by neither side): {', '.join(info['unverified'])}")

    shown = [c for c in comparison.get("changes", []) if c["status"] != "unchanged"]
    lines += ["", "## Changes", ""]
    if not shown:
        lines.append("No metric changed beyond its tolerance.")
    else:
        lines += ["| Area | Metric | Before | Now | Δ | Threshold | Status |",
                  "|---|---|---:|---:|---:|---:|---|"]
        for c in shown:
            if c["status"] == "not_comparable":
                lines.append(f"| {c['area']} | {c['metric']} | {_fmt(c['before'])} | {_fmt(c['after'])} | "
                             f"— | — | not_comparable |")
                continue
            threshold = max(c["min_effect"], c["noise_threshold"])
            lines.append(
                f"| {c['area']} | {c['metric']} | {_fmt(c['before'])} {c['unit']} | "
                f"{_fmt(c['after'])} {c['unit']} | {c['delta']:+.2f} | {threshold:.2f} "
                f"({c['noise_source']} noise) | {c['status']} |")
    lines += [
        "",
        "## Limits of this gate",
        "",
        "- Tolerances and assumed noise are documented in "
        "debug/architecture/metrics-gate-compat.md; assumed noise is a prior, "
        "pass several --current snapshots to measure it.",
        "- The environment class describes the machine running the gate, not "
        "the machine that produced reused artifacts.",
        "- No CPU stressors, soak tests, GPU counters or display FPS; video, audio, "
        "animated canvas and WebGL are not judged; network is blocked.",
    ]
    return "\n".join(lines) + "\n"


def _fmt(value):
    if value is None:
        return "—"
    try:
        return f"{float(value):.2f}"
    except (TypeError, ValueError):
        return str(value)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Headless NativaX quality gate")
    parser.add_argument("--run", action="store_true", help="run the suites; otherwise reuse latest artifacts")
    parser.add_argument("--no-visual", action="store_true")
    parser.add_argument("--no-perf", action="store_true")
    parser.add_argument("--compat", choices=["fast", "full", "reuse", "none"], default="reuse")
    parser.add_argument("--baseline", default=str(BASELINE_DEFAULT), help="baseline snapshot to read")
    parser.add_argument("--current", nargs="+", metavar="SNAPSHOT",
                        help="compare these snapshot files instead of the latest artifacts; "
                             "several files are repeated runs and give the measured noise")
    parser.add_argument("--out", metavar="DIR", help="write gate.json, gate.md and snapshot.json here")
    parser.add_argument("--write-baseline", metavar="PATH", help="write the current snapshot as a baseline")
    parser.add_argument("--legacy-outputs", action="store_true",
                        help="old behaviour: overwrite progress/reports/quality-gate-latest.{json,md} "
                             "and create the default baseline when missing")
    parser.add_argument("--save-baseline", action="store_true",
                        help="with --legacy-outputs: overwrite the --baseline file")
    parser.add_argument("--json", action="store_true", help="print the JSON result")
    args = parser.parse_args(argv)
    if args.save_baseline and not args.legacy_outputs:
        parser.error("--save-baseline needs --legacy-outputs; use --write-baseline PATH")
    if args.current and args.run:
        parser.error("--current and --run are exclusive")

    baseline_path = Path(args.baseline)
    if args.run:
        if not args.no_visual:
            run(
                ["dart", "run", "debug/engines/visual_comparison/bin/visual_check.dart",
                 "--suite", "50projects50days", "--out", str(VISUAL_DIR)],
                ROOT,
                "visual 50projects50days",
            )
        if not args.no_perf:
            run(
                ["dart", "run", "debug/engines/performance/bin/perf.dart", "run", "--out", str(PERF_DIR)],
                ROOT,
                "performance",
            )
        run_compat(args.compat)

    if args.current:
        snapshots = []
        for path in args.current:
            data = load_json(Path(path))
            if data is None:
                print(f"[gate] cannot read snapshot {path}", file=sys.stderr)
                return 3
            snapshots.append(data)
        try:
            snapshot = gate_compare.aggregate(snapshots) if len(snapshots) > 1 else snapshots[0]
        except ValueError as error:
            print(f"[gate] {error}", file=sys.stderr)
            return 4
        snapshot = dict(snapshot, baseline_path=str(baseline_path))
        snapshot.pop("comparison", None)
    else:
        snapshot = build_snapshot(baseline_path)
        if not snapshot["visual"] and not snapshot["perf"]:
            print("[gate] no measurements found", file=sys.stderr)
            print("Run: python3 debug/engines/quality_gate/quality_gate.py --run", file=sys.stderr)
            return 3

    baseline = load_json(baseline_path)
    comparison = gate_compare.compare(snapshot, baseline)
    result = dict(snapshot, comparison=comparison)
    report = markdown(snapshot, comparison)
    log = sys.stderr if args.json else sys.stdout

    written = []
    if args.out:
        out = Path(args.out)
        out.mkdir(parents=True, exist_ok=True)
        (out / "gate.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
        (out / "gate.md").write_text(report)
        (out / "snapshot.json").write_text(json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n")
        written.append(out / "gate.md")
    if args.write_baseline:
        target = Path(args.write_baseline)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n")
        print(f"[gate] baseline written: {target}", file=log)
    if args.legacy_outputs:
        LEGACY_JSON.parent.mkdir(parents=True, exist_ok=True)
        LEGACY_JSON.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
        LEGACY_MD.write_text(report)
        written.append(LEGACY_MD)
        if baseline is None or args.save_baseline:
            baseline_path.parent.mkdir(parents=True, exist_ok=True)
            baseline_path.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n")
            print(f"[gate] baseline {'created' if baseline is None else 'updated'}: {baseline_path}", file=log)

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(report)
    print(f"[gate] verdict: {comparison['verdict']}", file=log)
    for path in written:
        print(f"[gate] report: {path}", file=log)
    return EXIT_CODES.get(comparison["verdict"], 0)


EXIT_CODES = {"regressed": 2, "not_comparable": 4}


if __name__ == "__main__":
    sys.exit(main())

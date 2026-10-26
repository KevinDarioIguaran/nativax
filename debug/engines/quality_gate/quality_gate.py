#!/usr/bin/env python3
"""Headless quality gate for NativaX.

Runs (or reuses) the visual judge, the performance suite and the compatibility
suites, compares the result with a saved baseline and prints a machine-readable
verdict. Designed for an AI/CI to answer "is it better or worse?" without a UI.

    python3 debug/engines/quality_gate/quality_gate.py --run          # full run + comparison
    python3 debug/engines/quality_gate/quality_gate.py                # reuse latest artifacts
    python3 debug/engines/quality_gate/quality_gate.py --no-compat    # visual + performance only
    python3 debug/engines/quality_gate/quality_gate.py --json         # JSON on stdout

Exit codes: 0 = equal/better or baseline created, 2 = regression, 3 = missing
measurements. The detailed snapshot is written to
progress/reports/quality-gate-latest.json and .md.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VISUAL_DIR = ROOT / ".visual" / "latest"
VISUAL_FALLBACK = ROOT / ".visual" / "runs" / "50projects50days"
PERF_DIR = ROOT / ".perf" / "latest"
RESULTS_DIR = ROOT / ".conformance" / "results"
BASELINE_DEFAULT = ROOT / "progress" / "reports" / "quality-baseline.json"
GATE_JSON = ROOT / "progress" / "reports" / "quality-gate-latest.json"
GATE_MD = ROOT / "progress" / "reports" / "quality-gate-latest.md"

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
    return {
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
    return {
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


def compare(current, baseline):
    changes = []
    if not baseline:
        return {"verdict": "BASELINE", "changes": [], "regressions": [], "improvements": []}

    def add(area, name, before, after, unit="", higher_is_better=True, tolerance=0.5):
        if before is None or after is None:
            return
        delta = after - before
        status = "equal"
        if abs(delta) < tolerance:
            status = "equal"
        elif (delta > 0) == higher_is_better:
            status = "better"
        else:
            status = "worse"
        changes.append({
            "area": area,
            "metric": name,
            "before": before,
            "after": after,
            "delta": delta,
            "unit": unit,
            "status": status,
        })

    visual_now = current.get("visual") or {}
    visual_base = baseline.get("visual") or {}
    for key in ("overall", "position", "layout", "color", "design"):
        add("visual", key, (visual_base.get("categories") or {}).get(key),
            (visual_now.get("categories") or {}).get(key), " %", True, 0.5)
    for verdict in ("PASS", "FAIL"):
        add("visual", f"{verdict} pages",
            (visual_base.get("verdicts") or {}).get(verdict),
            (visual_now.get("verdicts") or {}).get(verdict),
            "", verdict == "PASS", 0.5)
    add("visual", "ink %", visual_base.get("mean_ink_pct"),
        visual_now.get("mean_ink_pct"), " %", False, 1.0)
    add("visual", "images", visual_base.get("images"),
        visual_now.get("images"), "", True, 0.5)

    perf_now = current.get("perf") or {}
    perf_base = baseline.get("perf") or {}
    for scenario, after in (perf_now.get("work") or {}).items():
        before = (perf_base.get("work") or {}).get(scenario)
        if before is None:
            continue
        add("performance", scenario, before, after, " ms", False, 10.0)
    for verdict in ("PASS", "FAIL"):
        add("performance", f"{verdict} scenarios",
            (perf_base.get("verdicts") or {}).get(verdict),
            (perf_now.get("verdicts") or {}).get(verdict),
            "", verdict == "PASS", 0.5)
    idle_now = (perf_now.get("idle") or {})
    idle_base = (perf_base.get("idle") or {})
    add("idle", "RSS MB", idle_base.get("rss_mb"), idle_now.get("rss_mb"), " MB", False, 5.0)
    add("idle", "CPU %", idle_base.get("cpu_pct"), idle_now.get("cpu_pct"), " %", False, 0.25)

    compat_now = current.get("compat") or {}
    compat_base = baseline.get("compat") or {}
    for suite, after in compat_now.items():
        before = (compat_base.get(suite) or {}).get("passRate")
        if before is None:
            continue
        add("compatibility", suite, before, after.get("passRate"), " %", True, 0.5)

    regressions = [change for change in changes if change["status"] == "worse"]
    improvements = [change for change in changes if change["status"] == "better"]
    verdict = "EQUAL"
    if regressions and not improvements:
        verdict = "WORSE"
    elif regressions and improvements:
        verdict = "MIXED"
    elif improvements:
        verdict = "BETTER"
    return {
        "verdict": verdict,
        "changes": changes,
        "regressions": regressions,
        "improvements": improvements,
    }


def markdown(snapshot, comparison):
    visual = snapshot.get("visual") or {}
    perf = snapshot.get("perf") or {}
    compat = snapshot.get("compat") or {}
    lines = [
        "# Quality gate — mejor/peor que la línea base",
        "",
        f"- Fecha: {snapshot['generated_at']}",
        f"- Veredicto: **{comparison['verdict']}**",
        f"- Baseline: `{snapshot['baseline_path']}`",
        "",
        "## Estado actual",
        "",
        "| Área | Métrica | Valor |",
        "|---|---|---:|",
    ]
    if visual:
        lines += [
            f"| Visual | Páginas | {visual['pages']} |",
            f"| Visual | Fidelidad media | {visual['categories'].get('overall', 0):.2f} % |",
            f"| Visual | Posición / layout / color / diseño | "
            f"{visual['categories'].get('position', 0):.1f} / {visual['categories'].get('layout', 0):.1f} / "
            f"{visual['categories'].get('color', 0):.1f} / {visual['categories'].get('design', 0):.1f} % |",
            f"| Visual | Píxeles ΔE>2 | {visual['mismatched_pixels']:,} / {visual['pixels']:,} |",
            f"| Visual | Imágenes generadas | {visual['images']} |",
        ]
    if perf:
        lines += [
            f"| Rendimiento | Escenarios PASS/FAIL | {perf['verdicts'].get('PASS', 0)} / {perf['verdicts'].get('FAIL', 0)} |",
            f"| Rendimiento | App idle RSS / CPU | "
            f"{_fmt((perf.get('idle') or {}).get('rss_mb'))} MB / "
            f"{_fmt((perf.get('idle') or {}).get('cpu_pct'))} % |",
        ]
    if compat:
        for name, data in compat.items():
            lines.append(f"| Compatibilidad | {name} | {_fmt(data.get('passRate'))} % |")
    lines += ["", "## Cambios frente a la base", ""]
    if comparison["verdict"] == "BASELINE":
        lines.append("No había baseline; se guardó el estado actual como referencia.")
    elif not comparison["changes"]:
        lines.append("Sin cambios comparables.")
    else:
        lines += ["| Área | Métrica | Antes | Ahora | Δ | Estado |", "|---|---|---:|---:|---:|---|"]
        for change in comparison["changes"]:
            if change["status"] == "equal" and abs(change["delta"]) < 0.01:
                continue
            lines.append(
                f"| {change['area']} | {change['metric']} | "
                f"{_fmt(change['before'])}{change['unit']} | "
                f"{_fmt(change['after'])}{change['unit']} | "
                f"{change['delta']:+.2f}{change['unit']} | {change['status']} |"
            )
    lines += ["", "## Regresiones", ""]
    if comparison["regressions"]:
        for change in comparison["regressions"]:
            lines.append(f"- **{change['area']} · {change['metric']}**: "
                         f"{_fmt(change['before'])}{change['unit']} → "
                         f"{_fmt(change['after'])}{change['unit']} "
                         f"({change['delta']:+.2f}{change['unit']})")
    else:
        lines.append("Ninguna detectada.")
    lines += [
        "",
        "## Límites de esta compuerta",
        "",
        "- Bajo carga de CPU real: los escenarios ejecutan DOM/scroll/JS, pero no lanzan "
        "estresores de CPU en paralelo, ni soak tests largos, ni concurrencia. La "
        "comparación visual se hace en reposo y con animaciones congeladas.",
        "- GPU/FPS reales: se mide trabajo de frame en CPU y RSS/CPU; la GPU no está "
        "expuesta en esta máquina y no se reportan FPS de pantalla ni rasterización GPU.",
        "- Vídeo, audio, canvas animado y WebGL no se juzgan.",
        "- La red se bloquea en ambos motores para que la comparación sea reproducible.",
        "- PassMark 2D HTML Scroll es propietario; se usa una escena equivalente.",
        "- Los números de una pasada tienen varianza; la compuerta compara cocientes y "
        "métricas con tolerancias, no FPS.",
    ]
    return "\n".join(lines) + "\n"


def _fmt(value):
    if value is None:
        return "—"
    try:
        return f"{float(value):.2f}"
    except (TypeError, ValueError):
        return str(value)


def main():
    parser = argparse.ArgumentParser(description="Headless NativaX quality gate")
    parser.add_argument("--run", action="store_true", help="run the suites; otherwise reuse latest artifacts")
    parser.add_argument("--no-visual", action="store_true")
    parser.add_argument("--no-perf", action="store_true")
    parser.add_argument("--compat", choices=["fast", "full", "reuse", "none"], default="reuse")
    parser.add_argument("--baseline", default=str(BASELINE_DEFAULT))
    parser.add_argument("--save-baseline", action="store_true")
    parser.add_argument("--json", action="store_true", help="print the JSON result")
    args = parser.parse_args()

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

    snapshot = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "visual": visual_snapshot(),
        "perf": perf_snapshot(),
        "compat": compat_snapshot(),
        "baseline_path": str(baseline_path),
    }
    if not snapshot["visual"] and not snapshot["perf"]:
        print("[gate] no measurements found", file=sys.stderr)
        print("Run: python3 debug/engines/quality_gate/quality_gate.py --run", file=sys.stderr)
        return 3

    baseline = load_json(baseline_path)
    comparison = compare(snapshot, baseline)
    snapshot["comparison"] = comparison
    GATE_JSON.parent.mkdir(parents=True, exist_ok=True)
    GATE_JSON.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n")
    GATE_MD.write_text(markdown(snapshot, comparison))

    if baseline is None or args.save_baseline:
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n")
        if baseline is None:
            comparison["verdict"] = "BASELINE"
            print(f"[gate] baseline created: {baseline_path}", file=sys.stderr if args.json else sys.stdout)
        else:
            print(f"[gate] baseline updated: {baseline_path}", file=sys.stderr if args.json else sys.stdout)

    if args.json:
        print(json.dumps(snapshot, indent=2, ensure_ascii=False))
        print(f"[gate] verdict: {comparison['verdict']}", file=sys.stderr)
        print(f"[gate] report: {GATE_MD}", file=sys.stderr)
    else:
        print(markdown(snapshot, comparison))
        print(f"\n[gate] verdict: {comparison['verdict']}")
        print(f"[gate] report: {GATE_MD}")
    if comparison["verdict"] == "WORSE" or comparison["verdict"] == "MIXED":
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

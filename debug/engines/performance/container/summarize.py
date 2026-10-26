#!/usr/bin/env python3
"""Summarize the per-container performance results into one matrix.

Discovers every `.perf/container/<name>/results.json`, reads its
`container.json` metadata when present and writes matrix.json/matrix.md.
"""
from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BASE = ROOT / ".perf" / "container"

KNOWN = {
    "desktop": ("2 CPUs · 2 GB", "2", "2g"),
    "mobile": ("1 CPU · 1 GB", "1", "1g"),
    "low": ("0.5 CPU · 768 MB", "0.5", "768m"),
}
ORDER = {"desktop": 0, "mobile": 1, "low": 2}


def work(engine):
    return (engine.get("scenario_ms") or 0) + (engine.get("render_ms") or 0)


def memory_mb(value):
    text = str(value or "").strip().lower()
    try:
        if text.endswith("g"):
            return int(float(text[:-1]) * 1024)
        if text.endswith("m"):
            return int(float(text[:-1]))
    except ValueError:
        pass
    return None


def load(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def main():
    entries = []
    for directory in BASE.iterdir() if BASE.exists() else []:
        if not directory.is_dir():
            continue
        results = directory / "results.json"
        if not results.exists():
            continue
        meta = load(directory / "container.json") or {}
        name = meta.get("id") or directory.name
        label = meta.get("label")
        cpus = meta.get("cpus")
        memory = meta.get("memory")
        if not label:
            label, cpus, memory = KNOWN.get(name, (f"{name} · custom", "?", "?"))
        entries.append({
            "id": name,
            "label": label,
            "cpus": cpus or "?",
            "memory": memory or "?",
            "path": results,
            "meta": meta,
        })
    entries.sort(key=lambda entry: (ORDER.get(entry["id"], 99), entry["id"]))

    configs = []
    results_by_config = {}
    scenarios = []
    for entry in entries:
        data = load(entry["path"]) or {}
        configs.append({
            "id": entry["id"],
            "label": entry["label"],
            "cpus": entry["cpus"],
            "memory": entry["memory"],
            "memory_mb": memory_mb(entry["memory"]),
            "exit_code": entry["meta"].get("exit_code"),
            "only": entry["meta"].get("only"),
        })
        rows = {}
        for row in data.get("results", []):
            scenario = row.get("scenario")
            if scenario not in scenarios:
                scenarios.append(scenario)
            nativa = row.get("nativax") or {}
            chrome = row.get("chromium") or {}
            both = nativa.get("status") == "ok" and chrome.get("status") == "ok"
            rows[scenario] = {
                "verdict": row.get("verdict"),
                "reasons": row.get("reasons", []),
                "nativa_ms": work(nativa),
                "chrome_ms": work(chrome),
                "ratio": (work(nativa) / work(chrome)) if both and work(chrome) > 0 else None,
                "nodes_nativa": nativa.get("nodes"),
                "nodes_chrome": chrome.get("nodes"),
                "frame_p95": (nativa.get("frame_ms") or {}).get("p95"),
                "frame_max": (nativa.get("frame_ms") or {}).get("max"),
                "rss_peak_mb": nativa.get("rss_peak_mb"),
                "cpu_peak_pct": nativa.get("cpu_peak_pct"),
                "status_nativa": nativa.get("status"),
                "status_chrome": chrome.get("status"),
            }
        results_by_config[entry["id"]] = rows

    matrix = {
        "generated_at": datetime.now().isoformat(),
        "image": "nativa-perf:local",
        "configs": configs,
        "scenarios": scenarios,
        "results": results_by_config,
    }
    out = BASE / "matrix.json"
    out.write_text(json.dumps(matrix, indent=2) + "\n")

    lines = [
        "# NativaX per-container performance matrix",
        "",
        f"- Generated: {matrix['generated_at']}",
        "- Isolation: Docker `--cpus`, `--memory`, `--network none`.",
        "- Chromium and `flutter test` run inside the same container.",
        "",
        "| Configuration | Docker CPU | Docker RAM |",
        "|---|---:|---:|",
    ]
    for config in configs:
        lines.append(f"| {config['label']} | {config['cpus']} | {config['memory']} |")
    lines.append("")
    for scenario in scenarios:
        lines += [f"## `{scenario}`", "",
                  "| Configuration | Verdict | NativaX ms | Chromium ms | Ratio | "
                  "Nodes N/C | Frame p95 | RSS arnés / RAM |",
                  "|---|---|---:|---:|---:|---:|---:|---:|"]
        for config in configs:
            row = results_by_config[config["id"]].get(scenario)
            if not row:
                lines.append(f"| {config['label']} | — | — | — | — | — | — | — |")
                continue
            ratio = f"{row['ratio']:.2f}x" if row["ratio"] is not None else "—"
            p95 = f"{row['frame_p95']:.1f} ms" if row["frame_p95"] else "—"
            lines.append(
                f"| {config['label']} | {row['verdict']} | "
                f"{row['nativa_ms']:.1f} ms | {row['chrome_ms']:.1f} ms | "
                f"{ratio} | {row['nodes_nativa']}/{row['nodes_chrome']} | "
                f"{p95} | {row['rss_peak_mb']:.0f} / {config['memory_mb']} MB |"
            )
        lines.append("")
    lines += [
        "## Notes",
        "",
        "- On low CPU quotas the Flutter test harness and Chromium share the same cgroup, "
        "so the numbers reflect contention, not just the runtime.",
        "- Offscreen frame times are `tester.pump()` CPU work, not GPU FPS.",
        "- RSS includes the Flutter test runner; the real app idle is measured separately.",
    ]
    md = BASE / "matrix.md"
    md.write_text("\n".join(lines) + "\n")
    print(md)
    print(out)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Summarize NativaX JSONL metrics without using FPS averages as a verdict.

The JSONL produced by MetricsOverlay has one record per 2 s window. Each record
already contains p50/p95/p99 for Flutter frame phases and for presentation
cadence. This script groups records by run label and by condition (the label
without the `_rN` suffix) and prints medians and worst-case values.

Usage:
    python3 tools/summarize_metrics.py /tmp/metrics.jsonl
    python3 tools/summarize_metrics.py /tmp/*.jsonl --csv /tmp/summary.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


def _get(record: dict[str, Any], *path: str, default: float = 0.0) -> float:
    value: Any = record
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return default
        value = value[key]
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _median(values: list[float]) -> float:
    return statistics.median(values) if values else 0.0


def _max(values: list[float]) -> float:
    return max(values) if values else 0.0


def _fmt(value: float, digits: int = 1) -> str:
    return f"{value:.{digits}f}"


def _condition(label: str) -> str:
    return re.sub(r"_r\d+$", "", label)


def summarize(records: list[dict[str, Any]], skip: int = 0,
              buffer: str | None = None,
              last: int = 0) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        if buffer is not None:
            actual = f"{int(_get(record, 'buffer_w'))}x{int(_get(record, 'buffer_h'))}"
            if actual != buffer:
                continue
        grouped[str(record.get("label") or "default")].append(record)
    if skip:
        grouped = {label: items[skip:] for label, items in grouped.items()}
    if last:
        grouped = {label: items[-last:] for label, items in grouped.items()}

    rows: list[dict[str, Any]] = []
    for label, items in grouped.items():
        frames = sum(int(item.get("frames", 0)) for item in items)
        jank = sum(int(item.get("jank", 0)) for item in items)
        present_p95 = [_get(item, "present_ms", "p95") for item in items]
        present_p99 = [_get(item, "present_ms", "p99") for item in items]
        decode_p95 = [_get(item, "decode_ms", "p95") for item in items]
        build_p95 = [_get(item, "build_ms", "p95") for item in items]
        raster_p95 = [_get(item, "raster_ms", "p95") for item in items]
        total_p95 = [_get(item, "total_ms", "p95") for item in items]
        width = int(_get(items[0], "buffer_w")) if items else 0
        height = int(_get(items[0], "buffer_h")) if items else 0
        rows.append(
            {
                "label": label,
                "condition": _condition(label),
                "windows": len(items),
                "frames": frames,
                "render_fps": _median([_get(item, "render_fps") for item in items]),
                "shown_fps": _median([_get(item, "shown_fps") for item in items]),
                "ui_fps": _median([_get(item, "ui_fps") for item in items]),
                "present_p50": _median([_get(item, "present_ms", "p50") for item in items]),
                "present_p95_med": _median(present_p95),
                "present_p95_max": _max(present_p95),
                "present_p99_max": _max(present_p99),
                "decode_p95_med": _median(decode_p95),
                "decode_p95_max": _max(decode_p95),
                "build_p95_med": _median(build_p95),
                "raster_p95_med": _median(raster_p95),
                "total_p95_med": _median(total_p95),
                "jank_pct": (jank * 100.0 / frames) if frames else 0.0,
                "buffer": f"{width}x{height}",
            }
        )
    rows.sort(key=lambda row: row["label"])
    return rows


def condition_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[row["condition"]].append(row)
    out: list[dict[str, Any]] = []
    for condition, items in grouped.items():
        frames = sum(int(item["frames"]) for item in items)
        jank = sum(item["jank_pct"] * item["frames"] / 100.0 for item in items)
        out.append(
            {
                "condition": condition,
                "runs": len(items),
                "windows": sum(int(item["windows"]) for item in items),
                "render_fps": _median([item["render_fps"] for item in items]),
                "shown_fps": _median([item["shown_fps"] for item in items]),
                "ui_fps": _median([item["ui_fps"] for item in items]),
                "present_p95_med": _median([item["present_p95_med"] for item in items]),
                "present_p95_max": _max([item["present_p95_max"] for item in items]),
                "present_p99_max": _max([item["present_p99_max"] for item in items]),
                "decode_p95_med": _median([item["decode_p95_med"] for item in items]),
                "build_p95_med": _median([item["build_p95_med"] for item in items]),
                "raster_p95_med": _median([item["raster_p95_med"] for item in items]),
                "total_p95_med": _median([item["total_p95_med"] for item in items]),
                "jank_pct": (jank * 100.0 / frames) if frames else 0.0,
                "buffer": items[0]["buffer"],
            }
        )
    out.sort(key=lambda row: row["condition"])
    return out


def print_table(title: str, rows: list[dict[str, Any]], key: str = "label") -> None:
    print(title)
    header = (
        f"{key:<14} {'win':>4} {'render':>7} {'shown':>7} {'UI':>7} "
        f"{'pres95':>8} {'pres99':>8} {'dec95':>7} {'build95':>8} "
        f"{'rast95':>7} {'tot95':>7} {'jank%':>6} {'buffer':>11}"
    )
    print(header)
    print("-" * len(header))
    for row in rows:
        print(
            f"{row[key]:<14} {row['windows']:>4d} "
            f"{row['render_fps']:>7.1f} {row['shown_fps']:>7.1f} {row['ui_fps']:>7.1f} "
            f"{row['present_p95_med']:>8.1f} {row['present_p99_max']:>8.1f} "
            f"{row['decode_p95_med']:>7.1f} {row['build_p95_med']:>8.1f} "
            f"{row['raster_p95_med']:>7.1f} {row['total_p95_med']:>7.1f} "
            f"{row['jank_pct']:>6.1f} {row['buffer']:>11}"
        )
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path, help="JSONL metrics files")
    parser.add_argument("--csv", type=Path, help="write the per-run table as CSV")
    parser.add_argument("--skip", type=int, default=0,
                        help="drop the first N windows of each run (warm-up)")
    parser.add_argument("--buffer", help="only keep windows with this buffer, e.g. 1280x720")
    parser.add_argument("--last", type=int, default=0,
                        help="keep only the last N windows of each run (steady state)")
    args = parser.parse_args()

    records: list[dict[str, Any]] = []
    for path in args.files:
        try:
            with path.open("r", encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                    except json.JSONDecodeError:
                        print(f"warning: ignoring malformed line in {path}", file=sys.stderr)
                        continue
                    if isinstance(record, dict):
                        records.append(record)
        except OSError as error:
            print(f"error: cannot read {path}: {error}", file=sys.stderr)
            return 2

    if not records:
        print("error: no metrics records found", file=sys.stderr)
        return 2

    rows = summarize(records, skip=args.skip, buffer=args.buffer, last=args.last)
    if not rows:
        print("error: no metrics records matched the filters", file=sys.stderr)
        return 2
    print(f"records: {len(records)} windows, {len(rows)} run(s)")
    if args.skip:
        print(f"warm-up skipped: {args.skip} windows per run")
    if args.buffer:
        print(f"buffer filter: {args.buffer}")
    if args.last:
        print(f"last windows: {args.last} per run")
    print()
    print_table("Per run", rows)
    print_table("Per condition (median across runs)", condition_rows(rows), key="condition")

    if args.csv:
        columns = list(rows[0].keys())
        with args.csv.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=columns)
            writer.writeheader()
            writer.writerows(rows)
        print(f"csv: {args.csv}")

    # A quick, explicit verdict. It is not a substitute for reading the table.
    print("Success gate at 1280x720 native (per condition):")
    for row in condition_rows(rows):
        checks = [
            ("shown>=45", row["shown_fps"] >= 45.0),
            ("present_p95<=25ms", row["present_p95_med"] <= 25.0),
            ("jank<2%", row["jank_pct"] < 2.0),
            ("UI>=50", row["ui_fps"] >= 50.0),
        ]
        detail = ", ".join(f"{name}={'PASS' if ok else 'FAIL'}" for name, ok in checks)
        print(f"  {row['condition']}: {detail}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

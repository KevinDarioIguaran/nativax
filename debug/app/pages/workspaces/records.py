"""Workspaces for engines whose evidence is a list of case records:
memory (leaks), security, microbenchmarks and compatibility. Each type keeps
its own columns, status vocabulary and detail view."""
from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path

from debug.app.components.basic import KeyValue, frame, label
from debug.app.components.charts import BarChart, LineChart
from debug.app.components.json_views import JsonTree
from debug.app.components.table import Table
from debug.styles import theme as t

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "debug" / "logic"))
import workspaces  # noqa: E402

COLUMNS = {
    "memory": [("id", "Case", 260, "w"), ("subsystem", "Subsystem", 100, "w"), ("status", "Status", 80, "w"),
               ("classification", "Leak classification", 150, "w"), ("samples", "Samples", 64, "e"),
               ("threshold_bytes", "Threshold bytes", 110, "e"), ("duration_ms", "ms", 70, "e"),
               ("reason", "Reason (engine)", 520, "w")],
    "security": [("id", "Case", 240, "w"), ("category", "Category", 100, "w"), ("severity", "Severity", 70, "w"),
                 ("status", "Status", 70, "w"), ("expected", "Expected", 260, "w"),
                 ("observed", "Observed", 260, "w"), ("remediation", "Remediation", 300, "w")],
    "microbenchmarks": [("name", "Benchmark", 240, "w"), ("category", "Category", 90, "w"),
                        ("language", "Lang", 60, "w"), ("median_ms", "Median ms", 84, "e"),
                        ("ci_low", "CI low", 70, "e"), ("ci_high", "CI high", 70, "e"),
                        ("p95_ms", "p95 ms", 70, "e"), ("stddev_ms", "Std dev", 70, "e"),
                        ("rounds", "Rounds", 60, "e"), ("warmup", "Warm-up", 60, "e"), ("unit", "Unit", 80, "w")],
    "compatibility": [("id", "Test", 520, "w"), ("status", "Status", 70, "w"), ("suite", "Suite", 110, "w"),
                      ("message", "Message", 520, "w")],
}
STATUS_KEY = {"memory": "status", "security": "status", "microbenchmarks": None, "compatibility": "status"}


class Workspace:
    def __init__(self, nb, app, ref, focus=None):
        kind = ref.type
        data = workspaces.LOADERS[kind](ref)
        tab = frame(nb)
        nb.add(tab, text={"memory": "Leak cases", "security": "Attack cases", "microbenchmarks": "Benchmarks",
                          "compatibility": "Tests"}[kind])
        if data["missing"]:
            label(tab, "Not available: " + "; ".join(data["missing"]), fg="status-unknown", anchor="w",
                  justify="left", wraplength=1300).pack(fill="x")
        rows = data["rows"]
        if kind == "compatibility":
            rows = [{"id": r.get("id") or r.get("name") or r.get("path"), "status": r.get("status"),
                     "suite": r.get("suite"), "message": r.get("message") or r.get("reason") or r.get("error"),
                     "_raw": r} for r in rows]
            if data.get("truncated"):
                label(tab, "Display limited to the first 20000 results; the full JSONL is in Files.",
                      fg="status-warning").pack(anchor="w")
        chart_row = frame(tab)
        chart_row.pack(fill="x")
        counts: dict[str, int] = {}
        for r in rows:
            key = str(r.get("classification") or r.get("status") or "measured")
            counts[key] = counts.get(key, 0) + 1
        status_chart = BarChart(chart_row, height=150)
        status_chart.pack(side="left", fill="x", expand=True)
        status_chart.set("Cases by status" + (" / classification" if kind == "memory" else ""),
                         [(k, v, k) for k, v in sorted(counts.items(), key=lambda kv: -kv[1])])
        self.detail_chart = LineChart(chart_row, height=150) if kind == "memory" else None
        if kind == "microbenchmarks":
            bench = BarChart(chart_row, height=150, unit=" ms")
            bench.pack(side="left", fill="x", expand=True)
            bench.set("Median per benchmark (with CI in the table)",
                      [(r["name"], r["median_ms"], "series-1") for r in rows[:12]])
        if self.detail_chart is not None:
            self.detail_chart.pack(side="left", fill="x", expand=True)
            self.detail_chart.set("Samples of the selected case", [])
        panes = tk.PanedWindow(tab, orient="vertical", bg=t.color("surface"), sashwidth=t.space("sm"))
        panes.pack(fill="both", expand=True)
        raw = JsonTree(panes)
        table = Table(panes, COLUMNS[kind], status_key=STATUS_KEY[kind],
                      on_select=lambda r: self._select(r, raw))
        table.set_rows(rows)
        panes.add(table, height=360)
        panes.add(raw)
        meta_tab = frame(nb, "surface-raised")
        nb.add(meta_tab, text="Run metadata")
        kv = KeyValue(meta_tab)
        meta = data.get("metadata") or data.get("summary") or {}
        kv.set([(k, v) for k, v in meta.items()] or [("metadata", None)])
        kv.pack(fill="x")
        if data.get("notes"):
            KeyValue(meta_tab).set([("notes", data["notes"])])

    def _select(self, row, raw):
        record = row.get("_raw") or row
        raw.show(record, [])
        if self.detail_chart is None:
            return
        samples = record.get("samples") or []
        series = []
        if samples and isinstance(samples[0], dict):
            numeric = [k for k, v in samples[0].items() if isinstance(v, (int, float)) and k not in ("batch",)]
            palette = ["series-1", "series-2", "series-3", "series-4", "series-5", "series-6"]
            for i, key in enumerate(numeric[:6]):
                series.append((key, [(j, s.get(key)) for j, s in enumerate(samples)], palette[i]))
        self.detail_chart.set(f"Samples of {row.get('id')} by batch", series, xlabel="batch")

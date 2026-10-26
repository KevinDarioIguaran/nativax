"""Performance workspace: per-scenario work against Chromium, frame p95, RSS,
reasons, the app-idle measurement and the raw scenario record."""
from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path

from debug.app.components.basic import KeyValue, frame, label
from debug.app.components.charts import BarChart, Histogram
from debug.app.components.json_views import JsonTree
from debug.app.components.table import Table
from debug.styles import theme as t

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "debug" / "logic"))
import workspaces  # noqa: E402


class Workspace:
    def __init__(self, nb, app, ref, focus=None):
        data = workspaces.performance(ref)
        tab = frame(nb)
        nb.add(tab, text="Scenarios")
        if data["missing"]:
            label(tab, "; ".join(data["missing"]), fg="status-error", anchor="w").pack(fill="x")
        charts = frame(tab)
        charts.pack(fill="x")
        ratio_chart = BarChart(charts, height=200, unit="x")
        ratio_chart.pack(side="left", fill="x", expand=True)
        hist = Histogram(charts, height=200)
        hist.pack(side="left", fill="x", expand=True)
        rows = data["rows"]
        worst = sorted((r for r in rows if r["ratio"] is not None), key=lambda r: -r["ratio"])[:12]
        ratio_chart.set("NativaX / Chromium work (highest 12; lower is better)",
                        [(r["scenario"], r["ratio"], r["verdict"]) for r in worst])
        hist.set_values("NativaX scenario + render time", [r["nativa_ms"] for r in rows])
        panes = tk.PanedWindow(tab, orient="vertical", bg=t.color("surface"), sashwidth=t.space("sm"))
        panes.pack(fill="both", expand=True)
        raw = JsonTree(panes)
        table = Table(panes, [
            ("scenario", "Scenario", 260, "w"), ("kind", "Kind", 80, "w"), ("verdict", "Verdict", 70, "w"),
            ("nativa_ms", "NativaX ms", 86, "e"), ("chrome_ms", "Chromium ms", 90, "e"), ("ratio", "Ratio", 64, "e"),
            ("p95", "Frame p95 ms", 90, "e"), ("rss_mb", "RSS MB", 70, "e"), ("nodes", "Nodes", 70, "e"),
            ("reasons", "Reasons (engine)", 520, "w")],
            status_key="verdict", on_select=lambda r: raw.show(r["_raw"], []))
        table.set_rows(rows)
        panes.add(table, height=380)
        panes.add(raw)
        idle_tab = frame(nb, "surface-raised")
        nb.add(idle_tab, text="App idle")
        kv = KeyValue(idle_tab)
        idle = data["idle"] or {}
        kv.set([(k, v) for k, v in idle.items() if not isinstance(v, (list, dict))] or
               [("app-idle.json", None)])
        kv.pack(fill="x")
        env_tab = frame(nb, "surface-raised")
        nb.add(env_tab, text="Environment")
        kv = KeyValue(env_tab)
        env = data["environment"] or {}
        kv.set([(k, v) for k, v in env.items()] or [("environment (results.json)", None)])
        kv.pack(fill="x")
        summary = data["summary"] or {}
        kv2 = KeyValue(env_tab)
        kv2.set([(f"summary.{k}", v) for k, v in summary.items()] or [("summary (results.json)", None)])
        kv2.pack(fill="x")

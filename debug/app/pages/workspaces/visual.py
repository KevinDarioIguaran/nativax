"""Visual-comparison workspace: per-page metrics, the original images side by
side with zoom and region inspection, per-element geometry and the capture
environment. Everything is read from the archived report."""
from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path
from tkinter import ttk

from debug.app.components.basic import KeyValue, frame, label, scroll_frame, section
from debug.app.components.charts import BarChart
from debug.app.components.images import ImagePanes
from debug.app.components.json_views import JsonTree
from debug.app.components.table import Table
from debug.styles import theme as t

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "debug" / "logic"))
import workspaces  # noqa: E402


class Workspace:
    def __init__(self, nb, app, ref, focus=None):
        self.app, self.ref = app, ref
        self.data = workspaces.visual(ref)
        self._pages_tab(nb)
        self._page_tab(nb)
        self.nb = nb
        if self.data["rows"]:
            target = focus if focus else self.data["rows"][0]["page"]
            self.pages.select_where("page", target)
            self.open_page(next((r for r in self.data["rows"] if r["page"] == target), self.data["rows"][0]),
                           switch=False)

    def _pages_tab(self, nb):
        tab = frame(nb)
        nb.add(tab, text="Pages")
        if self.data["missing"]:
            label(tab, "; ".join(self.data["missing"]), fg="status-error", anchor="w").pack(fill="x")
        self.chart = BarChart(tab, height=170, unit=" %",
                              on_click=lambda page: (self.pages.select_where("page", page)))
        self.chart.pack(fill="x")
        rows = self.data["rows"]
        self.chart.set("Overall score per page (worst 12)",
                       [(r["page"], r.get("overall"), r.get("verdict")) for r in
                        sorted(rows, key=lambda r: (r.get("overall") is None, r.get("overall") or 0))[:12]])
        self.pages = Table(tab, [
            ("page", "Page", 300, "w"), ("verdict", "Verdict", 70, "w"), ("overall", "Overall %", 76, "e"),
            ("position", "Position %", 80, "e"), ("layout", "Layout %", 76, "e"), ("color", "Color %", 70, "e"),
            ("design", "Design %", 76, "e"), ("mismatched_pct", "Pixels ΔE>2 %", 96, "e"),
            ("ink_mismatch_pct", "Ink mismatch %", 100, "e"), ("matched", "Matched", 66, "e"),
            ("missing", "Missing", 60, "e"), ("extra", "Extra", 50, "e"),
            ("environment_ok", "Env checks ok", 90, "e")],
            status_key="verdict", on_open=self.open_page)
        self.pages.set_rows(rows)
        self.pages.pack(fill="both", expand=True)
        label(tab, "Double-click a page to inspect its images, regions and elements.", role="caption").pack(anchor="w")

    def _page_tab(self, nb):
        self.page_tab = frame(nb)
        nb.add(self.page_tab, text="Page inspector")
        self.page_title = label(self.page_tab, "no page selected", role="heading", fg="text-primary", anchor="w")
        self.page_title.pack(fill="x")
        self.page_missing = label(self.page_tab, "", fg="status-unknown", anchor="w", justify="left",
                                  wraplength=1300)
        self.page_missing.pack(fill="x")
        panes = tk.PanedWindow(self.page_tab, orient="vertical", bg=t.color("surface"), sashwidth=t.space("sm"))
        panes.pack(fill="both", expand=True)
        self.images = ImagePanes(panes)
        panes.add(self.images, height=480)
        lower = ttk.Notebook(panes)
        panes.add(lower)
        self.regions = Table(lower, [("index", "#", 40, "e"), ("bbox", "Bounding box [x, y, w, h]", 220, "w"),
                                     ("pixels", "Pixels", 80, "e"), ("meanDeltaE", "Mean ΔE", 80, "e"),
                                     ("maxDeltaE", "Max ΔE", 80, "e"), ("elements", "Elements involved", 520, "w")],
                             on_select=lambda r: self.images.focus_region(r["index"]), height=8)
        lower.add(self.regions, text="Difference regions")
        self.elements = Table(lower, [("path", "Element", 320, "w"), ("tag", "Tag", 60, "w"),
                                      ("status", "Match", 70, "w"), ("dx", "dx", 54, "e"), ("dy", "dy", 54, "e"),
                                      ("dw", "dw", 54, "e"), ("dh", "dh", 54, "e"), ("iou", "IoU", 60, "e"),
                                      ("delta_e", "Mean ΔE", 64, "e"), ("cause", "Engine flag", 120, "w")],
                              height=8)
        lower.add(self.elements, text="Elements")
        env_holder = frame(lower, "surface-raised")
        lower.add(env_holder, text="Environment and metrics")
        self.env_inner = scroll_frame(env_holder)
        raw = frame(lower)
        lower.add(raw, text="Page report (raw)")
        self.page_raw = JsonTree(raw)
        self.page_raw.pack(fill="both", expand=True)

    def open_page(self, row, switch=True):
        page = workspaces.visual_page(Path(row["_dir"]))
        self.page_title.configure(text=f"{row['page']} — verdict {row.get('verdict')} · overall "
                                       f"{row.get('overall')} % · {row['_dir']}")
        self.page_missing.configure(text=("Not in this report: " + "; ".join(page["missing"])) if page["missing"] else "")
        regions = page["regions"] or []
        self.images.show([("Reference (Chromium)", page["images"]["chrome"]),
                          ("Actual (NativaX)", page["images"]["nativax"]),
                          ("Difference ΔE", page["images"]["diff"]),
                          ("Overlay", page["images"]["overlay"])], regions=regions)
        self.regions.set_rows([{"index": i, "bbox": r.get("bbox"), "pixels": r.get("pixels"),
                                "meanDeltaE": r.get("meanDeltaE"), "maxDeltaE": r.get("maxDeltaE"),
                                "elements": ", ".join(str(e.get("path")) for e in (r.get("elements") or [])[:6])}
                               for i, r in enumerate(regions)])
        el_rows = []
        elements = page["elements"] or {}
        for e in elements.get("rows") or [] if isinstance(elements, dict) else []:
            status = "missing" if e.get("missing") else "extra" if e.get("extra") else (
                "match" if e.get("position_match") and e.get("size_match") else "differs")
            el_rows.append({"path": e.get("path"), "tag": e.get("tag"), "status": status,
                            "dx": e.get("dx"), "dy": e.get("dy"), "dw": e.get("dw"), "dh": e.get("dh"),
                            "iou": e.get("iou"), "delta_e": e.get("color_mean_delta_e"),
                            "cause": "root cause" if e.get("root_cause") else "",
                            "_search": " ".join(str(x) for x in (e.get("style_mismatches") or []))})
        self.elements.set_rows(el_rows)
        for w in self.env_inner.winfo_children():
            w.destroy()
        section(self.env_inner, "Capture environment (environment.json)")
        kv = KeyValue(self.env_inner)
        env = page["environment"] or {}
        kv.set([(k, v) for k, v in env.items()] or [("environment.json", None)])
        kv.pack(fill="x")
        section(self.env_inner, "Pixel metrics (pixels.json)")
        kv = KeyValue(self.env_inner)
        px = page["pixels"] or {}
        totals = px.get("totals") if isinstance(px.get("totals"), dict) else {}
        kv.set([(k, v) for k, v in (totals or {}).items() if not isinstance(v, (list, dict))] or [("pixels.json", None)])
        kv.pack(fill="x")
        doc = page["regions_doc"]
        if isinstance(doc, dict):
            section(self.env_inner, "Region detection parameters (regions.json)")
            kv = KeyValue(self.env_inner)
            kv.set([(k, v) for k, v in doc.items() if k != "regions"])
            kv.pack(fill="x")
        self.page_raw.show(page["report"], [])
        if switch:
            self.nb.select(self.page_tab)

"""Global overview: counts by type and health, recent runs, failing and
incomplete reports, and engine-audit results. Every figure opens the
explorer filtered to the reports it counts."""
from __future__ import annotations

from debug.app.components.basic import fmt, frame, label
from debug.app.components.charts import BarChart
from debug.app.components.table import Table
from debug.styles import theme as t

TYPE_NAMES = {
    "bug_detection": "Bug detection", "visual_comparison": "Visual comparison", "performance": "Performance",
    "memory": "Memory", "compatibility": "Compatibility", "security": "Security",
    "microbenchmarks": "Microbenchmarks", "recommendations": "Recommendations", "quality_gate": "Quality gate",
    "engine_audit": "Engine audits",
}


class Page:
    def __init__(self, frm, app):
        self.app, self.frm = app, frm
        bar = frame(frm)
        bar.pack(fill="x")
        label(bar, "Overview", role="title", fg="text-primary").pack(side="left")
        label(bar, "measured counts from the report folders; click a figure to list its reports").pack(
            side="left", padx=t.space("lg"))
        self.grid = frame(frm)
        self.grid.pack(fill="x", pady=t.space("sm"))
        charts = frame(frm)
        charts.pack(fill="x")
        self.by_type = BarChart(charts, height=220, on_click=self._open_type)
        self.by_type.pack(side="left", fill="x", expand=True, padx=t.space("xs"))
        self.by_health = BarChart(charts, height=220, on_click=lambda h: app.page("explorer").set_filter(health=h)
                                  or app.show("explorer"))
        self.by_health.pack(side="left", fill="x", expand=True, padx=t.space("xs"))
        label(frm, "Needs attention — failed, aborted, incomplete or unreadable reports", role="heading",
              fg="text-primary").pack(anchor="w", pady=(t.space("md"), 0))
        self.attention = Table(frm, [("type", "Type", 140, "w"), ("id", "Report", 280, "w"),
                                     ("status", "Status", 90, "w"), ("health", "Health", 70, "w"),
                                     ("created_at", "Created", 190, "w"), ("summary", "Outcome", 420, "w"),
                                     ("problem", "Problem", 360, "w")],
                               status_key="health", height=8, on_open=self._open_row)
        self.attention.pack(fill="both", expand=True)
        label(frm, "Recent reports", role="heading", fg="text-primary").pack(anchor="w", pady=(t.space("md"), 0))
        self.recent = Table(frm, [("type", "Type", 140, "w"), ("id", "Report", 280, "w"),
                                  ("status", "Status", 90, "w"), ("health", "Health", 70, "w"),
                                  ("created_at", "Created", 190, "w"), ("commit", "Commit", 80, "w"),
                                  ("summary", "Outcome", 520, "w")],
                            status_key="health", height=8, page_size=25, on_open=self._open_row)
        self.recent.pack(fill="both", expand=True)

    def _open_type(self, name):
        key = next((k for k, v in TYPE_NAMES.items() if v == name), name)
        self.app.page("explorer").set_filter(type=key)
        self.app.show("explorer")

    def _open_row(self, row):
        ref = self.app.state.find(row["path"])
        if ref:
            self.app.open_report(ref)

    def refresh(self):
        refs = self.app.state.refs
        for w in self.grid.winfo_children():
            w.destroy()
        by_type: dict[str, int] = {}
        for r in refs:
            by_type[r.type] = by_type.get(r.type, 0) + 1
        tiles = [("Reports", len(refs), "folders found under debug/artifacts and debug/benchmarks", None)]
        for key, name in TYPE_NAMES.items():
            tiles.append((name, by_type.get(key, 0), f"type {key}", key))
        health = {h: sum(1 for r in refs if r.health == h) for h in ("error", "warn", "ok", "unknown")}
        tiles += [("With failures", health["error"], "engine verdict FAIL/ERROR or critical/high issues", "error"),
                  ("Health unknown", health["unknown"], "incomplete, unreadable or no outcome recorded", "unknown")]
        for i, (name, value, note, key) in enumerate(tiles):
            box = frame(self.grid, "surface-raised", padx=t.space("md"), pady=t.space("sm"),
                        highlightthickness=t.size("border"), highlightbackground=t.color("border-subtle"),
                        cursor="hand2")
            box.grid(row=i // 7, column=i % 7, sticky="nsew", padx=t.space("xs"), pady=t.space("xs"))
            value_label = label(box, fmt(value), role="metric", fg="text-primary", surface="surface-raised")
            value_label.pack(anchor="w")
            label(box, name, role="label", fg="text-primary", surface="surface-raised").pack(anchor="w")
            label(box, note, role="caption", surface="surface-raised", wraplength=180, justify="left").pack(anchor="w")
            action = (lambda k=key: (self.app.page("explorer").set_filter(
                health=k) if k in ("error", "unknown") else self.app.page("explorer").set_filter(type=k),
                self.app.show("explorer")))
            for w in (box, value_label):
                w.bind("<Button-1>", lambda _e, a=action: a())
        for c in range(7):
            self.grid.columnconfigure(c, weight=1)
        self.by_type.set("Reports by type", [(TYPE_NAMES.get(k, k), v, "series-1") for k, v in
                                             sorted(by_type.items(), key=lambda kv: -kv[1])])
        self.by_health.set("Reports by health", [(h, health[h], h) for h in ("error", "warn", "ok", "unknown")])
        attention = []
        for r in refs:
            problem = "; ".join(r.errors[:2])
            if r.status in ("failed", "aborted", "incomplete") or r.errors or r.health == "error":
                attention.append({**r.as_dict(), "problem": problem or r.summary})
        self.attention.set_rows(attention)
        self.recent.set_rows([r.as_dict() for r in refs[:200]])

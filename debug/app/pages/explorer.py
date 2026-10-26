"""Report explorer: a folder view (type → area → report) beside a searchable,
filterable, paginated table. Opening a row opens that report alone."""
from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from debug.app.components.basic import button, combo, frame, label
from debug.app.components.table import Table
from debug.styles import theme as t


class Page:
    def __init__(self, frm, app):
        self.app, self.frm = app, frm
        self.filters = {"type": "(all)", "health": "(all)", "status": "(all)", "layout": "(all)"}
        self.folder = None
        bar = frame(frm)
        bar.pack(fill="x")
        label(bar, "Report explorer", role="title", fg="text-primary").pack(side="left")
        self.sub = label(bar, "")
        self.sub.pack(side="left", padx=t.space("lg"))
        button(bar, "Compare selected (2)", self.compare_selected).pack(side="right")
        button(bar, "Export view…", self.export).pack(side="right", padx=t.space("sm"))
        button(bar, "Open", self.open_selected, primary=True).pack(side="right")
        filt = frame(frm)
        filt.pack(fill="x", pady=t.space("xs"))
        self.combos = {}
        for key in self.filters:
            label(filt, key.capitalize()).pack(side="left", padx=(t.space("md"), t.space("xs")))
            cb = combo(filt, ["(all)"], width=18, on_change=self._apply)
            cb.pack(side="left")
            self.combos[key] = cb
        self.path_label = label(frm, "", role="code-small", fg="accent", anchor="w")
        self.path_label.pack(fill="x")
        panes = tk.PanedWindow(frm, orient="horizontal", bg=t.color("surface"), sashwidth=t.space("sm"))
        panes.pack(fill="both", expand=True)
        left = frame(panes)
        panes.add(left, width=330, minsize=220)
        label(left, "Folders", role="heading", fg="text-primary").pack(anchor="w")
        self.tree = ttk.Treeview(left, show="tree", selectmode="browse")
        ys = ttk.Scrollbar(left, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=ys.set)
        self.tree.pack(side="left", fill="both", expand=True)
        ys.pack(side="left", fill="y")
        self.tree.bind("<<TreeviewSelect>>", self._tree_selected)
        self.tree.bind("<Double-1>", self._tree_open)
        right = frame(panes)
        panes.add(right)
        self.table = Table(right, [
            ("type", "Type", 130, "w"), ("area", "Area", 90, "w"), ("id", "Report id", 270, "w"),
            ("status", "Status", 86, "w"), ("health", "Health", 66, "w"), ("created_at", "Created", 180, "w"),
            ("commit", "Commit", 80, "w"), ("engine", "Engine", 140, "w"), ("layout", "Layout", 140, "w"),
            ("previous", "Previous in lineage", 200, "w"), ("summary", "Outcome", 420, "w"),
            ("problems", "Problems", 300, "w")],
            status_key="health", multi=True, on_open=self._open_row)
        self.table.pack(fill="both", expand=True)

    def set_query(self, query):
        self.table.search_var.set(query)

    def set_filter(self, **kw):
        for k, v in kw.items():
            self.filters[k] = v
        self.folder = None

    def refresh(self):
        refs = self.app.state.refs
        rows = []
        for r in refs:
            d = r.as_dict()
            d["problems"] = "; ".join(r.errors[:3])
            d["_search"] = f"{r.path} {r.lineage_key or ''}"
            rows.append(d)
        self.table.set_rows(rows, keep_page=True)
        for key, cb in self.combos.items():
            values = sorted({str(r.get(key)) for r in rows if r.get(key) is not None})
            cb.configure(values=["(all)", *values])
            cb.set(self.filters.get(key, "(all)") if self.filters.get(key) in values else "(all)")
        self._fill_tree(refs)
        self._apply()

    def _fill_tree(self, refs):
        self.tree.delete(*self.tree.get_children())
        groups: dict[str, dict[str, list]] = {}
        for r in refs:
            groups.setdefault(r.type, {}).setdefault(r.area, []).append(r)
        for type_name, areas in sorted(groups.items()):
            total = sum(len(v) for v in areas.values())
            node = self.tree.insert("", "end", iid=f"type::{type_name}", text=f"▸ {type_name}/  ({total})")
            for area, items in sorted(areas.items()):
                anode = self.tree.insert(node, "end", iid=f"area::{type_name}::{area}",
                                         text=f"{area}/  ({len(items)})")
                for r in items[:2000]:
                    self.tree.insert(anode, "end", iid=f"ref::{r.path}", text=r.id, tags=(r.health,))
        for health in ("error", "warn", "ok", "unknown"):
            self.tree.tag_configure(health, foreground=t.status_color(health))

    def _tree_selected(self, _e=None):
        sel = self.tree.selection()
        if not sel:
            return
        item = sel[0]
        if item.startswith("type::"):
            self.folder = ("type", item.split("::")[1], None)
        elif item.startswith("area::"):
            _, type_name, area = item.split("::", 2)
            self.folder = ("area", type_name, area)
        else:
            path = item.split("::", 1)[1]
            self.path_label.configure(text=f"selected: {path}")
            return
        self._apply()

    def _tree_open(self, _e=None):
        sel = self.tree.selection()
        if sel and sel[0].startswith("ref::"):
            ref = self.app.state.find(sel[0].split("::", 1)[1])
            if ref:
                self.app.open_report(ref)

    def _apply(self):
        sel = {k: cb.get() for k, cb in self.combos.items() if cb.get() != "(all)"}
        self.filters.update({k: cb.get() for k, cb in self.combos.items()})
        folder = self.folder

        def ok(r):
            if folder:
                kind, type_name, area = folder
                if r["type"] != type_name or (kind == "area" and r["area"] != area):
                    return False
            return all(str(r.get(k)) == v for k, v in sel.items())
        self.table.set_predicate(ok)
        where = "all folders" if not folder else f"{folder[1]}/" + (f"{folder[2]}/" if folder[2] else "")
        self.path_label.configure(text=f"folder: {where}")
        self.sub.configure(text=f"{len(self.table.view_rows):,} of {len(self.table.all_rows):,} reports")

    def _open_row(self, row):
        ref = self.app.state.find(row["path"])
        if ref:
            self.app.open_report(ref)

    def open_selected(self):
        rows = self.table.selected_rows()
        if rows:
            self._open_row(rows[0])

    def compare_selected(self):
        rows = self.table.selected_rows()
        if len(rows) != 2:
            messagebox.showinfo("Compare", "Select exactly two reports (Ctrl+click).")
            return
        cmp = self.app.page("compare")
        cmp.pair = (rows[0]["path"], rows[1]["path"])
        self.app.show("compare")

    def export(self):
        path = filedialog.asksaveasfilename(defaultextension=".csv", initialfile="reports.csv",
                                            filetypes=[("CSV", "*.csv"), ("JSON", "*.json")])
        if path:
            n = self.table.export(path)
            self.app.set_status(f"{n} rows exported to {Path(path).name}")

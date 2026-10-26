"""Sortable, filterable, paginated table. Search and filters run over all
rows; only the visible page is inserted, so large tables stay responsive."""
from __future__ import annotations

import csv
import json
import tkinter as tk
from tkinter import ttk

from debug.app.components.basic import copy, entry, fmt, frame, label, button
from debug.styles import theme as t
from debug.styles.tokens import STATUS


def _sortable(v):
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return (0, v, "")
    return (1, 0, fmt(v).lower())


class Table(tk.Frame):
    def __init__(self, master, columns, *, page_size=None, on_select=None, on_open=None,
                 status_key=None, multi=False, height=12, searchable=True):
        super().__init__(master, bg=t.color("surface"))
        self.columns = columns          # [(key, heading, width, anchor)]
        self.page_size = page_size or t.size("page-size")
        self.on_select, self.on_open, self.status_key = on_select, on_open, status_key
        self.all_rows: list[dict] = []
        self.view_rows: list[dict] = []
        self.page = 0
        self.sort_key, self.sort_desc = None, False
        self.query = ""
        self.predicate = None
        top = frame(self)
        top.pack(fill="x")
        self.search_var = tk.StringVar()
        if searchable:
            label(top, "Search").pack(side="left")
            self.search = entry(top, 28, self.search_var)
            self.search.pack(side="left", padx=t.space("sm"))
            self.search_var.trace_add("write", lambda *_: self._set_query(self.search_var.get()))
        self.pager = label(top, "")
        self.pager.pack(side="right")
        button(top, "Next ▶", self.next_page).pack(side="right", padx=t.space("xs"))
        button(top, "◀ Prev", self.prev_page).pack(side="right", padx=t.space("xs"))
        body = frame(self)
        body.pack(fill="both", expand=True)
        self.tree = ttk.Treeview(body, columns=[c[0] for c in columns], show="headings",
                                 selectmode="extended" if multi else "browse", height=height)
        for key, text, width, anchor in columns:
            self.tree.heading(key, text=text, command=lambda k=key: self.sort_by(k))
            self.tree.column(key, width=width, anchor=anchor, stretch=width >= 200)
        ys = ttk.Scrollbar(body, orient="vertical", command=self.tree.yview)
        xs = ttk.Scrollbar(self, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=ys.set, xscrollcommand=xs.set)
        self.tree.pack(side="left", fill="both", expand=True)
        ys.pack(side="left", fill="y")
        xs.pack(fill="x")
        for status, token in STATUS.items():
            self.tree.tag_configure(f"s:{status}", foreground=t.color(token))
        self.tree.tag_configure("stripe", background=t.color("surface-stripe"))
        self.tree.bind("<<TreeviewSelect>>", self._selected)
        self.tree.bind("<Double-1>", self._opened)
        self.tree.bind("<Return>", self._opened)
        self.tree.bind("<Button-3>", self._menu)

    def set_rows(self, rows, keep_page=False):
        self.all_rows = list(rows)
        if not keep_page:
            self.page = 0
        self.refresh()

    def set_predicate(self, fn):
        self.predicate = fn
        self.page = 0
        self.refresh()

    def _set_query(self, q):
        self.query = q.strip().lower()
        self.page = 0
        self.refresh()

    def sort_by(self, key):
        self.sort_desc = not self.sort_desc if self.sort_key == key else False
        self.sort_key = key
        self.refresh()

    def refresh(self):
        rows = self.all_rows
        if self.predicate:
            rows = [r for r in rows if self.predicate(r)]
        if self.query:
            keys = [c[0] for c in self.columns]
            terms = self.query.split()
            rows = [r for r in rows if all(term in (" ".join(fmt(r.get(k)) for k in keys) + " "
                                                    + str(r.get("_search", ""))).lower() for term in terms)]
        if self.sort_key:
            k = self.sort_key
            present = [r for r in rows if r.get(k) is not None]
            missing = [r for r in rows if r.get(k) is None]
            rows = sorted(present, key=lambda r: _sortable(r.get(k)), reverse=self.sort_desc) + missing
        self.view_rows = rows
        pages = max(1, (len(rows) + self.page_size - 1) // self.page_size)
        self.page = min(self.page, pages - 1)
        start = self.page * self.page_size
        visible = rows[start:start + self.page_size]
        self.tree.delete(*self.tree.get_children())
        for i, r in enumerate(visible):
            tags = []
            if self.status_key is not None:
                tags.append(f"s:{str(r.get(self.status_key) or '').lower()}")
            if i % 2:
                tags.append("stripe")
            self.tree.insert("", "end", iid=str(start + i), tags=tags,
                             values=[fmt(r.get(c[0])) for c in self.columns])
        for key, text, *_ in self.columns:
            arrow = (" ▼" if self.sort_desc else " ▲") if key == self.sort_key else ""
            self.tree.heading(key, text=text + arrow)
        shown = f"{start + 1 if visible else 0}–{start + len(visible)}"
        self.pager.configure(text=f"rows {shown} of {len(rows):,} (total {len(self.all_rows):,}) · "
                                  f"page {self.page + 1}/{pages}")

    def next_page(self):
        if (self.page + 1) * self.page_size < len(self.view_rows):
            self.page += 1
            self.refresh()

    def prev_page(self):
        if self.page:
            self.page -= 1
            self.refresh()

    def selected_rows(self):
        return [self.view_rows[int(i)] for i in self.tree.selection() if int(i) < len(self.view_rows)]

    def select_where(self, key, value) -> bool:
        for index, r in enumerate(self.view_rows):
            if r.get(key) == value:
                self.page = index // self.page_size
                self.refresh()
                self.tree.selection_set(str(index))
                self.tree.see(str(index))
                return True
        return False

    def _selected(self, _e=None):
        rows = self.selected_rows()
        if rows and self.on_select:
            self.on_select(rows[0])

    def _opened(self, _e=None):
        rows = self.selected_rows()
        if rows and self.on_open:
            self.on_open(rows[0])

    def _menu(self, event):
        item = self.tree.identify_row(event.y)
        if not item:
            return
        self.tree.selection_set(item)
        row = self.view_rows[int(item)]
        col = self.tree.identify_column(event.x)
        key = self.columns[int(col[1:]) - 1][0] if col else self.columns[0][0]
        menu = tk.Menu(self, tearoff=0, bg=t.color("surface-control"), fg=t.color("text-primary"),
                       activebackground=t.color("surface-hover"))
        menu.add_command(label=f"Copy “{key}”", command=lambda: copy(self, fmt(row.get(key))))
        menu.add_command(label="Copy row as JSON", command=lambda: copy(self, json.dumps(
            {k: v for k, v in row.items() if not k.startswith("_")}, ensure_ascii=False, indent=2, default=str)))
        if self.on_open:
            menu.add_command(label="Open", command=lambda: self.on_open(row))
        menu.tk_popup(event.x_root, event.y_root)

    def export(self, path: str) -> int:
        """Writes the current filtered rows (all pages) as CSV or JSON."""
        rows = [{k: v for k, v in r.items() if not k.startswith("_")} for r in self.view_rows]
        if path.endswith(".json"):
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(rows, fh, indent=2, ensure_ascii=False, default=str)
        else:
            keys = [c[0] for c in self.columns]
            with open(path, "w", newline="", encoding="utf-8") as fh:
                w = csv.DictWriter(fh, fieldnames=keys, extrasaction="ignore")
                w.writeheader()
                for r in rows:
                    w.writerow({k: fmt(r.get(k)) for k in keys})
        return len(rows)

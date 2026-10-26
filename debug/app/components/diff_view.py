"""Structural JSON diff list with per-kind filters and jump-to-node."""
from __future__ import annotations

import json
import tkinter as tk

from debug.app.components.basic import check, frame, label
from debug.app.components.table import Table
from debug.styles import theme as t

KINDS = ("added", "removed", "changed", "moved", "type_changed")


def _short(v):
    if v is None:
        return None
    text = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
    return text if len(text) < 200 else text[:197] + "…"


class DiffView(tk.Frame):
    def __init__(self, master, on_jump=None):
        super().__init__(master, bg=t.color("surface"))
        self.on_jump = on_jump
        bar = frame(self)
        bar.pack(fill="x")
        self.summary = label(bar, "", fg="text-primary")
        self.summary.pack(side="left")
        self.vars = {}
        for kind in KINDS:
            v = tk.BooleanVar(value=True)
            self.vars[kind] = v
            check(bar, kind.replace("_", " "), v, self.refresh).pack(side="right")
        self.table = Table(self, [("op", "Change", 100, "w"), ("path", "Path", 420, "w"),
                                  ("before", "Before", 300, "w"), ("after", "After", 300, "w")],
                           status_key="op", on_open=lambda r: self.on_jump and self.on_jump(r["path"]))
        self.table.pack(fill="both", expand=True)
        self.changes = []

    def set(self, changes, title=""):
        self.changes = [{**c, "before": _short(c.get("before")), "after": _short(c.get("after"))}
                        for c in changes]
        counts: dict[str, int] = {}
        for c in changes:
            counts[c["op"]] = counts.get(c["op"], 0) + 1
        self.summary.configure(text=f"{title} · " + (" · ".join(f"{k} {v}" for k, v in counts.items())
                                                       or "no structural differences"))
        self.refresh()

    def refresh(self):
        self.table.set_rows([c for c in self.changes if self.vars[c["op"]].get()])

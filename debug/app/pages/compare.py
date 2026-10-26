"""Compare two reports explicitly. Comparability is checked first
(catalog.comparable); only then are metrics judged (compare_runs) and the
chosen JSON files diffed structurally. Both origins stay labelled."""
from __future__ import annotations

import json
import sys
import tkinter as tk
from pathlib import Path
from tkinter import ttk

from debug.app.components.basic import button, frame, label
from debug.app.components.diff_view import DiffView
from debug.app.components.table import Table
from debug.styles import theme as t

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "debug" / "logic"))
import catalog  # noqa: E402
import compare_runs  # noqa: E402
import jsondiff  # noqa: E402

AREAS = {"visual_comparison": "visual", "performance": "perf"}


class Page:
    def __init__(self, frm, app):
        self.app, self.frm = app, frm
        self.pair = None
        bar = frame(frm)
        bar.pack(fill="x")
        label(bar, "Compare reports", role="title", fg="text-primary").pack(side="left")
        label(bar, "two reports side by side; incompatible pairs are refused, not guessed").pack(
            side="left", padx=t.space("lg"))
        pick = frame(frm)
        pick.pack(fill="x", pady=t.space("xs"))
        label(pick, "A (older)").pack(side="left")
        self.a = ttk.Combobox(pick, width=60, state="readonly")
        self.a.pack(side="left", padx=t.space("sm"))
        label(pick, "B (newer)").pack(side="left")
        self.b = ttk.Combobox(pick, width=60, state="readonly")
        self.b.pack(side="left", padx=t.space("sm"))
        button(pick, "Compare", self.run, primary=True).pack(side="left", padx=t.space("sm"))
        self.banner = label(frm, "", fg="text-secondary", anchor="w", justify="left", wraplength=1300)
        self.banner.pack(fill="x", pady=t.space("xs"))
        self.nb = ttk.Notebook(frm)
        self.nb.pack(fill="both", expand=True)
        self.items = Table(self.nb, [("id", "Item", 360, "w"), ("status", "Status", 100, "w"),
                                     ("before", "A", 100, "e"), ("after", "B", 100, "e"),
                                     ("delta", "B − A", 100, "e")], status_key="status")
        self.nb.add(self.items, text="Metric changes")
        diff_tab = frame(self.nb)
        self.nb.add(diff_tab, text="Structural JSON diff")
        bar2 = frame(diff_tab)
        bar2.pack(fill="x")
        label(bar2, "File present in both").pack(side="left")
        self.file = ttk.Combobox(bar2, width=80, state="readonly")
        self.file.pack(side="left", padx=t.space("sm"))
        self.file.bind("<<ComboboxSelected>>", lambda _e: self.diff_file())
        self.diff = DiffView(diff_tab)
        self.diff.pack(fill="both", expand=True)

    def _labels(self):
        return {f"{r.type} · {r.id}": r for r in self.app.state.refs}

    def refresh(self):
        refs = self._labels()
        values = list(refs)
        self.a.configure(values=values)
        self.b.configure(values=values)
        if self.pair:
            for combo, path in zip((self.a, self.b), self.pair):
                ref = self.app.state.find(path)
                if ref:
                    combo.set(f"{ref.type} · {ref.id}")
            self.pair = None
            self.run()

    def _pair(self):
        refs = self._labels()
        return refs.get(self.a.get()), refs.get(self.b.get())

    def run(self):
        a, b = self._pair()
        if not a or not b:
            return
        ok, reason = catalog.comparable(a, b)
        origin = f"A = {a.path}\nB = {b.path}\n"
        self.items.set_rows([])
        if not ok:
            self.banner.configure(text=origin + f"NOT COMPARABLE: {reason}", fg=t.color("status-unknown"))
        else:
            area = AREAS.get(a.type)
            if area and a.layout.startswith("run-manifest"):
                result = compare_runs.compare(area, Path(a.path), Path(b.path))
                self.banner.configure(
                    text=origin + f"{result['status'].upper()}: {result['reason']} · noise floor "
                                  f"{result['noise']} · {result['algorithm']}",
                    fg=t.status_color(result["status"]))
                self.items.set_rows(result["items"])
            else:
                self.banner.configure(text=origin + f"Comparable ({reason}). No metric comparison is "
                                                    "defined for this report type; use the structural diff.",
                                      fg=t.color("text-secondary"))
        self._list_files(a, b)

    def _files(self, ref):
        base = Path(ref.path)
        root = base if base.is_dir() else base.parent
        names = [base.name] if base.is_file() else sorted(
            p.relative_to(root).as_posix() for p in root.rglob("*.json") if p.is_file())
        return root, names

    def _list_files(self, a, b):
        ra, na = self._files(a)
        rb, nb = self._files(b)
        shared = [n for n in na if n in set(nb)] or ([na[0]] if na and nb and a.layout == "conformance-summary" else [])
        self._roots = (ra, rb, a, b)
        self.file.configure(values=shared)
        if shared:
            self.file.set(shared[0])
            self.diff_file()
        else:
            self.diff.set([], "no JSON file present in both reports")

    def diff_file(self):
        ra, rb, a, b = self._roots
        name = self.file.get()
        try:
            da = json.loads((ra / name if Path(a.path).is_dir() else Path(a.path)).read_text())
            db = json.loads((rb / name if Path(b.path).is_dir() else Path(b.path)).read_text())
        except (OSError, ValueError) as error:
            self.diff.set([], f"cannot read {name}: {error}")
            return
        self.diff.set(jsondiff.diff(da, db), f"{name}: A → B")

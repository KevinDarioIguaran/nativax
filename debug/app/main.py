#!/usr/bin/env python3
"""NativaX Debug Suite — desktop app (Tk).

    python3 debug/app/main.py [--report PATH] [--theme dark|light]

Layers: pages (debug/app/pages) → services (debug/logic) → engines, storage.
Every report is opened on its own; two reports meet only in Compare.
The app never writes inside a report; engine runs go through
debug/app/pages/run.py, which starts the real engine commands.
"""
from __future__ import annotations

import argparse
import sys
import tkinter as tk
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from debug.app.components.basic import button, entry, frame, label  # noqa: E402
from debug.app.state import AppState  # noqa: E402
from debug.styles import theme as t  # noqa: E402

NAV = [
    ("overview", "Overview"),
    ("explorer", "Report explorer"),
    ("report", "Report workspace"),
    ("compare", "Compare reports"),
    ("run", "Run engines"),
]


class App:
    def __init__(self, root: tk.Tk, *, report: str | None = None):
        self.tk = root
        self.state = AppState()
        self.pages: dict[str, object] = {}
        self.frames: dict[str, tk.Frame] = {}
        self.active = None
        root.title("NativaX Debug Suite")
        root.geometry("1600x980")
        root.minsize(1100, 700)
        t.apply(root)
        self._shell()
        root.bind("<Control-f>", lambda _e: self.search.focus_set())
        root.bind("<F5>", lambda _e: self.reload())
        self.reload()
        target = report or self.state.prefs.get("last_report")
        ref = self.state.find(target) if target else None
        if ref is not None:
            self.open_report(ref)
        else:
            self.show("overview")

    def _shell(self):
        top = frame(self.tk, "surface-raised", padx=t.space("lg"), pady=t.space("sm"))
        top.pack(fill="x")
        label(top, "NativaX Debug Suite", role="title", fg="text-primary", surface="surface-raised").pack(side="left")
        self.context = label(top, "no report open", role="code-small", surface="surface-raised")
        self.context.pack(side="left", padx=t.space("xl"))
        button(top, "Search", self.global_search).pack(side="right", padx=t.space("sm"))
        self.search = entry(top, 34)
        self.search.pack(side="right")
        self.search.bind("<Return>", lambda _e: self.global_search())
        label(top, "Search all reports (Ctrl+F)", surface="surface-raised").pack(side="right", padx=t.space("sm"))
        body = frame(self.tk)
        body.pack(fill="both", expand=True)
        nav = frame(body, "nav", width=t.size("nav-width"))
        nav.pack(side="left", fill="y")
        nav.pack_propagate(False)
        self.nav = {}
        for key, text in NAV:
            item = tk.Label(nav, text=text, bg=t.color("nav"), fg=t.color("text-secondary"), anchor="w",
                            padx=t.space("xl"), pady=t.space("sm"), font=t.font("label"), cursor="hand2",
                            takefocus=1)
            item.pack(fill="x")
            item.bind("<Button-1>", lambda _e, k=key: self.show(k))
            item.bind("<Return>", lambda _e, k=key: self.show(k))
            self.nav[key] = item
        self.nav_status = label(nav, "", role="caption", surface="nav", justify="left", wraplength=250)
        self.nav_status.pack(side="bottom", anchor="w", padx=t.space("lg"), pady=t.space("lg"))
        self.main = frame(body, padx=t.space("lg"), pady=t.space("sm"))
        self.main.pack(side="left", fill="both", expand=True)
        self.status = label(self.tk, "", surface="surface-raised", anchor="w", padx=t.space("lg"))
        self.status.pack(fill="x", side="bottom")

    def set_status(self, text, tone="text-secondary"):
        self.status.configure(text=text, fg=t.color(tone))
        self.tk.update_idletasks()

    def reload(self):
        self.set_status("scanning report folders …")
        self.state.reload()
        self.nav_status.configure(text=f"{len(self.state.refs)} reports found\nF5 rescans")
        if self.active:
            self.refresh(self.active)
        self.set_status(f"{len(self.state.refs)} reports")

    def page(self, key):
        if key not in self.pages:
            from debug.app import pages
            frm = frame(self.main)
            self.frames[key] = frm
            self.pages[key] = pages.create(key, frm, self)
        return self.pages[key]

    def show(self, key):
        page = self.page(key)
        for k, f in self.frames.items():
            f.pack_forget()
        self.frames[key].pack(fill="both", expand=True)
        for k, item in self.nav.items():
            active = k == key
            item.configure(fg=t.color("text-primary" if active else "text-secondary"),
                           bg=t.color("surface-hover" if active else "nav"))
        self.active = key
        page.refresh()

    def refresh(self, key):
        if key in self.pages:
            self.pages[key].refresh()

    def open_report(self, ref, *, focus=None):
        self.state.open(ref)
        self.context.configure(text=f"{ref.type} · {ref.id} · {ref.status or '—'} · {ref.path}",
                               fg=t.status_color(ref.health if ref.health != "unknown" else ref.status))
        self.page("report").focus = focus
        self.show("report")

    def global_search(self):
        query = self.search.get().strip()
        if not query:
            return
        self.page("explorer").set_query(query)
        self.show("explorer")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--report", help="report path to open at start")
    p.add_argument("--theme", choices=["dark", "light"], default="dark")
    args = p.parse_args(argv)
    t.use(args.theme)
    root = tk.Tk()
    App(root, report=args.report)
    root.mainloop()


if __name__ == "__main__":
    main()

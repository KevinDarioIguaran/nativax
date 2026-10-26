"""Basic widgets built only from design tokens (debug/styles)."""
from __future__ import annotations

import json
import tkinter as tk
from tkinter import ttk

from debug.styles import theme as t


def fmt(value, digits=1):
    """Display text for a value. None means not measured / not available."""
    if value is None:
        return "—"
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, float):
        return f"{value:,.{digits}f}"
    if isinstance(value, int):
        return f"{value:,}"
    if isinstance(value, (list, tuple)):
        return ", ".join(str(v) for v in value)
    if isinstance(value, dict):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def copy(widget, text: str) -> None:
    widget.clipboard_clear()
    widget.clipboard_append(text)


def frame(parent, surface="surface", **kw) -> tk.Frame:
    return tk.Frame(parent, bg=t.color(surface), **kw)


def label(parent, text="", *, role="body", fg="text-secondary", surface="surface", **kw) -> tk.Label:
    return tk.Label(parent, text=text, bg=t.color(surface), fg=t.color(fg), font=t.font(role), **kw)


def button(parent, text, command, *, primary=False, **kw) -> tk.Button:
    return tk.Button(parent, text=text, command=command,
                     bg=t.color("accent" if primary else "surface-control"),
                     fg=t.color("text-inverse" if primary else "text-primary"),
                     activebackground=t.color("surface-hover"), activeforeground=t.color("text-primary"),
                     relief="flat", bd=0, highlightthickness=t.size("border"),
                     highlightbackground=t.color("border-subtle"), padx=t.space("md"), pady=t.space("xs"),
                     font=t.font("label"), takefocus=1, cursor="hand2", **kw)


def entry(parent, width=24, textvariable=None) -> tk.Entry:
    return tk.Entry(parent, bg=t.color("surface-control"), fg=t.color("text-primary"),
                    insertbackground=t.color("text-primary"), relief="flat", width=width,
                    highlightthickness=t.size("border"), highlightbackground=t.color("border-subtle"),
                    highlightcolor=t.color("accent"), textvariable=textvariable, font=t.font("body"))


def combo(parent, values, width=14, on_change=None) -> ttk.Combobox:
    cb = ttk.Combobox(parent, values=list(values), width=width, state="readonly")
    if values:
        cb.current(0)
    if on_change:
        cb.bind("<<ComboboxSelected>>", lambda _e: on_change())
    return cb


def check(parent, text, variable, command=None) -> tk.Checkbutton:
    return tk.Checkbutton(parent, text=text, variable=variable, command=command, bg=t.color("surface"),
                          fg=t.color("text-primary"), selectcolor=t.color("surface-control"),
                          activebackground=t.color("surface"), font=t.font("body"))


def text_area(parent, *, height=10, mono=True, surface="surface-raised", wrap="none") -> tk.Text:
    return tk.Text(parent, bg=t.color(surface), fg=t.color("text-primary"),
                   insertbackground=t.color("text-primary"), relief="flat", height=height, wrap=wrap,
                   font=t.font("code" if mono else "body"), padx=t.space("md"), pady=t.space("sm"))


def scrolled(parent, widget_factory, *, horizontal=False):
    """Packs `widget_factory(holder)` with scrollbars; returns the widget."""
    holder = frame(parent, "surface-raised")
    w = widget_factory(holder)
    ys = ttk.Scrollbar(holder, orient="vertical", command=w.yview)
    w.configure(yscrollcommand=ys.set)
    if horizontal:
        xs = ttk.Scrollbar(holder, orient="horizontal", command=w.xview)
        w.configure(xscrollcommand=xs.set)
        xs.pack(side="bottom", fill="x")
    w.pack(side="left", fill="both", expand=True)
    ys.pack(side="left", fill="y")
    holder.widget = w
    return holder


def badge(parent, value, *, surface="surface") -> tk.Label:
    """Status label colored by the status vocabulary in debug/styles/tokens.py."""
    return tk.Label(parent, text=fmt(value), bg=t.color(surface), fg=t.status_color(value), font=t.font("label"))


class KeyValue(tk.Frame):
    """Fact list. A missing value reads 'not available', never a default."""

    def __init__(self, master, surface="surface-raised", wrap=900):
        super().__init__(master, bg=t.color(surface))
        self.surface, self.wrap = surface, wrap

    def set(self, pairs, *, on_click=None):
        for child in self.winfo_children():
            child.destroy()
        for row, (key, value) in enumerate(pairs):
            tk.Label(self, text=key, bg=t.color(self.surface), fg=t.color("text-secondary"), font=t.font("body"),
                     anchor="w").grid(row=row, column=0, sticky="nw", padx=(t.space("md"), t.space("lg")),
                                      pady=t.space("xxs"))
            missing = value is None
            lab = tk.Label(self, text="not available" if missing else fmt(value), bg=t.color(self.surface),
                           fg=t.color("status-unknown" if missing else "text-primary"), font=t.font("code"),
                           anchor="w", justify="left", wraplength=self.wrap)
            lab.grid(row=row, column=1, sticky="nw", pady=t.space("xxs"))
            if on_click and not missing:
                lab.configure(cursor="hand2")
                lab.bind("<Button-1>", lambda _e, k=key: on_click(k))
        self.columnconfigure(1, weight=1)


def scroll_frame(parent, surface="surface-raised"):
    """A vertically scrollable frame; returns the inner frame."""
    canvas = tk.Canvas(parent, bg=t.color(surface), highlightthickness=0)
    sb = ttk.Scrollbar(parent, orient="vertical", command=canvas.yview)
    inner = frame(canvas, surface)
    inner.bind("<Configure>", lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
    win = canvas.create_window((0, 0), window=inner, anchor="nw")
    canvas.bind("<Configure>", lambda e: canvas.itemconfigure(win, width=e.width))
    canvas.configure(yscrollcommand=sb.set)
    canvas.pack(side="left", fill="both", expand=True)
    sb.pack(side="left", fill="y")
    return inner


def section(parent, title, *, surface="surface-raised"):
    label(parent, title, role="heading", fg="accent", surface=surface).pack(anchor="w", padx=t.space("md"),
                                                                           pady=(t.space("md"), t.space("xxs")))


def bullet_list(parent, lines, *, surface="surface-raised", fg="text-primary", empty="none recorded"):
    if not lines:
        label(parent, f"— {empty} —", fg="status-unknown", surface=surface).pack(anchor="w", padx=t.space("xl"))
    for line in lines:
        label(parent, f"• {line}", fg=fg, surface=surface, wraplength=1100, justify="left").pack(
            anchor="w", padx=t.space("xl"))

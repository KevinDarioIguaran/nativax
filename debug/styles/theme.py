"""Applies a token theme to Tk/ttk and exposes token lookups to components."""
from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from debug.styles.tokens import SIZE, SPACE, THEMES, TYPE, status_token

_current = THEMES["dark"]


def use(name: str) -> None:
    global _current
    _current = THEMES[name]


def color(token: str) -> str:
    return _current.color[token]


def status_color(value) -> str:
    return color(status_token(value))


def font(role: str):
    return TYPE[role]


def space(name: str) -> int:
    return SPACE[name]


def size(name: str) -> int:
    return SIZE[name]


def apply(root: tk.Misc) -> ttk.Style:
    s = ttk.Style(root)
    try:
        s.theme_use("clam")
    except tk.TclError:
        pass
    root.configure(bg=color("surface"))
    s.configure("Treeview", background=color("surface-raised"), fieldbackground=color("surface-raised"),
                foreground=color("text-primary"), rowheight=size("row"), borderwidth=0, font=font("body"))
    s.configure("Treeview.Heading", background=color("surface-control"), foreground=color("text-secondary"),
                relief="flat", font=font("label"))
    s.map("Treeview", background=[("selected", color("surface-selected"))],
          foreground=[("selected", color("text-primary"))])
    s.map("Treeview.Heading", background=[("active", color("surface-hover"))])
    s.configure("TNotebook", background=color("surface"), borderwidth=0)
    s.configure("TNotebook.Tab", background=color("surface-control"), foreground=color("text-secondary"),
                padding=(space("lg"), space("sm")), font=font("label"))
    s.map("TNotebook.Tab", background=[("selected", color("surface-raised"))],
          foreground=[("selected", color("text-primary"))])
    s.configure("TCombobox", fieldbackground=color("surface-control"), background=color("surface-control"),
                foreground=color("text-primary"))
    s.configure("Vertical.TScrollbar", background=color("surface-control"), troughcolor=color("surface"))
    s.configure("Horizontal.TScrollbar", background=color("surface-control"), troughcolor=color("surface"))
    s.configure("TProgressbar", background=color("accent"), troughcolor=color("surface-control"))
    return s

"""Tk widgets for the audit GUI: paginated sortable table, JSON viewer with
path spans, charts that keep "not measured" distinct from zero, diff view."""
from __future__ import annotations

import json
import tkinter as tk
from tkinter import ttk

BG = "#0b0f14"
PANEL = "#11161d"
PANEL2 = "#18202a"
BORDER = "#212b36"
FG = "#e6edf3"
MUTED = "#9fb3c8"
ACCENT = "#7aa2ff"
GREEN = "#3fb950"
YELLOW = "#d29922"
RED = "#f85149"
PURPLE = "#a371f7"
CYAN = "#39c5cf"
UNKNOWN = "#6e7681"
FONT = "Noto Sans"
MONO = "DejaVu Sans Mono"

STATUS_COLORS = {
    "critical": RED, "high": RED, "medium": YELLOW, "low": MUTED, "info": PURPLE,
    "failed": RED, "passed": GREEN, "inconclusive": UNKNOWN, "ok": GREEN, "error": RED,
    "warn": YELLOW, "unknown": UNKNOWN, "complete": GREEN, "incomplete": YELLOW, "corrupt": RED,
    "new": CYAN, "known": MUTED, "regression": RED, "oracle_conflict": PURPLE,
    "added": GREEN, "removed": RED, "changed": YELLOW, "moved": CYAN, "type_changed": PURPLE,
}


def fmt(value, digits=1):
    """Display a value; None is 'no medido', never 0."""
    if value is None:
        return "—"
    if isinstance(value, bool):
        return "sí" if value else "no"
    if isinstance(value, float):
        return f"{value:,.{digits}f}"
    if isinstance(value, int):
        return f"{value:,}"
    if isinstance(value, (list, tuple)):
        return ", ".join(str(v) for v in value)
    return str(value)


def style(root):
    s = ttk.Style(root)
    try:
        s.theme_use("clam")
    except tk.TclError:
        pass
    s.configure("Treeview", background=PANEL, fieldbackground=PANEL, foreground=FG, rowheight=21,
                borderwidth=0, font=(FONT, 9))
    s.configure("Treeview.Heading", background=PANEL2, foreground=MUTED, relief="flat", font=(FONT, 9, "bold"))
    s.map("Treeview", background=[("selected", "#1f3a5f")], foreground=[("selected", FG)])
    s.map("Treeview.Heading", background=[("active", BORDER)])
    s.configure("TNotebook", background=BG, borderwidth=0)
    s.configure("TNotebook.Tab", background=PANEL2, foreground=MUTED, padding=(10, 4), font=(FONT, 9, "bold"))
    s.map("TNotebook.Tab", background=[("selected", PANEL)], foreground=[("selected", FG)])
    s.configure("TCombobox", fieldbackground=PANEL2, background=PANEL2, foreground=FG)
    s.configure("TCheckbutton", background=BG, foreground=FG)
    s.configure("Vertical.TScrollbar", background=PANEL2, troughcolor=BG)


def button(parent, text, command, accent=False, **kw):
    return tk.Button(parent, text=text, command=command, bg=ACCENT if accent else PANEL2,
                     fg="#07101f" if accent else FG, activebackground="#2a3644", relief="flat", bd=0,
                     highlightthickness=1, highlightbackground=BORDER, padx=9, pady=3,
                     font=(FONT, 9, "bold"), takefocus=1, **kw)


def label(parent, text="", fg=MUTED, size=9, bold=False, mono=False, bg=BG, **kw):
    return tk.Label(parent, text=text, bg=bg, fg=fg, font=(MONO if mono else FONT, size, "bold" if bold else ""),
                    **kw)


def entry(parent, width=24, textvariable=None):
    return tk.Entry(parent, bg=PANEL2, fg=FG, insertbackground=FG, relief="flat", width=width,
                    highlightthickness=1, highlightbackground=BORDER, highlightcolor=ACCENT,
                    textvariable=textvariable, font=(FONT, 9))


class Table(tk.Frame):
    """Sortable, filterable, paginated table over an in-memory row list.

    Filtering and search run over *all* rows; only the visible page is
    inserted into the Treeview, so large tables stay responsive.
    """

    def __init__(self, master, columns, *, page_size=200, on_select=None, on_open=None,
                 tag_key=None, multi=False, height=12):
        super().__init__(master, bg=BG)
        self.columns = columns  # [(key, label, width, anchor)]
        self.page_size = page_size
        self.on_select, self.on_open, self.tag_key = on_select, on_open, tag_key
        self.all_rows: list[dict] = []
        self.view_rows: list[dict] = []
        self.page = 0
        self.sort_key, self.sort_desc = None, False
        self.query = ""
        self.predicate = None
        top = tk.Frame(self, bg=BG)
        top.pack(fill="x")
        label(top, "Buscar").pack(side="left")
        self.search_var = tk.StringVar()
        self.search = entry(top, 28, self.search_var)
        self.search.pack(side="left", padx=4)
        self.search_var.trace_add("write", lambda *_: self._set_query(self.search_var.get()))
        self.pager = label(top, "")
        self.pager.pack(side="right")
        button(top, "▶", self.next_page).pack(side="right", padx=2)
        button(top, "◀", self.prev_page).pack(side="right", padx=2)
        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True)
        self.tree = ttk.Treeview(body, columns=[c[0] for c in columns], show="headings",
                                 selectmode="extended" if multi else "browse", height=height)
        for key, text, width, anchor in columns:
            self.tree.heading(key, text=text, command=lambda k=key: self.sort_by(k))
            self.tree.column(key, width=width, anchor=anchor, stretch=key == columns[0][0] or width > 200)
        ys = ttk.Scrollbar(body, orient="vertical", command=self.tree.yview)
        xs = ttk.Scrollbar(self, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=ys.set, xscrollcommand=xs.set)
        self.tree.pack(side="left", fill="both", expand=True)
        ys.pack(side="left", fill="y")
        xs.pack(fill="x")
        for name, color in STATUS_COLORS.items():
            self.tree.tag_configure(name, foreground=color)
        self.tree.tag_configure("odd", background="#0f151d")
        self.tree.bind("<<TreeviewSelect>>", self._selected)
        self.tree.bind("<Double-1>", self._opened)
        self.tree.bind("<Return>", self._opened)
        self.tree.bind("<Button-3>", self._menu)

    # data -----------------------------------------------------------------
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
            rows = [r for r in rows if self.query in " ".join(fmt(r.get(k)) for k in keys).lower()
                    or self.query in str(r.get("_search", "")).lower()]
        if self.sort_key:
            k = self.sort_key
            rows = sorted(rows, key=lambda r: (r.get(k) is None, _sortable(r.get(k))), reverse=self.sort_desc)
            if self.sort_desc:  # keep missing values last in both directions
                rows = [r for r in rows if r.get(k) is not None] + [r for r in rows if r.get(k) is None]
        self.view_rows = rows
        pages = max(1, (len(rows) + self.page_size - 1) // self.page_size)
        self.page = min(self.page, pages - 1)
        start = self.page * self.page_size
        visible = rows[start:start + self.page_size]
        self.tree.delete(*self.tree.get_children())
        for i, r in enumerate(visible):
            tags = []
            if self.tag_key and r.get(self.tag_key) in STATUS_COLORS:
                tags.append(r.get(self.tag_key))
            if i % 2:
                tags.append("odd")
            self.tree.insert("", "end", iid=str(start + i), tags=tags,
                             values=[fmt(r.get(c[0])) for c in self.columns])
        for key, text, *_ in self.columns:
            arrow = (" ▼" if self.sort_desc else " ▲") if key == self.sort_key else ""
            self.tree.heading(key, text=text + arrow)
        shown = f"{start + 1 if visible else 0}–{start + len(visible)}"
        self.pager.configure(text=f"filas {shown} de {len(rows):,} (total {len(self.all_rows):,}) · "
                                  f"pág. {self.page + 1}/{pages}")

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

    def select_where(self, key, value):
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
        menu = tk.Menu(self, tearoff=0, bg=PANEL2, fg=FG, activebackground=BORDER)
        menu.add_command(label=f"Copiar «{key}»", command=lambda: copy(self, fmt(row.get(key))))
        menu.add_command(label="Copiar fila (JSON)", command=lambda: copy(
            self, json.dumps({k: v for k, v in row.items() if not k.startswith("_")}, ensure_ascii=False,
                             indent=2, default=str)))
        if self.on_open:
            menu.add_command(label="Abrir", command=lambda: self.on_open(row))
        menu.tk_popup(event.x_root, event.y_root)


def _sortable(v):
    if isinstance(v, (int, float)):
        return (0, v, "")
    return (1, 0, fmt(v).lower())


def copy(widget, text):
    widget.clipboard_clear()
    widget.clipboard_append(text)


class JsonView(tk.Frame):
    """Read-only JSON with syntax colours and per-path character spans."""

    def __init__(self, master, height=20):
        super().__init__(master, bg=PANEL)
        bar = tk.Frame(self, bg=PANEL)
        bar.pack(fill="x")
        self.title = label(bar, "", bg=PANEL)
        self.title.pack(side="left", padx=6)
        button(bar, "Copiar JSON", lambda: copy(self, self._raw)).pack(side="right", padx=2, pady=2)
        self.path_label = label(bar, "", fg=ACCENT, mono=True, bg=PANEL)
        self.path_label.pack(side="right", padx=6)
        self.text = tk.Text(self, bg=PANEL, fg=FG, insertbackground=FG, relief="flat", wrap="none",
                            font=(MONO, 9), height=height, padx=6, pady=4)
        ys = ttk.Scrollbar(self, orient="vertical", command=self.text.yview)
        xs = ttk.Scrollbar(self, orient="horizontal", command=self.text.xview)
        self.text.configure(yscrollcommand=ys.set, xscrollcommand=xs.set)
        xs.pack(side="bottom", fill="x")
        self.text.pack(side="left", fill="both", expand=True)
        ys.pack(side="left", fill="y")
        for tag, color in (("key", ACCENT), ("str", "#a5d6ff"), ("num", "#ffa657"), ("lit", PURPLE),
                           ("null", UNKNOWN)):
            self.text.tag_configure(tag, foreground=color)
        self.text.tag_configure("hl", background="#2d3f1f")
        self.spans: dict[str, tuple[int, int]] = {}
        self._raw = ""
        self.text.configure(state="disabled")

    def show(self, obj, title="", max_chars=1_500_000):
        self.spans = {}
        parts: list[tuple[str, str | None]] = []
        pos = [0]

        def put(s, tag=None):
            parts.append((s, tag))
            pos[0] += len(s)

        def walk(v, path, indent):
            start = pos[0]
            pad = "  " * indent
            if isinstance(v, dict):
                if not v:
                    put("{}")
                else:
                    put("{\n")
                    for i, (k, x) in enumerate(v.items()):
                        put(pad + "  ")
                        put(json.dumps(k, ensure_ascii=False), "key")
                        put(": ")
                        walk(x, f"{path}.{k}", indent + 1)
                        put(",\n" if i < len(v) - 1 else "\n")
                    put(pad + "}")
            elif isinstance(v, list):
                if not v:
                    put("[]")
                else:
                    put("[\n")
                    for i, x in enumerate(v):
                        put(pad + "  ")
                        walk(x, f"{path}[{i}]", indent + 1)
                        put(",\n" if i < len(v) - 1 else "\n")
                    put(pad + "]")
            elif isinstance(v, str):
                put(json.dumps(v, ensure_ascii=False), "str")
            elif v is None:
                put("null", "null")
            elif isinstance(v, bool):
                put("true" if v else "false", "lit")
            else:
                put(json.dumps(v), "num")
            self.spans[path] = (start, pos[0])
            if pos[0] > max_chars:
                raise OverflowError

        truncated = False
        try:
            walk(obj, "$", 0)
        except OverflowError:
            truncated = True
        self._raw = json.dumps(obj, ensure_ascii=False, indent=2, default=str)
        self.text.configure(state="normal")
        self.text.delete("1.0", "end")
        for s, tag in parts:
            self.text.insert("end", s, tag or ())
        if truncated:
            self.text.insert("end", "\n… truncado en pantalla; «Copiar JSON» contiene el documento completo.")
        self.text.configure(state="disabled")
        self.title.configure(text=title)
        self.path_label.configure(text="")

    def highlight(self, path):
        self.text.tag_remove("hl", "1.0", "end")
        span = self.spans.get(path)
        self.path_label.configure(text=path if span else f"{path} (no presente)")
        if not span:
            return False
        a, b = f"1.0 + {span[0]} chars", f"1.0 + {span[1]} chars"
        self.text.tag_add("hl", a, b)
        self.text.see(a)
        return True


class BarChart(tk.Canvas):
    """Horizontal bars with exact values; None is drawn as 'no medido'.
    Clicking a bar calls `on_click(key)`."""

    def __init__(self, master, height=200, on_click=None, unit=""):
        super().__init__(master, bg=PANEL, height=height, highlightthickness=0)
        self.on_click, self.unit = on_click, unit
        self.items: list[tuple[str, float | None, str]] = []
        self.title = ""
        self.bind("<Configure>", lambda _e: self.draw())

    def set(self, title, items):
        """items: [(label, value_or_None, color_key)]"""
        self.title, self.items = title, list(items)
        self.draw()

    def draw(self):
        self.delete("all")
        w = max(self.winfo_width(), 300)
        self.create_text(8, 10, text=self.title, anchor="w", fill=FG, font=(FONT, 9, "bold"))
        if not self.items:
            self.create_text(w / 2, 60, text="sin datos en este informe", fill=UNKNOWN, font=(FONT, 9))
            return
        vals = [v for _, v, _ in self.items if isinstance(v, (int, float))]
        top = max(vals) if vals else 0
        row_h = max(14, min(22, (int(self["height"]) - 26) // max(1, len(self.items))))
        for i, (name, v, color) in enumerate(self.items):
            y = 26 + i * row_h
            self.create_text(8, y + row_h / 2, text=str(name)[:28], anchor="w", fill=MUTED, font=(FONT, 8))
            x0, x1 = 190, w - 70
            if v is None:
                self.create_text(x0, y + row_h / 2, text="no medido", anchor="w", fill=UNKNOWN,
                                 font=(FONT, 8, "italic"))
                continue
            length = (x1 - x0) * (v / top) if top else 0
            tag = f"bar{i}"
            self.create_rectangle(x0, y + 2, x0 + max(length, 1), y + row_h - 2,
                                  fill=STATUS_COLORS.get(color, color if color.startswith("#") else ACCENT),
                                  outline="", tags=(tag,))
            self.create_text(x0 + max(length, 1) + 6, y + row_h / 2, text=f"{fmt(v)}{self.unit}", anchor="w",
                             fill=FG, font=(MONO, 8), tags=(tag,))
            if self.on_click:
                self.tag_bind(tag, "<Button-1>", lambda _e, n=name: self.on_click(n))
                self.tag_bind(tag, "<Enter>", lambda _e: self.configure(cursor="hand2"))
                self.tag_bind(tag, "<Leave>", lambda _e: self.configure(cursor=""))


class LineChart(tk.Canvas):
    def __init__(self, master, height=180):
        super().__init__(master, bg=PANEL, height=height, highlightthickness=0)
        self.series, self.title, self.xlabel, self.ylabel = [], "", "", ""
        self.bind("<Configure>", lambda _e: self.draw())

    def set(self, title, series, xlabel="", ylabel=""):
        """series: [(name, [(x, y)], color)]"""
        self.title, self.series, self.xlabel, self.ylabel = title, series, xlabel, ylabel
        self.draw()

    def draw(self):
        self.delete("all")
        w, h = max(self.winfo_width(), 300), int(self["height"])
        self.create_text(8, 10, text=self.title, anchor="w", fill=FG, font=(FONT, 9, "bold"))
        pts = [p for _, s, _ in self.series for p in s if p[1] is not None]
        if not pts:
            self.create_text(w / 2, h / 2, text="sin datos en este informe", fill=UNKNOWN, font=(FONT, 9))
            return
        x0, y0, x1, y1 = 52, h - 26, w - 12, 24
        xmax = max(p[0] for p in pts) or 1
        ymax = max(p[1] for p in pts) or 1
        self.create_line(x0, y0, x1, y0, fill=BORDER)
        self.create_line(x0, y0, x0, y1, fill=BORDER)
        for frac in (0, 0.5, 1):
            y = y0 - (y0 - y1) * frac
            self.create_text(x0 - 4, y, text=fmt(ymax * frac, 0), anchor="e", fill=MUTED, font=(MONO, 7))
        self.create_text(x1, y0 + 12, text=f"{self.xlabel} (máx {fmt(xmax)})", anchor="e", fill=MUTED,
                         font=(FONT, 7))
        self.create_text(x0, y1 - 8, text=self.ylabel, anchor="w", fill=MUTED, font=(FONT, 7))
        for i, (name, s, color) in enumerate(self.series):
            coords = []
            for x, y in s:
                if y is None:
                    continue
                coords += [x0 + (x1 - x0) * x / xmax, y0 - (y0 - y1) * y / ymax]
            if len(coords) >= 4:
                self.create_line(*coords, fill=color, width=2)
            self.create_text(x1 - 4, y1 + 10 + i * 12, text=name, anchor="e", fill=color, font=(FONT, 8))


class Histogram(BarChart):
    def set_values(self, title, values, bins=12, unit=" ms"):
        vals = [v for v in values if isinstance(v, (int, float))]
        missing = len(values) - len(vals)
        if not vals:
            self.set(title, [])
            return
        lo, hi = min(vals), max(vals)
        step = (hi - lo) / bins or 1
        counts = [0] * bins
        for v in vals:
            counts[min(int((v - lo) / step), bins - 1)] += 1
        items = [(f"{lo + i * step:,.0f}–{lo + (i + 1) * step:,.0f}{unit}", c, "#7aa2ff")
                 for i, c in enumerate(counts)]
        if missing:
            items.append(("sin medir", None, UNKNOWN))
        self.unit = ""
        self.set(title + f" · n={len(vals)}", items)


class KeyValue(tk.Frame):
    """Two-column facts panel; missing values are labelled, not defaulted."""

    def __init__(self, master, bg=PANEL):
        super().__init__(master, bg=bg)
        self.bg = bg

    def set(self, pairs, on_click=None):
        for c in self.winfo_children():
            c.destroy()
        for r, (k, v) in enumerate(pairs):
            tk.Label(self, text=k, bg=self.bg, fg=MUTED, font=(FONT, 9), anchor="w").grid(
                row=r, column=0, sticky="nw", padx=(8, 12), pady=1)
            text = "no disponible" if v is None else fmt(v)
            lab = tk.Label(self, text=text, bg=self.bg, fg=UNKNOWN if v is None else FG, font=(MONO, 9),
                           anchor="w", justify="left", wraplength=640)
            lab.grid(row=r, column=1, sticky="nw", pady=1)
            if on_click and v is not None:
                lab.configure(cursor="hand2")
                lab.bind("<Button-1>", lambda _e, key=k: on_click(key))
        self.columnconfigure(1, weight=1)


class DiffView(tk.Frame):
    """Structural diff list with per-kind filters; double-click jumps."""

    def __init__(self, master, on_jump=None):
        super().__init__(master, bg=BG)
        self.on_jump = on_jump
        bar = tk.Frame(self, bg=BG)
        bar.pack(fill="x")
        self.summary = label(bar, "")
        self.summary.pack(side="left")
        self.vars = {}
        for kind in ("added", "removed", "changed", "moved", "type_changed"):
            v = tk.BooleanVar(value=True)
            self.vars[kind] = v
            tk.Checkbutton(bar, text=kind, variable=v, command=self.refresh, bg=BG, fg=STATUS_COLORS[kind],
                           selectcolor=PANEL2, activebackground=BG, font=(FONT, 9)).pack(side="right")
        self.table = Table(self, [("op", "Cambio", 90, "w"), ("path", "Ruta", 380, "w"),
                                  ("before", "Antes", 260, "w"), ("after", "Después", 260, "w")],
                           tag_key="op", on_open=lambda r: self.on_jump and self.on_jump(r["path"]))
        self.table.pack(fill="both", expand=True)
        self.changes = []

    def set(self, changes, title=""):
        self.changes = [{**c, "before": _short(c.get("before")), "after": _short(c.get("after"))}
                        for c in changes]
        counts = {}
        for c in changes:
            counts[c["op"]] = counts.get(c["op"], 0) + 1
        self.summary.configure(text=f"{title} · " + (" · ".join(f"{k} {v}" for k, v in counts.items())
                                                       or "sin diferencias estructurales"))
        self.refresh()

    def refresh(self):
        self.table.set_rows([c for c in self.changes if self.vars[c["op"]].get()])


def _short(v):
    if v is None:
        return None
    text = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
    return text if len(text) < 160 else text[:157] + "…"

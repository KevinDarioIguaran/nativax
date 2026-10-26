"""Charts with exact values. None is drawn as 'not measured', never as zero."""
from __future__ import annotations

import tkinter as tk

from debug.app.components.basic import fmt
from debug.styles import theme as t


class BarChart(tk.Canvas):
    """Horizontal bars; clicking a bar calls `on_click(label)`."""

    def __init__(self, master, height=200, on_click=None, unit=""):
        super().__init__(master, bg=t.color("surface-raised"), height=height, highlightthickness=0)
        self.on_click, self.unit = on_click, unit
        self.items: list[tuple[str, float | None, str]] = []
        self.title = ""
        self.bind("<Configure>", lambda _e: self.draw())

    def set(self, title, items):
        """items: [(label, value or None, status or color token)]."""
        self.title, self.items = title, list(items)
        self.draw()

    def _color(self, key):
        try:
            return t.color(key)
        except KeyError:
            return t.status_color(key)

    def draw(self):
        self.delete("all")
        w = max(self.winfo_width(), 300)
        self.create_text(8, 10, text=self.title, anchor="w", fill=t.color("text-primary"), font=t.font("label"))
        if not self.items:
            self.create_text(w / 2, 60, text="no data in this report", fill=t.color("status-unknown"),
                             font=t.font("body"))
            return
        values = [v for _, v, _ in self.items if isinstance(v, (int, float))]
        top = max(values) if values else 0
        row_h = max(14, min(22, (int(self["height"]) - 26) // max(1, len(self.items))))
        for i, (name, v, color) in enumerate(self.items):
            y = 26 + i * row_h
            self.create_text(8, y + row_h / 2, text=str(name)[:30], anchor="w", fill=t.color("text-secondary"),
                             font=t.font("caption"))
            x0, x1 = 200, w - 80
            if v is None:
                self.create_text(x0, y + row_h / 2, text="not measured", anchor="w",
                                 fill=t.color("status-unknown"), font=t.font("caption"))
                continue
            length = (x1 - x0) * (v / top) if top else 0
            tag = f"bar{i}"
            self.create_rectangle(x0, y + 2, x0 + max(length, 1), y + row_h - 2, fill=self._color(color),
                                  outline="", tags=(tag,))
            self.create_text(x0 + max(length, 1) + 6, y + row_h / 2, text=f"{fmt(v)}{self.unit}", anchor="w",
                             fill=t.color("text-primary"), font=t.font("code-small"), tags=(tag,))
            if self.on_click:
                self.tag_bind(tag, "<Button-1>", lambda _e, n=name: self.on_click(n))


class LineChart(tk.Canvas):
    def __init__(self, master, height=180):
        super().__init__(master, bg=t.color("surface-raised"), height=height, highlightthickness=0)
        self.series, self.title, self.xlabel, self.ylabel = [], "", "", ""
        self.bind("<Configure>", lambda _e: self.draw())

    def set(self, title, series, xlabel="", ylabel=""):
        """series: [(name, [(x, y or None)], color token)]."""
        self.title, self.series, self.xlabel, self.ylabel = title, series, xlabel, ylabel
        self.draw()

    def draw(self):
        self.delete("all")
        w, h = max(self.winfo_width(), 300), int(self["height"])
        self.create_text(8, 10, text=self.title, anchor="w", fill=t.color("text-primary"), font=t.font("label"))
        points = [p for _, s, _ in self.series for p in s if p[1] is not None]
        if not points:
            self.create_text(w / 2, h / 2, text="no data in this report", fill=t.color("status-unknown"),
                             font=t.font("body"))
            return
        x0, y0, x1, y1 = 56, h - 26, w - 12, 24
        xmin = min(p[0] for p in points)
        xmax = max(p[0] for p in points)
        ymax = max(p[1] for p in points) or 1
        span = (xmax - xmin) or 1
        self.create_line(x0, y0, x1, y0, fill=t.color("border-strong"))
        self.create_line(x0, y0, x0, y1, fill=t.color("border-strong"))
        for frac in (0, 0.5, 1):
            y = y0 - (y0 - y1) * frac
            self.create_text(x0 - 4, y, text=fmt(ymax * frac, 1), anchor="e", fill=t.color("text-secondary"),
                             font=t.font("code-small"))
        self.create_text(x1, y0 + 12, text=self.xlabel, anchor="e", fill=t.color("text-secondary"),
                         font=t.font("caption"))
        self.create_text(x0, y1 - 8, text=self.ylabel, anchor="w", fill=t.color("text-secondary"),
                         font=t.font("caption"))
        for i, (name, s, color) in enumerate(self.series):
            coords = []
            for x, y in s:
                if y is None:
                    continue
                coords += [x0 + (x1 - x0) * (x - xmin) / span, y0 - (y0 - y1) * y / ymax]
            if len(coords) >= 4:
                self.create_line(*coords, fill=t.color(color), width=2)
            elif len(coords) == 2:
                self.create_oval(coords[0] - 3, coords[1] - 3, coords[0] + 3, coords[1] + 3,
                                 fill=t.color(color), outline="")
            self.create_text(x1 - 4, y1 + 10 + i * 12, text=name, anchor="e", fill=t.color(color),
                             font=t.font("caption"))


class Histogram(BarChart):
    def set_values(self, title, values, bins=12, unit=" ms"):
        measured = [v for v in values if isinstance(v, (int, float))]
        missing = len(values) - len(measured)
        if not measured:
            self.set(title, [])
            return
        lo, hi = min(measured), max(measured)
        step = (hi - lo) / bins or 1
        counts = [0] * bins
        for v in measured:
            counts[min(int((v - lo) / step), bins - 1)] += 1
        items = [(f"{lo + i * step:,.0f}–{lo + (i + 1) * step:,.0f}{unit}", c, "series-1")
                 for i, c in enumerate(counts)]
        if missing:
            items.append(("not measured", None, "status-unknown"))
        self.unit = ""
        self.set(f"{title} · n={len(measured)}", items)

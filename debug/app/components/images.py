"""Image evidence viewer: original PNG files shown side by side with
synchronized zoom/scroll, region boxes and a per-pixel readout. The files
are read from the report as they are; nothing is resampled on disk."""
from __future__ import annotations

import tkinter as tk
from pathlib import Path
from tkinter import ttk

from debug.app.components.basic import button, combo, frame, label
from debug.styles import theme as t

ZOOMS = ["25%", "50%", "100%", "200%", "400%", "800%"]


def _scaled(img: tk.PhotoImage, zoom: str) -> tk.PhotoImage:
    pct = int(zoom.rstrip("%"))
    if pct >= 100:
        return img.zoom(pct // 100) if pct > 100 else img
    return img.subsample(100 // pct)


class ImagePanes(tk.Frame):
    """Up to four images (e.g. reference / actual / difference / overlay)."""

    def __init__(self, master):
        super().__init__(master, bg=t.color("surface"))
        bar = frame(self)
        bar.pack(fill="x")
        label(bar, "Zoom").pack(side="left")
        self.zoom = combo(bar, ZOOMS, width=6, on_change=self.redraw)
        self.zoom.set("100%")
        self.zoom.pack(side="left", padx=t.space("sm"))
        self.readout = label(bar, "", role="code-small")
        self.readout.pack(side="left", padx=t.space("lg"))
        self.grid_frame = frame(self)
        self.grid_frame.pack(fill="both", expand=True)
        self.panes: list[dict] = []
        self.regions: list[dict] = []
        self.selected_region = None
        xs = ttk.Scrollbar(self, orient="horizontal", command=self._xview)
        xs.pack(fill="x")
        self.xs = xs

    def show(self, images: list[tuple[str, Path | None]], regions=None):
        for w in self.grid_frame.winfo_children():
            w.destroy()
        self.panes = []
        self.regions = list(regions or [])
        for col, (title, path) in enumerate(images):
            holder = frame(self.grid_frame, "surface-raised")
            holder.grid(row=0, column=col, sticky="nsew", padx=t.space("xs"))
            self.grid_frame.columnconfigure(col, weight=1)
            self.grid_frame.rowconfigure(0, weight=1)
            exists = path is not None and Path(path).is_file()
            label(holder, f"{title}" + (f" — {Path(path).name}" if exists else " — not available"),
                  role="label", fg="text-primary" if exists else "status-unknown",
                  surface="surface-raised").pack(anchor="w")
            canvas = tk.Canvas(holder, bg=t.color("surface-sunken"), highlightthickness=0)
            ys = ttk.Scrollbar(holder, orient="vertical", command=self._yview)
            canvas.configure(yscrollcommand=ys.set, xscrollcommand=self.xs.set)
            canvas.pack(side="left", fill="both", expand=True)
            ys.pack(side="left", fill="y")
            pane = {"title": title, "path": path, "canvas": canvas, "image": None, "scaled": None,
                    "error": None if exists else "file not in this report"}
            if exists:
                try:
                    pane["image"] = tk.PhotoImage(file=str(path))
                except tk.TclError as error:
                    pane["error"] = f"cannot decode: {error}"
            canvas.bind("<Motion>", lambda e, p=pane: self._hover(p, e))
            canvas.bind("<MouseWheel>", lambda e: self._yview("scroll", -1 if e.delta > 0 else 1, "units"))
            canvas.bind("<Button-4>", lambda _e: self._yview("scroll", -3, "units"))
            canvas.bind("<Button-5>", lambda _e: self._yview("scroll", 3, "units"))
            self.panes.append(pane)
        self.redraw()

    def factor(self) -> float:
        return int(self.zoom.get().rstrip("%")) / 100

    def redraw(self):
        k = self.factor()
        for pane in self.panes:
            c = pane["canvas"]
            c.delete("all")
            if pane["image"] is None:
                c.create_text(10, 10, anchor="nw", text=pane["error"] or "not available",
                              fill=t.color("status-unknown"), font=t.font("body"))
                continue
            pane["scaled"] = _scaled(pane["image"], self.zoom.get())
            c.create_image(0, 0, anchor="nw", image=pane["scaled"])
            for i, region in enumerate(self.regions):
                x, y, w, h = region["bbox"]
                selected = i == self.selected_region
                c.create_rectangle(x * k, y * k, (x + w) * k, (y + h) * k,
                                   outline=t.color("status-error" if selected else "status-warning"),
                                   width=3 if selected else 1)
            c.configure(scrollregion=(0, 0, pane["image"].width() * k, pane["image"].height() * k))

    def focus_region(self, index: int):
        self.selected_region = index
        self.redraw()
        if not self.regions or index is None:
            return
        x, y, w, h = self.regions[index]["bbox"]
        k = self.factor()
        for pane in self.panes:
            if pane["image"] is None:
                continue
            total_w = max(pane["image"].width() * k, 1)
            total_h = max(pane["image"].height() * k, 1)
            pane["canvas"].xview_moveto(max(0, (x * k - 40) / total_w))
            pane["canvas"].yview_moveto(max(0, (y * k - 40) / total_h))

    def _xview(self, *args):
        for p in self.panes:
            p["canvas"].xview(*args)

    def _yview(self, *args):
        for p in self.panes:
            p["canvas"].yview(*args)

    def _hover(self, pane, event):
        img = pane["image"]
        if img is None:
            return
        k = self.factor()
        c = pane["canvas"]
        x, y = int(c.canvasx(event.x) / k), int(c.canvasy(event.y) / k)
        if not (0 <= x < img.width() and 0 <= y < img.height()):
            return
        parts = [f"x={x} y={y}"]
        for p in self.panes:
            if p["image"] is not None and x < p["image"].width() and y < p["image"].height():
                r, g, b = p["image"].get(x, y)[:3]
                parts.append(f"{p['title']}: rgb({r},{g},{b})")
        self.readout.configure(text="   ".join(parts))

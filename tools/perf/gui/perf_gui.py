#!/usr/bin/env python3
"""NativaX quality dashboard (Tkinter).

Everything is driven from this window: run the visual judge, the performance
suite or the real app-idle measurement, then inspect tables, charts,
screenshots and reports. No terminal needed after launching it.

    python3 tools/perf/gui/perf_gui.py
"""
from __future__ import annotations

import json
import math
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import messagebox, ttk

try:
    from PIL import Image, ImageTk
except Exception:  # pragma: no cover - optional thumbnails
    Image = None
    ImageTk = None

ROOT = Path(__file__).resolve().parents[3]
VISUAL_DIR = ROOT / ".visual" / "latest"
PERF_DIR = ROOT / ".perf" / "latest"
VISUAL_CANDIDATES = [
    VISUAL_DIR / "results.json",
    ROOT / ".visual" / "runs" / "50projects50days" / "results.json",
]
PERF_RESULTS = PERF_DIR / "results.json"
PERF_CATALOG = ROOT / "tools" / "perf" / "scenarios.json"
RECOMMENDATIONS_REPORT = ROOT / "progress" / "reports" / "recommendations-latest.md"
VIDEO_PROFILES = ROOT / "tools" / "video_profiles.json"
PERF_GAME_DIR = ROOT / ".perf" / "game"
PERF_GAME_RESULTS = PERF_GAME_DIR / "results.json"
PERF_GAME3D_DIR = ROOT / ".perf" / "game3d"
PERF_GAME3D_RESULTS = PERF_GAME3D_DIR / "results.json"
CONFORMANCE_DIR = ROOT / ".conformance"
CONFORMANCE_RESULTS = CONFORMANCE_DIR / "results"
CONFORMANCE_REPORT = ROOT / "progress" / "reports" / "conformance-latest.md"
VISUAL_CATALOG = ROOT / ".visual" / "catalog.json"
LIVE_REPORT = ROOT / ".perf" / "live" / "report-live.md"
PERF_CATALOG_SOURCES = [
    ROOT / "tools" / "perf" / "lib" / "src" / "scenarios.dart",
    ROOT / "tools" / "perf" / "lib" / "src" / "externals.dart",
]
VISUAL_CATALOG_SOURCES = [ROOT / "tools" / "visual" / "lib" / "src" / "fixtures.dart"]
CONSOLIDATED = ROOT / "progress" / "reports" / "nativa-quality-latest.md"

BG = "#0b0f14"
PANEL = "#11161d"
PANEL2 = "#161d26"
BORDER = "#212b36"
FG = "#e6edf3"
MUTED = "#9fb3c8"
ACCENT = "#7aa2ff"
GREEN = "#3fb950"
YELLOW = "#d29922"
RED = "#f85149"
PURPLE = "#a371f7"
CYAN = "#39c5cf"
SIDEBAR = "#0c1117"
HOVER = "#151d27"
FONT = "Noto Sans"
MONO = "DejaVu Sans Mono"
SUBTLE = "#0f151d"

sys.path.insert(0, str(ROOT / "tools"))
try:
    import recommend as recommendation_engine
except Exception:  # pragma: no cover - optional report engine
    recommendation_engine = None

VERDICT_COLORS = {"PASS": GREEN, "WARN": YELLOW, "FAIL": RED, "INVALID": PURPLE}
CATEGORY_COLORS = {
    "Posición": "#7aa2ff",
    "Layout": "#39c5cf",
    "Color": "#d2a8ff",
    "Diseño": "#ffa657",
    "Fidelidad": "#3fb950",
}


def _ram_label(config):
    if not config:
        return "—"
    if config.get("memory_mb"):
        return f"{config['memory_mb']} MB"
    return str(config.get("memory", "—"))


def _num(value, digits=2, dash="—"):
    if value is None:
        return dash
    try:
        return f"{float(value):.{digits}f}"
    except (TypeError, ValueError):
        return dash


def _mean(values):
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else 0.0


def _median(values):
    values = sorted(v for v in values if v is not None)
    if not values:
        return 0.0
    middle = len(values) // 2
    return values[middle] if len(values) % 2 else (values[middle - 1] + values[middle]) / 2


def _load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


class DataStore:
    def __init__(self):
        self.visual = None
        self.perf = None
        self.app_idle = None
        self.matrix = None
        self.catalog = None
        self.perf_catalog = None
        self.video = None
        self.game = None
        self.game3d = None
        self.conformance = None
        self.loaded_at = None

    def load(self):
        self.visual = None
        for candidate in VISUAL_CANDIDATES:
            self.visual = _load_json(candidate)
            if self.visual:
                break
        self.perf = _load_json(PERF_RESULTS)
        self.app_idle = _load_json(PERF_DIR / "app-idle.json") or _load_json(
            ROOT / ".perf" / "app-idle.json"
        )
        self.matrix = _load_json(ROOT / ".perf" / "container" / "matrix.json")
        self.catalog = _load_json(ROOT / ".visual" / "catalog.json")
        self.perf_catalog = _load_json(PERF_CATALOG) or _load_json(
            ROOT / ".perf" / "scenarios.json"
        )
        self.video = _load_json(VIDEO_PROFILES)
        self.game = _load_json(PERF_GAME_RESULTS)
        self.game3d = _load_json(PERF_GAME3D_RESULTS)
        self.loaded_at = datetime.now()

    @property
    def visual_rows(self):
        return (self.visual or {}).get("rows") or []

    @property
    def perf_rows(self):
        return (self.perf or {}).get("results") or []

    def visual_summary(self):
        rows = self.visual_rows
        return {
            "total": len(rows),
            **{
                verdict: sum(1 for r in rows if r.get("verdict") == verdict)
                for verdict in VERDICT_COLORS
            },
        }

    def visual_categories(self):
        rows = self.visual_rows
        return {
            "Posición": _mean([r.get("position") for r in rows]),
            "Layout": _mean([r.get("layout") for r in rows]),
            "Color": _mean([r.get("color") for r in rows]),
            "Diseño": _mean([r.get("design") for r in rows]),
            "Fidelidad": _mean([r.get("overall") for r in rows]),
        }

    def visual_pixels(self):
        rows = self.visual_rows
        return {
            "pixels": sum(r.get("pixels") or 0 for r in rows),
            "mismatched": sum(r.get("mismatched_pixels") or 0 for r in rows),
            "mean_delta_e": _mean([r.get("mean_delta_e") for r in rows]),
            "mean_ink": _mean([r.get("ink_mismatch_pct") for r in rows]),
            "exact_mean": _mean(
                [100 - (r.get("mismatched_pct") or 0) for r in rows]
            ),
        }

    def perf_summary(self):
        rows = self.perf_rows
        return {
            "total": len(rows),
            **{
                verdict: sum(1 for r in rows if r.get("verdict") == verdict)
                for verdict in VERDICT_COLORS
            },
        }

    @property
    def matrix_configs(self):
        return (self.matrix or {}).get("configs") or []

    @property
    def matrix_scenarios(self):
        return (self.matrix or {}).get("scenarios") or []

    def matrix_row(self, config_id, scenario):
        return (((self.matrix or {}).get("results") or {}).get(config_id) or {}).get(scenario)

    @property
    def game_rows(self):
        return (self.game or {}).get("results") or []

    @property
    def game3d_rows(self):
        return (self.game3d or {}).get("results") or []

    def perf_work(self, row, engine):
        data = row.get(engine) or {}
        return (data.get("scenario_ms") or 0) + (data.get("render_ms") or 0)


class ChartMixin:
    """Canvas drawing helpers. No matplotlib dependency."""

    def _canvas(self):
        raise NotImplementedError

    def chart_bar(
        self,
        canvas: tk.Canvas,
        title: str,
        items,
        target=None,
        max_value=None,
        unit="",
        log=False,
        color_by_value=None,
    ):
        canvas.delete("all")
        width = max(canvas.winfo_width(), 360)
        height = max(canvas.winfo_height(), 180)
        canvas.create_text(12, 12, anchor="nw", text=title, fill=MUTED,
                           font=(FONT, 9, "bold"))
        items = list(items)
        if not items:
            canvas.create_text(width / 2, height / 2, text="Sin datos",
                               fill=MUTED, font=(FONT, 10))
            return
        label_w = min(260, max(120, int(width * 0.34)))
        chart_w = max(60, width - label_w - 74)
        top = 46
        row_h = max(16, min(30, (height - top - 24) // len(items)))
        values = [float(v) for _, v, *_ in items]
        upper = max_value or max(values + ([target] if target else [0.0001]))
        upper = max(upper, 0.0001)

        def length(value):
            if log:
                return math.log10(1 + max(0.0, value)) / math.log10(1 + upper) * chart_w
            return max(0.0, value) / upper * chart_w

        for index, item in enumerate(items):
            label, value = item[0], float(item[1])
            color = item[2] if len(item) > 2 else (
                color_by_value(value) if color_by_value else ACCENT
            )
            y = top + index * row_h
            canvas.create_text(8, y + row_h / 2, anchor="w", text=str(label)[:42],
                               fill=FG, font=(FONT, 8))
            canvas.create_rectangle(label_w, y + 4, label_w + chart_w, y + row_h - 4,
                                    fill=PANEL2, outline="")
            bar = length(value)
            canvas.create_rectangle(label_w, y + 4, label_w + bar, y + row_h - 4,
                                    fill=color, outline="")
            canvas.create_text(label_w + chart_w + 6, y + row_h / 2, anchor="w",
                               text=f"{value:.2f}{unit}", fill=FG,
                               font=(FONT, 8))
        if target is not None:
            tx = label_w + length(float(target))
            canvas.create_line(tx, top - 4, tx, top + len(items) * row_h,
                               fill=YELLOW, dash=(4, 3))
            canvas.create_text(tx, height - 10, text=f"objetivo {target:g}{unit}",
                               fill=YELLOW, font=(FONT, 7), anchor="s")

    def chart_grouped(
        self,
        canvas: tk.Canvas,
        title: str,
        labels,
        series,
        unit="ms",
        log=True,
    ):
        """series: list of (name, values, color)."""
        canvas.delete("all")
        width = max(canvas.winfo_width(), 380)
        height = max(canvas.winfo_height(), 200)
        canvas.create_text(12, 12, anchor="nw", text=title, fill=MUTED,
                           font=(FONT, 9, "bold"))
        labels = list(labels)
        if not labels:
            canvas.create_text(width / 2, height / 2, text="Sin datos", fill=MUTED)
            return
        all_values = [v for _, values, _ in series for v in values if v is not None]
        upper = max(all_values + [0.001])
        label_w = min(280, max(150, int(width * 0.36)))
        chart_w = max(60, width - label_w - 92)
        top = 66
        group_h = max(18, min(30, (height - top - 30) // len(labels)))
        bar_h = max(4, (group_h - 8) // max(1, len(series)))

        def length(value):
            value = max(0.0, float(value or 0))
            if log:
                return math.log10(1 + value) / math.log10(1 + upper) * chart_w
            return value / upper * chart_w

        for index, label in enumerate(labels):
            y = top + index * group_h
            canvas.create_text(8, y + group_h / 2 - 2, anchor="w",
                               text=str(label)[:40], fill=FG,
                               font=(FONT, 8))
            for s_index, (name, values, color) in enumerate(series):
                value = values[index] if index < len(values) else 0
                bar_y = y + 2 + s_index * bar_h
                canvas.create_rectangle(label_w, bar_y, label_w + chart_w,
                                        bar_y + bar_h - 1, fill=PANEL2, outline="")
                canvas.create_rectangle(label_w, bar_y,
                                        label_w + length(value),
                                        bar_y + bar_h - 1, fill=color, outline="")
            primary = series[0][1][index] if series and index < len(series[0][1]) else 0
            canvas.create_text(label_w + chart_w + 6, y + group_h / 2 - 2,
                               anchor="w", text=f"{_num(primary, 1)} {unit}",
                               fill=FG, font=(FONT, 7))
        legend_x = label_w
        for name, _, color in series:
            canvas.create_rectangle(legend_x, 38, legend_x + 10, 47, fill=color, outline="")
            canvas.create_text(legend_x + 14, 42, anchor="w", text=name, fill=MUTED,
                               font=(FONT, 8))
            legend_x += 110

    def chart_donut(self, canvas: tk.Canvas, title: str, counts: dict[str, int]):
        canvas.delete("all")
        width = max(canvas.winfo_width(), 260)
        height = max(canvas.winfo_height(), 180)
        canvas.create_text(12, 12, anchor="nw", text=title, fill=MUTED,
                           font=(FONT, 9, "bold"))
        total = sum(counts.values())
        side = min(width - 150, height - 76, 150)
        x1 = 24
        y1 = (height - side) / 2 + 18
        x2 = x1 + side
        y2 = y1 + side
        if total == 0:
            canvas.create_text(width / 2, height / 2, text="Sin datos", fill=MUTED)
            return
        start = 90
        for name, count in counts.items():
            if count <= 0:
                continue
            extent = -360 * count / total
            canvas.create_arc(x1, y1, x2, y2, start=start, extent=extent,
                              fill=VERDICT_COLORS.get(name, MUTED), outline=BG, width=2)
            start += extent
        canvas.create_oval(x1 + side * 0.28, y1 + side * 0.28,
                           x2 - side * 0.28, y2 - side * 0.28, fill=PANEL, outline="")
        canvas.create_text((x1 + x2) / 2, (y1 + y2) / 2, text=str(total), fill=FG,
                           font=(FONT, 16, "bold"))
        legend_x = x2 + 24
        for index, (name, count) in enumerate(counts.items()):
            y = y1 + 16 + index * 24
            canvas.create_rectangle(legend_x, y - 6, legend_x + 10, y + 4,
                                    fill=VERDICT_COLORS.get(name, MUTED), outline="")
            canvas.create_text(legend_x + 16, y, anchor="w",
                               text=f"{name}: {count}", fill=FG,
                               font=(FONT, 9))

    def chart_timeline(self, canvas: tk.Canvas, title: str, series):
        canvas.delete("all")
        width = max(canvas.winfo_width(), 380)
        height = max(canvas.winfo_height(), 200)
        canvas.create_text(12, 12, anchor="nw", text=title, fill=MUTED,
                           font=(FONT, 9, "bold"))
        if not series:
            canvas.create_text(width / 2, height / 2, text="Sin muestras", fill=MUTED)
            return
        points = [p for _, values, _ in series for p in values if p and p[1] > 0]
        if not points:
            canvas.create_text(width / 2, height / 2, text="Sin muestras", fill=MUTED)
            return
        max_value = max(v for _, v in points) * 1.15 or 1
        max_x = max(x for x, _ in points) or 1
        left, top, right, bottom = 58, 56, width - 16, height - 26
        for fraction in (0, 0.25, 0.5, 0.75, 1):
            y = bottom - fraction * (bottom - top)
            canvas.create_line(left, y, right, y, fill="#1c2530")
            canvas.create_text(left - 6, y, anchor="e",
                               text=f"{max_value * fraction:.0f}", fill=MUTED,
                               font=(FONT, 7))
        canvas.create_line(left, top, left, bottom, fill="#2b3647")
        canvas.create_line(left, bottom, right, bottom, fill="#2b3647")
        legend_x = left
        for name, values, color in series:
            coords = []
            for x, value in values:
                coords.extend([
                    left + (x / max_x) * (right - left),
                    bottom - (value / max_value) * (bottom - top),
                ])
            if len(coords) >= 4:
                canvas.create_line(*coords, fill=color, width=2, smooth=True)
            canvas.create_text(legend_x, 40, anchor="w", text=name, fill=color,
                               font=(FONT, 8, "bold"))
            legend_x += 100

    def chart_gauge(
        self,
        canvas: tk.Canvas,
        title: str,
        value: float,
        maximum: float,
        target: float,
        unit="",
        invert=False,
    ):
        canvas.delete("all")
        width = max(canvas.winfo_width(), 220)
        height = max(canvas.winfo_height(), 170)
        canvas.create_text(12, 10, anchor="nw", text=title, fill=MUTED,
                           font=(FONT, 9, "bold"))
        side = min(width - 40, height - 60, 150)
        x1 = (width - side) / 2
        y1 = 34
        x2 = x1 + side
        y2 = y1 + side
        ratio = 0 if maximum <= 0 else max(0.0, min(1.0, value / maximum))
        color = GREEN
        if invert:
            color = GREEN if value <= target else (YELLOW if value <= target * 1.5 else RED)
        else:
            color = GREEN if value >= target else (YELLOW if value >= target * 0.7 else RED)
        canvas.create_arc(x1, y1, x2, y2, start=225, extent=-270, style="arc",
                          outline=PANEL2, width=16)
        canvas.create_arc(x1, y1, x2, y2, start=225, extent=-270 * ratio,
                          style="arc", outline=color, width=16)
        canvas.create_text((x1 + x2) / 2, (y1 + y2) / 2, text=f"{value:.1f}{unit}",
                           fill=FG, font=(FONT, 16, "bold"))
        canvas.create_text((x1 + x2) / 2, y2 - 6,
                           text=f"objetivo {target:g}{unit}", fill=MUTED,
                           font=(FONT, 8))


class MarkdownView(tk.Frame):
    """Readable Markdown preview: headings, paragraphs, lists, real tables."""

    def __init__(self, master):
        super().__init__(master, bg=PANEL)
        self.canvas = tk.Canvas(self, bg=PANEL, highlightthickness=0)
        self.scroll = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=self.scroll.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.scroll.pack(side="right", fill="y")
        self.content = tk.Frame(self.canvas, bg=PANEL)
        self.window = self.canvas.create_window((0, 0), window=self.content, anchor="nw")
        self.content.bind("<Configure>", self._on_content)
        self.canvas.bind("<Configure>", self._on_canvas)
        self.canvas.bind_all("<MouseWheel>", self._on_wheel, add="+")
        self.canvas.bind_all("<Button-4>", self._on_wheel, add="+")
        self.canvas.bind_all("<Button-5>", self._on_wheel, add="+")
        self._wrap_labels = []
        self._images = []
        style = ttk.Style(self)
        style.configure("Report.Treeview", background=PANEL2, fieldbackground=PANEL2,
                        foreground=FG, rowheight=25, borderwidth=0,
                        font=(FONT, 9))
        style.configure("Report.Treeview.Heading", background="#1b2530",
                        foreground=ACCENT, relief="flat",
                        font=(FONT, 9, "bold"))

    def _on_content(self, _event=None):
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _on_canvas(self, event):
        self.canvas.itemconfigure(self.window, width=event.width)
        wrap = max(400, event.width - 48)
        for label in self._wrap_labels:
            try:
                label.configure(wraplength=wrap)
            except tk.TclError:
                pass

    def _on_wheel(self, event):
        if event.num == 4:
            delta = -2
        elif event.num == 5:
            delta = 2
        else:
            delta = -1 if event.delta > 0 else 1
        self.canvas.yview_scroll(delta, "units")

    def clear(self):
        for child in self.content.winfo_children():
            child.destroy()
        self._wrap_labels.clear()
        self._images.clear()

    def _label(self, text, font, fg=FG, pady=2, padx=18, mono=False):
        label = tk.Label(self.content, text=text, bg=PANEL, fg=fg,
                         font=font, justify="left", anchor="w", padx=padx, pady=pady)
        self._wrap_labels.append(label)
        return label

    def show_png(self, path: Path):
        self.clear()
        try:
            photo = tk.PhotoImage(file=str(path))
            self._images.append(photo)
            label = tk.Label(self.content, image=photo, bg=PANEL)
            label.pack(anchor="nw")
            self.after_idle(self._reset_scroll)
        except Exception:
            pass

    def render(self, markdown: str, base_dir: Path):
        self.clear()
        lines = markdown.splitlines()
        index = 0
        while index < len(lines):
            line = lines[index]
            stripped = line.strip()
            if stripped.startswith("```"):
                index += 1
                code = []
                while index < len(lines) and not lines[index].strip().startswith("```"):
                    code.append(lines[index])
                    index += 1
                index += 1
                block = tk.Label(self.content, text="\n".join(code), bg="#0a0e14",
                                 fg="#d6dee8", justify="left", anchor="w",
                                 font=(MONO, 9), padx=12, pady=8)
                block.pack(fill="x", padx=18, pady=6)
                continue
            heading = re.match(r"^(#{1,4})\s+(.*)$", stripped)
            if heading:
                level = len(heading.group(1))
                size = {1: 18, 2: 14, 3: 12, 4: 11}[level]
                color = {1: FG, 2: ACCENT, 3: CYAN, 4: FG}[level]
                label = tk.Label(self.content, text=heading.group(2), bg=PANEL,
                                 fg=color, font=(FONT, size, "bold"),
                                 justify="left", anchor="w", padx=18,
                                 pady=14 if level <= 2 else 8)
                label.pack(fill="x")
                index += 1
                continue
            if stripped.startswith("|"):
                table = []
                while index < len(lines) and lines[index].strip().startswith("|"):
                    table.append(lines[index].strip())
                    index += 1
                self._add_table(table)
                continue
            if stripped.startswith("!["):
                match = re.match(r"!\[([^\]]*)\]\(([^)]+)\)", stripped)
                if match:
                    self._add_image(match.group(1), match.group(2), base_dir)
                index += 1
                continue
            bullet = re.match(r"^\s*[-*]\s+(.*)$", line)
            if bullet:
                text = bullet.group(1).replace("**", "").replace("`", "")
                self._label("  •  " + text, (FONT, 10), padx=30, pady=1).pack(fill="x")
                index += 1
                continue
            numbered = re.match(r"^\s*(\d+)\.\s+(.*)$", line)
            if numbered:
                text = numbered.group(2).replace("**", "").replace("`", "")
                self._label(f"  {numbered.group(1)}.  " + text, (FONT, 10),
                            padx=30, pady=1).pack(fill="x")
                index += 1
                continue
            if stripped.startswith(">"):
                self._label(stripped.lstrip("> ").strip(), (FONT, 10),
                            fg=MUTED, padx=30, pady=4).pack(fill="x")
                index += 1
                continue
            if stripped.startswith("---"):
                ttk.Separator(self.content, orient="horizontal").pack(fill="x", padx=18, pady=10)
                index += 1
                continue
            if not stripped:
                tk.Frame(self.content, bg=PANEL, height=5).pack(fill="x")
                index += 1
                continue
            paragraph = [stripped]
            index += 1
            while index < len(lines):
                nxt = lines[index].strip()
                if (not nxt or nxt.startswith("#") or nxt.startswith("|")
                        or nxt.startswith("```") or nxt.startswith("- ")
                        or nxt.startswith("* ") or nxt.startswith(">")
                        or re.match(r"^\d+\.\s", nxt) or nxt.startswith("![")):
                    break
                paragraph.append(nxt)
                index += 1
            text = " ".join(paragraph).replace("**", "").replace("`", "")
            self._label(text, (FONT, 10), pady=3).pack(fill="x")
        self.after_idle(self._reset_scroll)

    def _reset_scroll(self):
        self.canvas.update_idletasks()
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        self.canvas.yview_moveto(0)

    def _add_table(self, lines):
        rows = []
        for line in lines:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if all(re.fullmatch(r":?-{3,}:?", cell or "") for cell in cells):
                continue
            rows.append([cell.replace("**", "").replace("`", "") for cell in cells])
        if not rows:
            return
        columns = max(len(row) for row in rows)
        rows = [row + [""] * (columns - len(row)) for row in rows]
        ids = [f"c{i}" for i in range(columns)]
        tree = ttk.Treeview(self.content, columns=ids, show="headings",
                            style="Report.Treeview",
                            height=min(len(rows), 18), selectmode="browse")
        widths = []
        for i in range(columns):
            widest = max(len(row[i]) for row in rows)
            widths.append(max(90, min(360, widest * 8)))
        total = sum(widths)
        available = max(400, self.canvas.winfo_width() - 48)
        if total > available:
            factor = available / total
            widths = [max(70, int(width * factor)) for width in widths]
        for i in range(columns):
            tree.heading(ids[i], text=rows[0][i] if rows else f"Col {i+1}")
            tree.column(ids[i], width=widths[i], anchor="w", stretch=True)
        for row in rows[1:]:
            tree.insert("", "end", values=row)
        tree.pack(fill="x", padx=18, pady=6)
        ttk.Separator(self.content, orient="horizontal").pack(fill="x", padx=18, pady=(0, 6))

    def _add_image(self, alt, source, base_dir):
        path = Path(source)
        if not path.is_absolute():
            path = (base_dir / source).resolve()
        if not path.exists():
            return
        try:
            if Image is not None and ImageTk is not None:
                image = Image.open(path).convert("RGB")
                image.thumbnail((820, 520))
                photo = ImageTk.PhotoImage(image)
            else:
                source_image = tk.PhotoImage(file=str(path))
                factor = max(1, math.ceil(max(source_image.width() / 820,
                                              source_image.height() / 520)))
                photo = source_image.subsample(factor, factor)
            self._images.append(photo)
            label = tk.Label(self.content, image=photo, bg=PANEL)
            label.pack(padx=18, pady=6)
        except Exception:
            pass


class Dashboard(ChartMixin):
    def __init__(self, root: tk.Tk):
        self.root = root
        self.store = DataStore()
        self.process: subprocess.Popen | None = None
        self.log_queue: queue.Queue[str] = queue.Queue()
        self.selected_visual: dict | None = None
        self.selected_perf: dict | None = None
        self.selected_perf_pending: dict | None = None
        self.thumb_refs = []
        self.visual_report_cache = {}
        self.preview_jobs = set()
        self.preview_results: queue.Queue = queue.Queue()
        self.catalog_results: queue.Queue = queue.Queue()
        self.catalog_job = False
        self.pending_action: dict | None = None
        self._live_report_timer = None
        self._last_data_sig = None
        self._report_sig = None
        self._run_done = 0
        self._run_total = 0
        self.leak_run = None
        self.security_run = None
        if recommendation_engine is not None:
            self.leak_run = recommendation_engine.load_latest_run(
                ROOT / "benchmarks" / "leaks"
            )
            self.security_run = recommendation_engine.load_latest_run(
                ROOT / "benchmarks" / "security"
            )
        self._load_conformance()
        self._build()
        self.reload()
        self._last_data_sig = self._data_signature()
        self.root.after(150, self._drain_log)
        self.root.after(1000, self._auto_refresh)

    def _load_conformance(self):
        if not CONFORMANCE_RESULTS.exists():
            return {}
        latest = {}
        for path in CONFORMANCE_RESULTS.glob("*.summary.json"):
            try:
                data = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            suite = data.get("suite")
            command = str(data.get("command") or "")
            key = suite
            if suite == "wpt":
                if "css/selectors" in command and "dom/nodes" not in command:
                    key = "wpt-css-selectors"
                elif "dom/nodes" in command and "css/selectors" not in command:
                    key = "wpt-dom-nodes"
                else:
                    key = "wpt"
            if key not in (
                "test262", "html5lib-tokenizer", "wpt-url",
                "wpt-dom-nodes", "wpt-css-selectors", "wpt-html-tree",
            ):
                continue
            mtime = path.stat().st_mtime_ns
            if key not in latest or mtime > latest[key][0]:
                latest[key] = (mtime, data)
        return {suite: item[1] for suite, item in latest.items()}

    # ------------------------------------------------------------------ UI
    def _build(self):
        self.root.title("NativaX · Calidad y rendimiento")
        self.root.geometry("1520x980")
        self.root.minsize(1180, 760)
        self.root.configure(bg=BG)
        self._style()

        body = tk.Frame(self.root, bg=BG)
        body.pack(fill="both", expand=True)

        sidebar = tk.Frame(body, bg=SIDEBAR, width=224)
        sidebar.pack(side="left", fill="y")
        sidebar.pack_propagate(False)
        tk.Label(sidebar, text="NativaX", bg=SIDEBAR, fg=FG,
                 font=(FONT, 22, "bold")).pack(anchor="w", padx=18, pady=(18, 0))
        tk.Label(sidebar, text="calidad y rendimiento", bg=SIDEBAR, fg=MUTED,
                 font=(FONT, 9)).pack(anchor="w", padx=18, pady=(0, 18))
        tk.Frame(sidebar, bg=BORDER, height=1).pack(fill="x", padx=12, pady=(0, 10))

        self.nav_buttons = {}
        nav_items = [
            ("summary", "◈", "Resumen"),
            ("perf", "▤", "Rendimiento"),
            ("visual", "◉", "Fidelidad visual"),
            ("conformance", "✓", "Conformidad"),
            ("video", "▶", "Vídeo"),
            ("video", "▶", "Vídeo"),
            ("games", "▣", "Videojuegos"),
            ("idle", "◷", "Idle"),
            ("container", "❏", "Contenedores"),
            ("reports", "▥", "Informes"),
        ]
        for key, icon, label in nav_items:
            row = tk.Frame(sidebar, bg=SIDEBAR)
            row.pack(fill="x", padx=10, pady=1)
            bar = tk.Frame(row, bg=SIDEBAR, width=3)
            bar.pack(side="left", fill="y")
            button = tk.Label(
                row, text=f"{icon}   {label}", bg=SIDEBAR, fg=MUTED,
                anchor="w", padx=12, pady=8, cursor="hand2",
                font=(FONT, 10, "bold"),
            )
            button.bind("<Button-1>", lambda _e, k=key: self._show_page(k))
            button.bind("<Enter>", lambda _e, k=key: self._nav_hover(k, True))
            button.bind("<Leave>", lambda _e, k=key: self._nav_hover(k, False))
            button.pack(side="left", fill="x", expand=True)
            self.nav_buttons[key] = (row, bar, button)

        tk.Label(sidebar, text="", bg=SIDEBAR).pack(fill="both", expand=True)
        self.sidebar_status = tk.Label(
            sidebar, text="", bg=SIDEBAR, fg=MUTED, justify="left",
            font=(FONT, 8), padx=18, pady=12,
        )
        self.sidebar_status.pack(anchor="w", fill="x")

        main = tk.Frame(body, bg=BG)
        main.pack(side="left", fill="both", expand=True)

        topbar = tk.Frame(main, bg=BG, padx=22, pady=14)
        topbar.pack(fill="x")
        tk.Label(topbar, text="calidad visual · rendimiento · memoria",
                 bg=BG, fg=MUTED, font=(FONT, 10)).pack(side="left")
        self.header_status = tk.Label(topbar, text="", bg=BG, fg=MUTED,
                                      font=(FONT, 9))
        self.header_status.pack(side="right")
        tk.Label(topbar, text="● auto 1 s", bg=BG, fg=GREEN,
                 font=(FONT, 8)).pack(side="right", padx=(0, 10))

        bar = tk.Frame(main, bg=BG, padx=22, pady=4)
        bar.pack(fill="x")
        self.buttons = []
        self._button(bar, "▶ Ejecutar todo", self.run_all, ACCENT, "#07101f")
        self._button(bar, "Solo visual", self.run_visual, PANEL2, FG)
        self._button(bar, "Visual 300", self.run_visual_all, PANEL2, FG)
        self._button(bar, "Solo rendimiento", self.run_perf, PANEL2, FG)
        self._button(bar, "Idle app", self.run_idle, PANEL2, FG)
        self._button(bar, "Refrescar", self.reload, PANEL2, FG)
        self.stop_button = self._button(bar, "■ Detener", self.stop, "#3a2026", RED)
        self.stop_button.configure(state="disabled")
        self.progress = ttk.Progressbar(bar, mode="indeterminate", length=120)
        self.progress.pack(side="right", padx=(8, 0))
        self.status = tk.Label(bar, text="listo", bg=BG, fg=MUTED,
                               font=(FONT, 9))
        self.status.pack(side="right", padx=8)

        self.page_host = tk.Frame(main, bg=BG)
        self.page_host.pack(fill="both", expand=True, padx=18, pady=(2, 4))
        self.pages = {}
        for key in ("summary", "perf", "visual", "conformance", "video", "games",
                    "idle", "container", "reports"):
            frame = tk.Frame(self.page_host, bg=BG)
            self.pages[key] = frame
        self.tab_summary = self.pages["summary"]
        self.tab_perf = self.pages["perf"]
        self.tab_visual = self.pages["visual"]
        self.tab_conformance = self.pages["conformance"]
        self.tab_video = self.pages["video"]
        self.tab_games = self.pages["games"]
        self.tab_idle = self.pages["idle"]
        self.tab_container = self.pages["container"]
        self.tab_reports = self.pages["reports"]

        self._build_summary()
        self._build_perf()
        self._build_visual()
        self._build_conformance()
        self._build_video()
        self._build_games()
        self._build_idle()
        self._build_container()
        self._build_reports()

        log_frame = tk.Frame(main, bg=BG)
        log_frame.pack(fill="x", padx=22, pady=(0, 10))
        self.log_toggle = tk.Button(
            log_frame, text="▸ Registro", command=self._toggle_log, bg=BG, fg=MUTED,
            activebackground=BG, relief="flat", font=(FONT, 9),
            anchor="w",
        )
        self.log_toggle.pack(fill="x")
        self.log_container = tk.Frame(log_frame, bg="#070a0f")
        self.log = tk.Text(self.log_container, height=9, bg="#070a0f", fg=MUTED,
                           relief="flat", font=(MONO, 9),
                           padx=8, pady=6, insertbackground=FG)
        self.log.pack(fill="both", expand=True)
        self.log.configure(state="disabled")
        self.log_visible = False
        self._show_page("summary")

    def _data_signature(self):
        paths = [
            *VISUAL_CANDIDATES,
            PERF_RESULTS,
            PERF_DIR / "app-idle.json",
            ROOT / ".perf" / "app-idle.json",
            ROOT / ".perf" / "container" / "matrix.json",
            ROOT / ".visual" / "catalog.json",
            PERF_CATALOG,
            ROOT / ".perf" / "scenarios.json",
            VIDEO_PROFILES,
            PERF_GAME_RESULTS,
            PERF_GAME3D_RESULTS,
            CONFORMANCE_DIR,
            CONFORMANCE_REPORT,
            *sorted((ROOT / "progress" / "reports").glob("*-latest.md")),
        ]
        state = []
        for path in paths:
            try:
                stat = path.stat()
                state.append((str(path), stat.st_mtime_ns, stat.st_size))
            except OSError:
                state.append((str(path), 0, 0))
        return tuple(state)

    def _auto_refresh(self):
        try:
            self._refresh_catalogs()
            signature = self._data_signature()
            if signature != self._last_data_sig:
                self._last_data_sig = signature
                self._refresh_data()
            self._refresh_report()
        except Exception as error:
            self._append_log(f"auto-refresh: {error}\n")
        finally:
            self.root.after(1000, self._auto_refresh)

    def _refresh_report(self):
        path = self._report_path()
        try:
            mtime = path.stat().st_mtime_ns
        except OSError:
            mtime = 0
        if mtime != self._report_sig:
            self._report_sig = mtime
            self._load_report()

    def _refresh_catalogs(self):
        if self.catalog_job:
            return
        perf_stale = self._catalog_stale(PERF_CATALOG, PERF_CATALOG_SOURCES)
        visual_stale = self._catalog_stale(VISUAL_CATALOG, VISUAL_CATALOG_SOURCES)
        if not perf_stale and not visual_stale:
            return
        self.catalog_job = True

        def worker():
            try:
                if perf_stale:
                    result = subprocess.run(
                        ["dart", "run", "tools/perf/bin/perf.dart",
                         "list", "--json"],
                        cwd=ROOT, capture_output=True, text=True, timeout=180,
                    )
                    if result.returncode == 0 and result.stdout.strip():
                        rows = json.loads(result.stdout)
                        if isinstance(rows, list) and rows:
                            tmp = PERF_CATALOG.with_suffix(".tmp")
                            tmp.write_text(json.dumps(rows, indent=2) + "\n")
                            tmp.replace(PERF_CATALOG)
                            self.catalog_results.put("rendimiento")
                if visual_stale:
                    result = subprocess.run(
                        ["dart", "run", "tools/visual/bin/visual_check.dart",
                         "--all", "--list", "--json"],
                        cwd=ROOT, capture_output=True, text=True, timeout=300,
                    )
                    if result.returncode == 0 and result.stdout.strip():
                        rows = json.loads(result.stdout)
                        if isinstance(rows, list) and rows:
                            VISUAL_CATALOG.parent.mkdir(parents=True, exist_ok=True)
                            tmp = VISUAL_CATALOG.with_suffix(".tmp")
                            tmp.write_text(json.dumps(rows, indent=2) + "\n")
                            tmp.replace(VISUAL_CATALOG)
                            self.catalog_results.put("visual")
            except Exception as error:
                self.log_queue.put(f"catálogo: {error}\n")
            finally:
                self.catalog_job = False

        threading.Thread(target=worker, daemon=True).start()

    @staticmethod
    def _catalog_stale(catalog: Path, sources) -> bool:
        try:
            catalog_mtime = catalog.stat().st_mtime_ns
        except OSError:
            return True
        for source in sources:
            try:
                if source.stat().st_mtime_ns > catalog_mtime:
                    return True
            except OSError:
                continue
        return False

    def _show_page(self, key):
        for name, frame in self.pages.items():
            if name == key:
                frame.pack(fill="both", expand=True)
            else:
                frame.pack_forget()
        for name, (row, bar, button) in self.nav_buttons.items():
            active = name == key
            bg = HOVER if active else SIDEBAR
            row.configure(bg=bg)
            button.configure(bg=bg, fg=FG if active else MUTED)
            bar.configure(bg=ACCENT if active else bg)
        self.active_page = key
        if key == "reports" and hasattr(self, "report_view"):
            self.root.after(50, self._load_report)

    def _nav_hover(self, key, entering):
        if getattr(self, "active_page", None) == key:
            return
        row, bar, button = self.nav_buttons[key]
        bg = HOVER if entering else SIDEBAR
        row.configure(bg=bg)
        button.configure(bg=bg, fg=FG if entering else MUTED)

    def _page_header(self, parent, title, subtitle):
        header = tk.Frame(parent, bg=BG)
        header.pack(fill="x", pady=(6, 10))
        tk.Label(header, text=title, bg=BG, fg=FG,
                 font=(FONT, 20, "bold")).pack(anchor="w")
        tk.Label(header, text=subtitle, bg=BG, fg=MUTED,
                 font=(FONT, 9)).pack(anchor="w", pady=(2, 0))

    def _style(self):
        style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TNotebook", background=BG, borderwidth=0)
        style.configure("TNotebook.Tab", background=PANEL, foreground=MUTED,
                        padding=(14, 7), font=(FONT, 10, "bold"))
        style.map("TNotebook.Tab", background=[("selected", PANEL2)],
                  foreground=[("selected", FG)])
        style.configure("Treeview", background=PANEL, fieldbackground=PANEL,
                        foreground=FG, rowheight=28, borderwidth=0,
                        font=(FONT, 9))
        style.configure("Treeview.Heading", background=PANEL2, foreground=MUTED,
                        relief="flat", font=(FONT, 9, "bold"), padding=(6, 6))
        style.map("Treeview", background=[("selected", "#23324a")])
        style.configure("TEntry", fieldbackground=PANEL2, foreground=FG,
                        insertcolor=FG, borderwidth=0)
        style.configure("TCombobox", fieldbackground=PANEL2, background=PANEL2,
                        foreground=FG, arrowcolor=FG)
        style.configure("TProgressbar", background=ACCENT, troughcolor=PANEL2)

    def _button(self, parent, text, command, bg, fg):
        button = tk.Button(parent, text=text, command=command, bg=bg, fg=fg,
                           activebackground="#22304a", activeforeground=FG,
                           relief="flat", bd=0, highlightthickness=0,
                           padx=12, pady=6,
                           font=(FONT, 10, "bold" if bg == ACCENT else "normal"))
        button.pack(side="left", padx=(0, 8))
        self.buttons.append(button)
        return button

    def _card(self, parent, title, value="—", subtitle=""):
        frame = tk.Frame(parent, bg=PANEL, padx=14, pady=10,
                         highlightbackground=BORDER, highlightthickness=1)
        tk.Label(frame, text=title, bg=PANEL, fg=MUTED,
                 font=(FONT, 9, "bold")).pack(anchor="w")
        value_label = tk.Label(frame, text=value, bg=PANEL, fg=FG,
                               font=(FONT, 20, "bold"))
        value_label.pack(anchor="w", pady=(2, 0))
        subtitle_label = tk.Label(frame, text=subtitle, bg=PANEL, fg=MUTED,
                                  font=(FONT, 8))
        subtitle_label.pack(anchor="w")
        return frame, value_label, subtitle_label

    # --------------------------------------------------------------- summary
    def _build_summary(self):
        tab = self.tab_summary
        self._page_header(tab, "Resumen", "Fidelidad, rendimiento y memoria en una sola vista.")
        cards = tk.Frame(tab, bg=BG)
        cards.pack(fill="x", pady=(4, 8))
        self.card_visual, self.card_visual_value, self.card_visual_sub = self._card(
            cards, "Fidelidad visual", "—", "51 páginas"
        )
        self.card_visual.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.card_perf, self.card_perf_value, self.card_perf_sub = self._card(
            cards, "Rendimiento", "—", "17 escenarios"
        )
        self.card_perf.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.card_idle, self.card_idle_value, self.card_idle_sub = self._card(
            cards, "App idle", "—", "250 MB / 1 % CPU"
        )
        self.card_idle.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.card_pixels, self.card_pixels_value, self.card_pixels_sub = self._card(
            cards, "Píxeles", "—", "ΔE > 2"
        )
        self.card_pixels.pack(side="left", fill="both", expand=True)

        charts = tk.Frame(tab, bg=BG)
        charts.pack(fill="both", expand=True)
        left = tk.Frame(charts, bg=PANEL, highlightbackground=BORDER, highlightthickness=1)
        left.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.summary_categories = tk.Canvas(left, bg=PANEL, highlightthickness=0)
        self.summary_categories.pack(fill="both", expand=True, padx=8, pady=(8, 0))
        note = tk.Frame(left, bg=PANEL)
        note.pack(fill="x", padx=14, pady=(0, 10))
        tk.Label(note, text="CÓMO SE CALCULA", bg=PANEL, fg=MUTED,
                 font=(FONT, 8, "bold")).pack(anchor="w")
        tk.Label(
            note,
            text="Overall = 30 % posición + 30 % layout + 25 % color + 15 % diseño.\n"
                 "El color se mide dentro de cada caja; la tinta evita que una página vacía pase.",
            bg=PANEL, fg=MUTED, justify="left", font=(FONT, 8),
        ).pack(anchor="w", pady=(3, 0))
        right = tk.Frame(charts, bg=PANEL, highlightbackground=BORDER, highlightthickness=1)
        right.pack(side="left", fill="both", expand=True)
        self.summary_donut_visual = tk.Canvas(right, bg=PANEL, height=190, highlightthickness=0)
        self.summary_donut_visual.pack(fill="x", padx=8, pady=(8, 2))
        self.summary_donut_perf = tk.Canvas(right, bg=PANEL, height=190, highlightthickness=0)
        self.summary_donut_perf.pack(fill="x", padx=8, pady=(2, 8))

        bottom = tk.Frame(tab, bg=BG)
        bottom.pack(fill="x", pady=(8, 0))
        self.summary_worst_pages = tk.Text(bottom, height=6, bg=PANEL, fg=FG,
                                           relief="flat", font=(MONO, 9),
                                           bd=0, highlightthickness=1,
                                           highlightbackground=BORDER,
                                           highlightcolor=BORDER,
                                           padx=10, pady=8)
        self.summary_worst_pages.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.summary_worst_scenarios = tk.Text(bottom, height=6, bg=PANEL, fg=FG,
                                               relief="flat", font=(MONO, 9),
                                               bd=0, highlightthickness=1,
                                               highlightbackground=BORDER,
                                               highlightcolor=BORDER,
                                               padx=10, pady=8)
        self.summary_worst_scenarios.pack(side="left", fill="both", expand=True)
        for canvas in (self.summary_categories, self.summary_donut_visual,
                       self.summary_donut_perf):
            canvas.bind("<Configure>", lambda _e: self._draw_summary())

    # ------------------------------------------------------------ performance
    def _build_perf(self):
        tab = self.tab_perf
        self._page_header(tab, "Rendimiento", "Escenarios, frames, nodos y consumo por motor.")
        top = tk.Frame(tab, bg=BG)
        top.pack(fill="x", pady=(4, 6))
        tk.Label(top, text="Escenarios", bg=BG, fg=FG,
                 font=(FONT, 11, "bold")).pack(side="left")
        self.perf_summary = tk.Label(top, text="", bg=BG, fg=MUTED,
                                     font=(FONT, 9))
        self.perf_summary.pack(side="left", padx=10)
        self.perf_filter = tk.Entry(top, bg=PANEL2, fg=FG, insertbackground=FG,
                                    relief="flat", width=24)
        self.perf_filter.pack(side="right", padx=4)
        self.perf_filter.bind("<KeyRelease>", lambda _e: self._fill_perf_table())
        tk.Label(top, text="filtrar", bg=BG, fg=MUTED,
                 font=(FONT, 9)).pack(side="right")
        self.perf_actions = tk.Button(
            top, text="Acciones ▾", command=self._perf_actions_menu,
            bg=PANEL2, fg=FG, activebackground=HOVER, relief="flat",
            bd=0, highlightthickness=0, padx=8, pady=3, font=(FONT, 9, "bold"),
        )
        self.perf_actions.pack(side="right", padx=4)
        tk.Label(top, text="clic derecho en una fila", bg=BG, fg=MUTED,
                 font=(FONT, 8)).pack(side="left", padx=8)

        panes = tk.PanedWindow(tab, orient="horizontal", bg=BG, sashwidth=6)
        panes.pack(fill="both", expand=True)
        left = tk.Frame(panes, bg=BG)
        panes.add(left, stretch="always")
        columns = ("scenario", "verdict", "nativa", "chrome", "ratio", "nodes",
                   "p95", "rss")
        self.perf_tree = ttk.Treeview(left, columns=columns, show="headings",
                                       selectmode="browse")
        for column, label, width, anchor in [
            ("scenario", "Escenario", 187, "w"),
            ("verdict", "Veredicto", 71, "w"),
            ("nativa", "NativaX", 71, "e"),
            ("chrome", "Chromium", 78, "e"),
            ("ratio", "Ratio", 56, "e"),
            ("nodes", "Nodos", 70, "e"),
            ("p95", "p95", 54, "e"),
            ("rss", "RSS arnés", 86, "e"),
        ]:
            self.perf_tree.heading(column, text=label)
            self.perf_tree.column(column, width=width, anchor=anchor)
        scroll = ttk.Scrollbar(left, orient="vertical", command=self.perf_tree.yview)
        self.perf_tree.configure(yscrollcommand=scroll.set)
        self.perf_tree.pack(side="left", fill="both", expand=True)
        scroll.pack(side="left", fill="y")
        self.perf_tree.bind("<<TreeviewSelect>>", self._on_perf_select)
        self.perf_tree.bind("<Button-3>", self._perf_context_menu)
        self.perf_tree.bind("<Double-1>", lambda _e: self.open_detail("perf"))
        for verdict, color in VERDICT_COLORS.items():
            self.perf_tree.tag_configure(verdict, foreground=color)
        self.perf_tree.tag_configure("odd", background=SUBTLE)
        self.perf_tree.tag_configure("pending", foreground=MUTED)

        right = tk.Frame(panes, bg=PANEL, width=560)
        panes.add(right, stretch="never")
        right.pack_propagate(False)
        self.perf_detail = tk.Text(right, height=11, bg=PANEL, fg=FG,
                                   relief="flat", wrap="word", padx=10, pady=8,
                                   font=(MONO, 9))
        self.perf_detail.pack(fill="x")
        self.perf_work_chart = tk.Canvas(right, bg=PANEL, height=250,
                                         highlightthickness=0)
        self.perf_work_chart.pack(fill="x", padx=8, pady=(10, 6))
        self.perf_timeline = tk.Canvas(right, bg=PANEL, height=170,
                                       highlightthickness=0)
        self.perf_timeline.pack(fill="x", padx=8, pady=(6, 10))
        self.perf_work_chart.bind("<Configure>", lambda _e: self._draw_perf_charts())
        self.perf_timeline.bind("<Configure>", lambda _e: self._draw_perf_charts())

    # --------------------------------------------------------------- visual
    def _build_visual(self):
        tab = self.tab_visual
        self._page_header(tab, "Fidelidad visual", "Píxel a píxel, color, layout y diseño computado.")
        top = tk.Frame(tab, bg=BG)
        top.pack(fill="x", pady=(4, 6))
        tk.Label(top, text="Páginas", bg=BG, fg=FG,
                 font=(FONT, 11, "bold")).pack(side="left")
        self.visual_summary = tk.Label(top, text="", bg=BG, fg=MUTED,
                                       font=(FONT, 9))
        self.visual_summary.pack(side="left", padx=10)
        self.visual_filter = tk.Entry(top, bg=PANEL2, fg=FG, insertbackground=FG,
                                      relief="flat", width=24)
        self.visual_filter.pack(side="right", padx=4)
        self.visual_filter.bind("<KeyRelease>", lambda _e: self._fill_visual_table())
        tk.Label(top, text="filtrar", bg=BG, fg=MUTED,
                 font=(FONT, 9)).pack(side="right")
        self.visual_actions = tk.Button(
            top, text="Acciones ▾", command=self._visual_actions_menu,
            bg=PANEL2, fg=FG, activebackground=HOVER, relief="flat",
            bd=0, highlightthickness=0, padx=8, pady=3, font=(FONT, 9, "bold"),
        )
        self.visual_actions.pack(side="right", padx=4)
        tk.Label(top, text="clic derecho en una página", bg=BG, fg=MUTED,
                 font=(FONT, 8)).pack(side="left", padx=8)

        panes = tk.PanedWindow(tab, orient="horizontal", bg=BG, sashwidth=6)
        panes.pack(fill="both", expand=True)
        left = tk.Frame(panes, bg=BG)
        panes.add(left, stretch="always")
        columns = ("page", "verdict", "overall", "position", "layout", "color",
                   "design")
        self.visual_tree = ttk.Treeview(left, columns=columns, show="headings",
                                         selectmode="browse")
        for column, label, width, anchor in [
            ("page", "Página", 232, "w"),
            ("verdict", "Veredicto", 66, "w"),
            ("overall", "Overall", 62, "e"),
            ("position", "Posición", 62, "e"),
            ("layout", "Layout", 58, "e"),
            ("color", "Color", 56, "e"),
            ("design", "Diseño", 60, "e"),
        ]:
            self.visual_tree.heading(column, text=label)
            self.visual_tree.column(column, width=width, anchor=anchor)
        scroll = ttk.Scrollbar(left, orient="vertical", command=self.visual_tree.yview)
        self.visual_tree.configure(yscrollcommand=scroll.set)
        self.visual_tree.pack(side="left", fill="both", expand=True)
        scroll.pack(side="left", fill="y")
        self.visual_tree.bind("<<TreeviewSelect>>", self._on_visual_select)
        self.visual_tree.bind("<Button-3>", self._visual_context_menu)
        self.visual_tree.bind("<Double-1>", lambda _e: self.open_detail("visual"))
        for verdict, color in VERDICT_COLORS.items():
            self.visual_tree.tag_configure(verdict, foreground=color)
        self.visual_tree.tag_configure("pending", foreground=MUTED)
        self.visual_tree.tag_configure("odd", background=SUBTLE)

        right = tk.Frame(panes, bg=PANEL, width=620)
        panes.add(right, stretch="never")
        right.pack_propagate(False)
        self.visual_detail = tk.Text(right, height=9, bg=PANEL, fg=FG,
                                     relief="flat", wrap="word", padx=10, pady=8,
                                     font=(MONO, 9))
        self.visual_detail.pack(fill="x")
        self.visual_categories = tk.Canvas(right, bg=PANEL, height=170,
                                           highlightthickness=0)
        self.visual_categories.pack(fill="x", padx=8, pady=(8, 4))
        self.visual_pixels = tk.Canvas(right, bg=PANEL, height=150,
                                       highlightthickness=0)
        self.visual_pixels.pack(fill="x", padx=8, pady=(4, 8))
        self.visual_categories.bind("<Configure>", lambda _e: self._draw_visual_charts())
        self.visual_pixels.bind("<Configure>", lambda _e: self._draw_visual_charts())

        images = tk.Frame(right, bg=PANEL)
        images.pack(fill="both", expand=True, padx=8, pady=(2, 8))
        self.thumb_labels = []
        for title in ("Chromium", "NativaX", "Diferencia"):
            frame = tk.Frame(images, bg=PANEL2, padx=4, pady=4)
            frame.pack(side="left", fill="both", expand=True, padx=3)
            label = tk.Label(frame, text="sin captura", bg=PANEL2, fg=MUTED,
                             font=(FONT, 8), width=22, height=9)
            label.pack(fill="both", expand=True)
            tk.Label(frame, text=title, bg=PANEL2, fg=MUTED,
                     font=(FONT, 8)).pack()
            self.thumb_labels.append(label)

    # ----------------------------------------------------------------- idle
    # ----------------------------------------------------------- conformance
    def _build_conformance(self):
        tab = self.tab_conformance
        self._page_header(
            tab, "Conformidad",
            "Test262, html5lib, URL, WPT DOM, CSS selectors y tree construction.",
        )
        top = tk.Frame(tab, bg=BG)
        top.pack(fill="x", pady=(4, 6))
        tk.Label(top, text="Suites oficiales", bg=BG, fg=FG,
                 font=(FONT, 11, "bold")).pack(side="left")
        self.conformance_summary = tk.Label(top, text="", bg=BG, fg=MUTED,
                                           font=(FONT, 9))
        self.conformance_summary.pack(side="left", padx=10)
        for label, command in (
            ("Test262", self.run_conformance_test262),
            ("html5lib", self.run_conformance_html5lib),
            ("URL", self.run_conformance_url),
            ("WPT DOM", self.run_conformance_wpt_dom),
            ("WPT CSS", self.run_conformance_wpt_css),
            ("WPT tree", self.run_conformance_wpt_tree),
        ):
            tk.Button(
                top, text=label, command=command, bg=PANEL2, fg=FG,
                activebackground=HOVER, relief="flat", bd=0,
                highlightthickness=0, padx=8, pady=3, font=(FONT, 9, "bold"),
            ).pack(side="right", padx=2)
        tk.Button(
            top, text="Todo", command=self.run_conformance_all,
            bg=ACCENT, fg="#07101f", relief="flat", bd=0,
            highlightthickness=0, padx=8, pady=3, font=(FONT, 9, "bold"),
        ).pack(side="right", padx=(2, 6))

        panes = tk.Frame(tab, bg=BG)
        panes.pack(fill="both", expand=True)
        columns = ("suite", "tests", "pass", "fail", "skip", "error", "rate", "target")
        self.conformance_tree = ttk.Treeview(
            panes, columns=columns, show="headings", selectmode="browse"
        )
        for column, label, width, anchor in [
            ("suite", "Suite", 250, "w"),
            ("tests", "Tests", 90, "e"),
            ("pass", "PASS", 90, "e"),
            ("fail", "FAIL", 90, "e"),
            ("skip", "SKIP", 90, "e"),
            ("error", "ERROR", 90, "e"),
            ("rate", "Tasa %", 90, "e"),
            ("target", "Objetivo", 100, "e"),
        ]:
            self.conformance_tree.heading(column, text=label)
            self.conformance_tree.column(column, width=width, anchor=anchor)
        scroll = ttk.Scrollbar(panes, orient="vertical", command=self.conformance_tree.yview)
        self.conformance_tree.configure(yscrollcommand=scroll.set)
        self.conformance_tree.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        self.conformance_note = tk.Label(
            tab, text="", bg=BG, fg=MUTED, justify="left",
            anchor="w", font=(FONT, 9), wraplength=1100,
        )
        self.conformance_note.pack(fill="x", pady=(6, 0))

    def _fill_conformance(self):
        if not hasattr(self, "conformance_tree"):
            return
        selected = self.conformance_tree.selection()
        view = self.conformance_tree.yview()
        for item in self.conformance_tree.get_children():
            self.conformance_tree.delete(item)
        display = {
            "test262": ("Test262 (ECMAScript)", 70),
            "html5lib-tokenizer": ("html5lib tokenizer", 70),
            "wpt-url": ("WPT URL", 70),
            "wpt-dom-nodes": ("WPT DOM nodes", 70),
            "wpt-css-selectors": ("WPT CSS selectors", 70),
            "wpt-html-tree": ("WPT tree construction", 70),
        }
        total_pass = 0
        total_fail = 0
        total_skip = 0
        total_error = 0
        total_tests = 0
        for suite, data in sorted((self.conformance or {}).items()):
            counts = data.get("counts") or {}
            tests = int(counts.get("PASS", 0)) + int(counts.get("FAIL", 0)) + int(counts.get("SKIP", 0)) + int(counts.get("ERROR", 0))
            pass_count = int(counts.get("PASS", 0))
            total_tests += tests
            total_pass += pass_count
            total_fail += int(counts.get("FAIL", 0))
            total_skip += int(counts.get("SKIP", 0))
            total_error += int(counts.get("ERROR", 0))
            rate = float(data.get("passRate") or 0)
            target = display.get(suite, (suite, 70))[1]
            status = "OK" if rate >= target else "NO"
            self.conformance_tree.insert("", "end", iid=suite, values=(
                display.get(suite, (suite, 70))[0],
                tests, pass_count, counts.get("FAIL", 0),
                counts.get("SKIP", 0), counts.get("ERROR", 0),
                f"{rate:.2f}", f"{target} % · {status}",
            ))
        children = self.conformance_tree.get_children()
        if selected and self.conformance_tree.exists(selected[0]):
            self.conformance_tree.selection_set(selected[0])
        elif children:
            self.conformance_tree.selection_set(children[0])
        if view:
            self.conformance_tree.yview_moveto(view[0])
        if self.conformance:
            self.conformance_summary.configure(
                text=f"{total_pass}/{total_tests} PASS · "
                     f"{len(self.conformance)} suites"
            )
            self.conformance_note.configure(
                text=(
                    "Los suites WPT son adaptadores mínimos: no cubren reftests, "
                    "testdriver, workers ni el testharness completo. Los SKIP no "
                    "cuentan como compatibilidad."
                )
            )
        else:
            self.conformance_summary.configure(text="sin resultados")
            self.conformance_note.configure(
                text="Ejecuta las suites para poblar esta página. Los resultados "
                     "se leen de .conformance/results/*.summary.json."
            )

    def _write_conformance_report(self):
        self.conformance = self._load_conformance()
        data = self.conformance or {}
        lines = ["# NativaX — conformidad", "", f"Generado: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}.", ""]
        if data:
            lines.extend(["| Suite | Tests | PASS | FAIL | SKIP | ERROR | Tasa % |", "|---|---:|---:|---:|---:|---:|---:|"])
            for suite, item in sorted(data.items()):
                counts = item.get("counts") or {}
                tests = sum(int(counts.get(k, 0)) for k in ("PASS", "FAIL", "SKIP", "ERROR"))
                lines.append(
                    f"| {suite} | {tests} | {counts.get('PASS', 0)} | "
                    f"{counts.get('FAIL', 0)} | {counts.get('SKIP', 0)} | "
                    f"{counts.get('ERROR', 0)} | {_num(item.get('passRate'), 2)} |"
                )
            lines.append("")
        else:
            lines.append("Sin resultados de conformidad.")
        CONFORMANCE_REPORT.parent.mkdir(parents=True, exist_ok=True)
        tmp = CONFORMANCE_REPORT.with_suffix(".md.tmp")
        tmp.write_text("\n".join(lines))
        tmp.replace(CONFORMANCE_REPORT)

    # ----------------------------------------------------------------- video
    def _build_video(self):
        tab = self.tab_video
        self._page_header(
            tab, "Vídeo",
            "Contrato de calidad 360p–2160p. NativaX todavía no decodifica vídeo.",
        )
        banner = tk.Frame(tab, bg="#2a1d12", highlightbackground=YELLOW,
                          highlightthickness=1)
        banner.pack(fill="x", pady=(0, 8))
        tk.Label(
            banner,
            text="REPRODUCCIÓN REAL: NO  ·  decoder: none  ·  "
                 "MEDIA_ERR_SRC_NOT_SUPPORTED",
            bg="#2a1d12", fg=YELLOW, font=(FONT, 11, "bold"),
            anchor="w", padx=12, pady=8,
        ).pack(fill="x")
        tk.Label(
            banner,
            text="Los 25 tests verifican el placeholder, la caja y el contrato "
                 "del DOM. No convierten el vídeo en compatible ni simulan playback.",
            bg="#2a1d12", fg=MUTED, font=(FONT, 9),
            anchor="w", padx=12, pady=4,
        ).pack(fill="x")

        cards = tk.Frame(tab, bg=BG)
        cards.pack(fill="x", pady=(0, 8))
        self.video_profiles_card, self.video_profiles_value, _ = self._card(
            cards, "Perfiles", "—", "360p–2160p"
        )
        self.video_profiles_card.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.video_tests_card, self.video_tests_value, self.video_tests_sub = self._card(
            cards, "Contrato", "—", "última corrida"
        )
        self.video_tests_card.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.video_play_card, self.video_play_value, self.video_play_sub = self._card(
            cards, "Playback", "NO", "sin pipeline multimedia"
        )
        self.video_play_card.pack(side="left", fill="both", expand=True)

        top = tk.Frame(tab, bg=BG)
        top.pack(fill="x", pady=(2, 6))
        tk.Label(top, text="Perfiles de vídeo", bg=BG, fg=FG,
                 font=(FONT, 11, "bold")).pack(side="left")
        self.video_last = tk.Label(top, text="", bg=BG, fg=MUTED,
                                   font=(FONT, 9))
        self.video_last.pack(side="left", padx=10)
        tk.Button(
            top, text="Ejecutar tests de vídeo", command=self.run_video_tests,
            bg=PANEL2, fg=FG, activebackground=HOVER, relief="flat",
            bd=0, highlightthickness=0, padx=10, pady=4,
            font=(FONT, 9, "bold"),
        ).pack(side="right")

        panes = tk.Frame(tab, bg=BG)
        panes.pack(fill="both", expand=True)
        columns = ("profile", "box", "attributes", "contract", "status")
        self.video_tree = ttk.Treeview(
            panes, columns=columns, show="headings", selectmode="browse"
        )
        for column, label, width, anchor in [
            ("profile", "Perfil", 150, "w"),
            ("box", "Caja CSS", 110, "w"),
            ("attributes", "Atributos", 390, "w"),
            ("contract", "Contrato actual", 300, "w"),
            ("status", "Test", 110, "w"),
        ]:
            self.video_tree.heading(column, text=label)
            self.video_tree.column(column, width=width, anchor=anchor)
        scroll = ttk.Scrollbar(
            panes, orient="vertical", command=self.video_tree.yview
        )
        self.video_tree.configure(yscrollcommand=scroll.set)
        self.video_tree.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        for status, color in (
            ("PASS", GREEN), ("FAIL", RED), ("SKIP", YELLOW),
            ("CONTRATO", CYAN),
        ):
            self.video_tree.tag_configure(status, foreground=color)
        self.video_note = tk.Label(
            tab, text="", bg=BG, fg=MUTED, justify="left",
            anchor="w", font=(FONT, 9), wraplength=1100,
        )
        self.video_note.pack(fill="x", pady=(6, 0))

    def _fill_video(self):
        if not hasattr(self, "video_tree"):
            return
        data = self.store.video or {}
        profiles = data.get("profiles") or []
        capability = data.get("capability") or {}
        last = data.get("last_run") or {}
        status = str(last.get("status") or "—").upper()
        self.video_profiles_value.configure(text=str(len(profiles)))
        self.video_tests_value.configure(text=f"{status}" if status != "—" else "—")
        self.video_tests_sub.configure(
            text=f"{last.get('tests', '—')} tests · {last.get('date', 'sin fecha')}"
        )
        self.video_play_value.configure(text="NO")
        self.video_play_sub.configure(text="sin pipeline multimedia")
        self.video_last.configure(
            text=f"última corrida: {status} · {last.get('date', '—')}"
        )
        selected = self.video_tree.selection()
        view = self.video_tree.yview()
        for item in self.video_tree.get_children():
            self.video_tree.delete(item)
        for index, profile in enumerate(profiles):
            test = str(profile.get("test") or "")
            row_status = str(profile.get("status") or "CONTRATO").upper()
            tags = (row_status,)
            if index % 2:
                tags = tags + ("odd",)
            self.video_tree.insert(
                "", "end", iid=str(profile.get("id")),
                tags=tags,
                values=(
                    profile.get("id", ""),
                    profile.get("box", ""),
                    profile.get("attributes", ""),
                    profile.get("contract", "MEDIA_ERR_SRC_NOT_SUPPORTED"),
                    row_status,
                ),
            )
        self.video_tree.tag_configure("odd", background=SUBTLE)
        if selected and self.video_tree.exists(selected[0]):
            self.video_tree.selection_set(selected[0])
        elif self.video_tree.get_children():
            self.video_tree.selection_set(self.video_tree.get_children()[0])
        if view:
            self.video_tree.yview_moveto(view[0])
        self.video_note.configure(
            text=(
                "Contrato actual: "
                f"{capability.get('media_error', 'MEDIA_ERR_SRC_NOT_SUPPORTED')}. "
                "No hay decoder ni pipeline de audio/sincronización: los tests "
                "son de layout y comportamiento del DOM, no de reproducción."
            )
        )

    # ---------------------------------------------------------------- games
    def _build_games(self):
        tab = self.tab_games
        self._page_header(
            tab, "Videojuegos",
            "50 perfiles: 25 Canvas 2D + 25 WebGL 3D, por resolución y carga.",
        )
        top = tk.Frame(tab, bg=BG)
        top.pack(fill="x", pady=(4, 6))
        tk.Label(top, text="Perfiles de juego", bg=BG, fg=FG,
                 font=(FONT, 11, "bold")).pack(side="left")
        self.game_summary = tk.Label(top, text="", bg=BG, fg=MUTED,
                                     font=(FONT, 9))
        self.game_summary.pack(side="left", padx=10)
        tk.Button(
            top, text="Ejecutar 25 3D", command=self.run_games3d,
            bg=PANEL2, fg=FG, activebackground=HOVER, relief="flat",
            bd=0, highlightthickness=0, padx=10, pady=4,
            font=(FONT, 9, "bold"),
        ).pack(side="right", padx=(0, 6))
        tk.Button(
            top, text="Ejecutar 25 2D", command=self.run_games,
            bg=PANEL2, fg=FG, activebackground=HOVER, relief="flat",
            bd=0, highlightthickness=0, padx=10, pady=4,
            font=(FONT, 9, "bold"),
        ).pack(side="right")
        tk.Label(
            tab,
            text="2D: Canvas 2D. 3D: WebGL con cubos, perspectiva y "
                 "profundidad. Resoluciones 640x360–2560x1440 y cargas "
                 "100–5.000. No es el game-player Three.js completo.",
            bg=BG, fg=MUTED, anchor="w", font=(FONT, 9),
            wraplength=1100,
        ).pack(fill="x", pady=(0, 6))

        panes = tk.Frame(tab, bg=BG)
        panes.pack(fill="both", expand=True)
        columns = ("type", "scenario", "resolution", "particles", "verdict",
                   "nativa", "chrome", "ratio", "p95", "rss")
        self.game_tree = ttk.Treeview(
            panes, columns=columns, show="headings", selectmode="browse"
        )
        for column, label, width, anchor in [
            ("type", "Tipo", 54, "w"),
            ("scenario", "Escenario", 300, "w"),
            ("resolution", "Resolución", 110, "w"),
            ("particles", "Partículas", 90, "e"),
            ("verdict", "Veredicto", 90, "w"),
            ("nativa", "NativaX ms", 90, "e"),
            ("chrome", "Chromium ms", 100, "e"),
            ("ratio", "Ratio", 70, "e"),
            ("p95", "p95 ms", 70, "e"),
            ("rss", "RSS arnés", 90, "e"),
        ]:
            self.game_tree.heading(column, text=label)
            self.game_tree.column(column, width=width, anchor=anchor)
        scroll = ttk.Scrollbar(
            panes, orient="vertical", command=self.game_tree.yview
        )
        self.game_tree.configure(yscrollcommand=scroll.set)
        self.game_tree.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        for verdict, color in VERDICT_COLORS.items():
            self.game_tree.tag_configure(verdict, foreground=color)
        self.game_tree.tag_configure("pending", foreground=MUTED)
        self.game_tree.tag_configure("odd", background=SUBTLE)

    def _game_entries(self):
        measured = {}
        for row in (self.store.perf_rows + self.store.game_rows
                    + self.store.game3d_rows):
            scenario = str(row.get("scenario") or "")
            if scenario.startswith("game.") or scenario.startswith("game3d."):
                measured[scenario] = row
        entries = [
            str(entry.get("id"))
            for entry in (self.store.perf_catalog or [])
            if str(entry.get("id") or "").startswith("game.")
            or str(entry.get("id") or "").startswith("game3d.")
        ]
        for scenario in measured:
            if scenario not in entries:
                entries.append(scenario)
        entries.sort(key=lambda scenario: (0 if scenario.startswith("game3d.") else 1, scenario))
        return entries, measured

    def _fill_games(self):
        if not hasattr(self, "game_tree"):
            return
        entries, measured = self._game_entries()
        selected = self.game_tree.selection()
        view = self.game_tree.yview()
        for item in self.game_tree.get_children():
            self.game_tree.delete(item)
        for index, scenario in enumerate(entries):
            match = re.search(r"game(3d)?\.quality-(\d+)x(\d+)-(?:p|c)(\d+)", scenario)
            kind = "3D" if scenario.startswith("game3d.") else "2D"
            resolution = f"{match.group(2)}x{match.group(3)}" if match else "—"
            particles = match.group(4) if match else "—"
            row = measured.get(scenario)
            tags = []
            if index % 2:
                tags.append("odd")
            if row is None:
                tags.insert(0, "pending")
                self.game_tree.insert("", "end", iid=scenario, tags=tuple(tags), values=(
                    kind, scenario, resolution, particles, "pendiente",
                    "—", "—", "—", "—", "—",
                ))
                continue
            nativa = row.get("nativax") or {}
            chrome = row.get("chromium") or {}
            ok = nativa.get("status") == "ok" and chrome.get("status") == "ok"
            nwork = self.store.perf_work(row, "nativax")
            cwork = self.store.perf_work(row, "chromium")
            ratio = nwork / cwork if ok and cwork > 0.0001 else None
            p95 = (nativa.get("frame_ms") or {}).get("p95")
            tags.insert(0, row.get("verdict", ""))
            self.game_tree.insert("", "end", iid=scenario, tags=tuple(tags), values=(
                kind, scenario, resolution, particles, row.get("verdict", ""),
                _num(nwork, 1) if ok else "—",
                _num(cwork, 1) if ok else "—",
                f"{_num(ratio, 2)}x" if ratio is not None else "—",
                _num(p95, 1) if p95 else "—",
                _num(nativa.get("rss_peak_mb"), 0),
            ))
        children = self.game_tree.get_children()
        keep = selected[0] if selected and self.game_tree.exists(selected[0]) else None
        if keep:
            self.game_tree.selection_set(keep)
        elif children:
            self.game_tree.selection_set(children[0])
        if view:
            self.game_tree.yview_moveto(view[0])
        measured_2d = sum(1 for s in measured if s.startswith("game."))
        measured_3d = sum(1 for s in measured if s.startswith("game3d."))
        verdicts = {
            str(row.get("verdict", "")).upper()
            for row in measured.values()
        }
        self.game_summary.configure(
            text=f"2D {measured_2d}/25 · 3D {measured_3d}/25 · "
                 f"{verdicts and ' · '.join(sorted(verdicts)) or 'sin ejecución'}"
        )

    def run_games(self):
        self._start(
            ["dart", "run", "tools/perf/bin/perf.dart", "run",
             "--only", r"^game\.", "--out", str(PERF_GAME_DIR)],
            "juegos Canvas (25 perfiles)",
        )

    def run_games3d(self):
        self._start(
            ["dart", "run", "tools/perf/bin/perf.dart", "run",
             "--only", r"^game3d\.", "--out", str(PERF_GAME3D_DIR)],
            "juegos 3D WebGL (25 perfiles)",
        )

    def run_conformance_test262(self):
        self._start(["dart", "run", "tools/conformance/bin/run_test262.dart"],
                    "conformidad Test262")

    def run_conformance_html5lib(self):
        self._start(["dart", "run", "tools/conformance/bin/run_html5lib.dart"],
                    "conformidad html5lib")

    def run_conformance_url(self):
        self._start(["dart", "run", "tools/conformance/bin/run_url.dart"],
                    "conformidad URL")

    def run_conformance_wpt_dom(self):
        self._start(["dart", "run", "tools/conformance/bin/run_wpt.dart",
                     "--dirs", "dom/nodes"],
                    "conformidad WPT DOM")

    def run_conformance_wpt_css(self):
        self._start(["dart", "run", "tools/conformance/bin/run_wpt.dart",
                     "--dirs", "css/selectors"],
                    "conformidad WPT CSS")

    def run_conformance_wpt_tree(self):
        self._start(["dart", "run", "tools/conformance/bin/run_html_tree.dart"],
                    "conformidad WPT tree")

    def run_conformance_all(self):
        self._start(["dart", "run", "tools/conformance/bin/run_all.dart"],
                    "conformidad completa")

    def run_video_tests(self):
        self._start(
            ["python3", "tools/run_video_contract.py"],
            "contrato de vídeo (25 perfiles)",
        )

    def _build_idle(self):
        tab = self.tab_idle
        self._page_header(tab, "Idle", "La app Flutter Linux real en reposo, sin arnés de test.")
        cards = tk.Frame(tab, bg=BG)
        cards.pack(fill="x", pady=(4, 8))
        self.idle_rss_card, self.idle_rss_value, self.idle_rss_sub = self._card(
            cards, "RSS en reposo", "—", "objetivo ≤ 250 MB"
        )
        self.idle_rss_card.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.idle_cpu_card, self.idle_cpu_value, self.idle_cpu_sub = self._card(
            cards, "CPU en reposo", "—", "objetivo ≤ 1 %"
        )
        self.idle_cpu_card.pack(side="left", fill="both", expand=True, padx=(0, 8))
        self.idle_gpu_card, self.idle_gpu_value, self.idle_gpu_sub = self._card(
            cards, "GPU", "—", "solo si el kernel la expone"
        )
        self.idle_gpu_card.pack(side="left", fill="both", expand=True)
        charts = tk.Frame(tab, bg=PANEL, highlightbackground=BORDER, highlightthickness=1)
        charts.pack(fill="both", expand=True)
        self.idle_timeline = tk.Canvas(charts, bg=PANEL, highlightthickness=0)
        self.idle_timeline.pack(fill="both", expand=True, padx=8, pady=8)
        self.idle_timeline.bind("<Configure>", lambda _e: self._draw_idle())
        self.idle_note = tk.Text(tab, height=4, bg=PANEL, fg=MUTED, relief="flat",
                                 wrap="word", font=(FONT, 9),
                                 padx=10, pady=6)
        self.idle_note.pack(fill="x", pady=(8, 0))

    # ----------------------------------------------------------- containers
    def _build_container(self):
        tab = self.tab_container
        self._page_header(tab, "Contenedores", "Aislamiento Docker con CPU y RAM limitadas.")
        top = tk.Frame(tab, bg=BG)
        top.pack(fill="x", pady=(4, 6))
        tk.Label(top, text="Aislamiento Docker: CPU y RAM por contenedor",
                 bg=BG, fg=FG, font=(FONT, 11, "bold")).pack(side="left")
        tk.Button(top, text="Matriz fija (3 configs)", command=self.run_container_matrix,
                  bg=PANEL2, fg=FG, relief="flat", padx=12, pady=5).pack(side="right")
        self.container_note = tk.Label(
            top, text="RSS = PSS del proceso de test (incluye flutter test)",
            bg=BG, fg=MUTED, font=(FONT, 9)
        )
        self.container_note.pack(side="right", padx=10)

        controls = tk.Frame(tab, bg=PANEL, padx=10, pady=8,
                            highlightbackground=BORDER, highlightthickness=1)
        controls.pack(fill="x", pady=(2, 8))
        tk.Label(controls, text="CPU", bg=PANEL, fg=MUTED,
                 font=(FONT, 9, "bold")).pack(side="left")
        self.container_cpus = ttk.Combobox(
            controls, values=["0.25", "0.5", "1", "1.5", "2", "3", "4"],
            width=5, state="readonly",
        )
        self.container_cpus.set("1")
        self.container_cpus.pack(side="left", padx=(4, 12))
        tk.Label(controls, text="RAM", bg=PANEL, fg=MUTED,
                 font=(FONT, 9, "bold")).pack(side="left")
        self.container_memory = ttk.Combobox(
            controls, values=["512m", "768m", "1g", "1.5g", "2g", "4g"],
            width=6, state="readonly",
        )
        self.container_memory.set("1g")
        self.container_memory.pack(side="left", padx=(4, 12))
        tk.Label(controls, text="Nombre", bg=PANEL, fg=MUTED,
                 font=(FONT, 9, "bold")).pack(side="left")
        self.container_name = tk.Entry(controls, bg=PANEL2, fg=FG,
                                       insertbackground=FG, relief="flat",
                                       width=14)
        self.container_name.insert(0, "custom")
        self.container_name.pack(side="left", padx=(4, 12))
        tk.Label(controls, text="Tests", bg=PANEL, fg=MUTED,
                 font=(FONT, 9, "bold")).pack(side="left")
        self.container_only = tk.Entry(controls, bg=PANEL2, fg=FG,
                                       insertbackground=FG, relief="flat",
                                       width=30)
        self.container_only.insert(0, "js.arrays|dom.rows-create-1k|scroll.2d-tiles")
        self.container_only.pack(side="left", padx=(4, 12), fill="x", expand=True)
        tk.Button(controls, text="▶ Ejecutar contenedor", command=self.run_container_custom,
                  bg=ACCENT, fg="#07101f", relief="flat", padx=12, pady=5,
                  font=(FONT, 9, "bold")).pack(side="left", padx=(0, 6))
        tk.Button(controls, text="Preparar imagen", command=self.build_container_image,
                  bg=PANEL2, fg=FG, relief="flat", padx=10, pady=5).pack(side="left")

        panes = tk.PanedWindow(tab, orient="horizontal", bg=BG, sashwidth=6)
        panes.pack(fill="both", expand=True)
        left = tk.Frame(panes, bg=BG)
        panes.add(left, stretch="always")
        columns = ("config", "scenario", "verdict", "nativa", "chrome", "ratio",
                   "p95", "rss", "ram")
        self.container_tree = ttk.Treeview(left, columns=columns, show="headings",
                                           selectmode="browse")
        for column, label, width, anchor in [
            ("config", "Configuración", 104, "w"),
            ("scenario", "Escenario", 160, "w"),
            ("verdict", "Veredicto", 64, "w"),
            ("nativa", "NativaX", 70, "e"),
            ("chrome", "Chromium", 76, "e"),
            ("ratio", "Ratio", 50, "e"),
            ("p95", "p95", 52, "e"),
            ("rss", "RSS arnés", 86, "e"),
            ("ram", "RAM Docker", 74, "e"),
        ]:
            self.container_tree.heading(column, text=label)
            self.container_tree.column(column, width=width, anchor=anchor)
        scroll = ttk.Scrollbar(left, orient="vertical", command=self.container_tree.yview)
        self.container_tree.configure(yscrollcommand=scroll.set)
        self.container_tree.pack(side="left", fill="both", expand=True)
        scroll.pack(side="left", fill="y")
        self.container_tree.bind("<<TreeviewSelect>>", self._on_container_select)
        for verdict, color in VERDICT_COLORS.items():
            self.container_tree.tag_configure(verdict, foreground=color)
        self.container_tree.tag_configure("odd", background=SUBTLE)

        right = tk.Frame(panes, bg=PANEL, width=480)
        panes.add(right, stretch="never")
        right.pack_propagate(False)
        self.container_detail = tk.Text(right, height=10, bg=PANEL, fg=FG,
                                        relief="flat", wrap="word", padx=10, pady=8,
                                        font=(MONO, 9))
        self.container_detail.pack(fill="x")
        self.container_chart = tk.Canvas(right, bg=PANEL, height=260,
                                         highlightthickness=0)
        self.container_chart.pack(fill="x", padx=8, pady=(10, 8))
        self.container_chart.bind("<Configure>", lambda _e: self._draw_container())

    def _fill_container(self):
        if not hasattr(self, "container_tree"):
            return
        selected = self.container_tree.selection()
        view = self.container_tree.yview()
        for item in self.container_tree.get_children():
            self.container_tree.delete(item)
        if not self.store.matrix:
            self.container_note.configure(text="sin matriz; ejecuta la matriz Docker")
            return
        configs = self.store.matrix_configs
        scenarios = self.store.matrix_scenarios
        app = self.store.app_idle or {}
        idle = ""
        if app.get("status") == "ok":
            idle = (f" · app idle {app.get('rss_tail_mb', 0):.0f} MB / "
                    f"{app.get('cpu_tail_pct', 0):.2f} % CPU")
        self.container_note.configure(
            text=f"{len(configs)} configuraciones · {len(scenarios)} escenarios · Docker"
                 f" · RSS = PSS del arnés (incluye flutter test){idle}"
        )
        for config in configs:
            for scenario in scenarios:
                row = self.store.matrix_row(config.get("id"), scenario)
                if not row:
                    continue
                ratio = row.get("ratio")
                index = len(self.container_tree.get_children())
                tags = (row.get("verdict", ""),)
                if index % 2:
                    tags = tags + ("odd",)
                self.container_tree.insert("", "end",
                    iid=f"{config.get('id')}|{scenario}",
                    tags=tags,
                    values=(
                        config.get("label", config.get("id")),
                        scenario,
                        row.get("verdict", ""),
                        _num(row.get("nativa_ms"), 1),
                        _num(row.get("chrome_ms"), 1),
                        f"{_num(ratio, 2)}x" if ratio else "—",
                        _num(row.get("frame_p95"), 1),
                        _num(row.get("rss_peak_mb"), 0),
                        _ram_label(config),
                    ))
        children = self.container_tree.get_children()
        keep = selected[0] if selected and self.container_tree.exists(selected[0]) else None
        if keep:
            self.container_tree.selection_set(keep)
        elif children:
            self.container_tree.selection_set(children[0])
        if view:
            self.container_tree.yview_moveto(view[0])
        self._on_container_select()

    def _on_container_select(self, _event=None):
        selection = self.container_tree.selection()
        if not selection:
            return
        config_id, _, scenario = selection[0].partition("|")
        row = self.store.matrix_row(config_id, scenario)
        config = next((c for c in self.store.matrix_configs if c.get("id") == config_id), {})
        lines = [
            f"{scenario}",
            f"{config.get('label', config_id)} · Docker CPU {config.get('cpus')} · RAM {config.get('memory')}",
            "",
            f"Veredicto: {row.get('verdict') if row else '—'}",
        ]
        if row:
            lines += [
                f"NativaX: {_num(row.get('nativa_ms'), 1)} ms",
                f"Chromium: {_num(row.get('chrome_ms'), 1)} ms",
                f"Ratio: {_num(row.get('ratio'), 2)}x",
                f"Nodos: {row.get('nodes_nativa')} / {row.get('nodes_chrome')}",
                f"Frame p95/max: {_num(row.get('frame_p95'), 1)} / {_num(row.get('frame_max'), 1)} ms",
                f"RSS arnés: {_num(row.get('rss_peak_mb'), 0)} MB / "
                f"límite {_ram_label(config)} (incluye flutter test)",
            ]
            for reason in row.get("reasons") or []:
                lines.append(f"· {reason}")
        self.container_detail.configure(state="normal")
        self.container_detail.delete("1.0", "end")
        self.container_detail.insert("1.0", "\n".join(lines))
        self.container_detail.configure(state="disabled")
        self._draw_container()

    def _draw_container(self):
        if not hasattr(self, "container_chart"):
            return
        selection = self.container_tree.selection() if hasattr(self, "container_tree") else ()
        scenario = selection[0].partition("|")[2] if selection else (
            (self.store.matrix_scenarios or ["—"])[0]
        )
        configs = self.store.matrix_configs
        items = []
        for config in configs:
            row = self.store.matrix_row(config.get("id"), scenario)
            if not row:
                continue
            value = row.get("nativa_ms") or 0
            items.append((config.get("label", config.get("id")), value,
                          GREEN if row.get("verdict") == "PASS" else YELLOW))
        self.chart_bar(self.container_chart,
                       f"NativaX en «{scenario}» por contenedor (ms)",
                       items, max_value=None, unit=" ms")

    def run_container_custom(self):
        cpus = self.container_cpus.get().strip() or "1"
        memory = self.container_memory.get().strip() or "1g"
        name = self.container_name.get().strip() or f"custom-{cpus}-{memory}"
        only = self.container_only.get().strip() or "js.arrays|dom.rows-create-1k|scroll.2d-tiles"
        self._start([
            "tools/perf/container/run.sh",
            "--cpus", cpus,
            "--memory", memory,
            "--name", name,
            "--only", only,
        ], f"contenedor {name} ({cpus} CPU, {memory})")

    def build_container_image(self):
        self._start([
            "docker", "build", "-t", "nativa-perf:local",
            str(ROOT / "tools" / "perf" / "container"),
        ], "construir imagen nativa-perf:local")

    def run_container_matrix(self):
        self._start(["tools/perf/container/matrix.sh"], "matriz Docker")

    # -------------------------------------------------------------- reports
    def _build_reports(self):
        tab = self.tab_reports
        self._page_header(tab, "Informes", "Informe HTML real renderizado dentro del panel.")
        top = tk.Frame(tab, bg=BG)
        top.pack(fill="x", pady=(4, 6))
        tk.Label(top, text="Informe", bg=BG, fg=FG,
                 font=(FONT, 11, "bold")).pack(side="left")
        self.report_choice = ttk.Combobox(
            top,
            values=["En vivo", "Recomendaciones", "Conformidad",
                    "Histórico consolidado", "Histórico visual",
                    "Histórico rendimiento", "Histórico quality gate"],
            state="readonly",
            width=24,
        )
        self.report_choice.current(0)
        self.report_choice.pack(side="left", padx=8)
        self.report_choice.bind("<<ComboboxSelected>>", lambda _e: self._load_report())
        tk.Button(top, text="Abrir carpeta", command=self.open_folder,
                  bg=PANEL2, fg=FG, relief="flat", padx=10, pady=4).pack(side="right")
        tk.Button(top, text="Recargar", command=self._load_report,
                  bg=PANEL2, fg=FG, relief="flat", padx=10, pady=4).pack(side="right", padx=6)
        self.report_view = MarkdownView(tab)
        self.report_view.pack(fill="both", expand=True)

    # ---------------------------------------------------------------- data
    def reload(self):
        self.store.load()
        self._fill_summary()
        self._fill_perf_table()
        self.conformance = self._load_conformance()
        self._fill_visual_table()
        self._fill_conformance()
        self._fill_video()
        self._fill_games()
        self._fill_idle()
        self._fill_container()
        if hasattr(self, "report_choice"):
            if self.report_choice.get() == "En vivo":
                self._write_live_report()
            elif self.report_choice.get() == "Recomendaciones":
                self._write_recommendations_report()
            elif self.report_choice.get() == "Conformidad":
                self._write_conformance_report()
        self._load_report()
        self._draw_summary()
        self._draw_perf_charts()
        self._draw_visual_charts()
        self._draw_idle()
        self._draw_container()
        self._update_header()
        self._last_data_sig = self._data_signature()

    def _refresh_data(self):
        self.store.load()
        self._fill_summary()
        self._fill_perf_table()
        self.conformance = self._load_conformance()
        self._fill_visual_table()
        self._fill_conformance()
        self._fill_video()
        self._fill_games()
        self._fill_idle()
        self._fill_container()
        self._draw_summary()
        self._draw_perf_charts()
        self._draw_visual_charts()
        self._draw_idle()
        self._draw_container()
        if hasattr(self, "report_choice") and self.report_choice.get() in (
            "En vivo", "Recomendaciones"
        ):
            if self.report_choice.get() == "En vivo":
                self._write_live_report()
                path = LIVE_REPORT
            elif self.report_choice.get() == "Recomendaciones":
                self._write_recommendations_report()
                path = RECOMMENDATIONS_REPORT
            else:
                self._write_conformance_report()
                path = CONFORMANCE_REPORT
            try:
                self._report_sig = path.stat().st_mtime_ns
            except OSError:
                self._report_sig = None
            if self.active_page == "reports":
                try:
                    self.report_view.render(path.read_text(), path.parent)
                except OSError:
                    pass
                if self.process is None:
                    if self._live_report_timer is not None:
                        try:
                            self.root.after_cancel(self._live_report_timer)
                        except tk.TclError:
                            pass
                    # Debounce the expensive HTML/PNG capture until updates
                    # stop arriving (external runs can write every page).
                    self._live_report_timer = self.root.after(
                        1800, self._load_report
                    )
        self._update_header()

    def _update_header(self):
        if self.store.loaded_at:
            catalog = len(self.store.catalog or [])
            pages = (f"{len(self.store.visual_rows)}/{catalog} páginas"
                     if catalog else f"{len(self.store.visual_rows)} páginas")
            perf_catalog = len(self.store.perf_catalog or [])
            scenarios = (f"{len(self.store.perf_rows)}/{perf_catalog} escenarios"
                         if perf_catalog else
                         f"{len(self.store.perf_rows)} escenarios")
            self.header_status.configure(
                text=f"{pages} · {scenarios} · "
                     f"{self.store.loaded_at.strftime('%H:%M:%S')}"
            )

    def _fill_summary(self):
        visual = self.store.visual_summary()
        perf = self.store.perf_summary()
        pages_total = len(self.store.catalog or []) or visual["total"]
        categories = self.store.visual_categories()
        pixels = self.store.visual_pixels()
        self.card_visual_value.configure(text=f"{categories['Fidelidad']:.1f} %")
        self.card_visual_sub.configure(
            text=f"{visual['total']} medidas de {pages_total} · "
                 f"{visual['PASS']} PASS · {visual['FAIL']} FAIL"
        )
        if perf["total"]:
            self.card_perf_value.configure(text=f"{perf['PASS']} / {perf['total']} PASS")
            perf_total = len(self.store.perf_catalog or []) or perf["total"]
            self.card_perf_sub.configure(
                text=f"{perf['total']} de {perf_total} medidos · "
                     f"{perf['WARN']} WARN · {perf['FAIL']} FAIL"
            )
        else:
            self.card_perf_value.configure(text="—")
            self.card_perf_sub.configure(text="sin ejecución")
        app = self.store.app_idle
        if app and app.get("status") == "ok":
            self.card_idle_value.configure(text=f"{app['rss_tail_mb']:.0f} MB")
            self.card_idle_sub.configure(
                text=f"{app['cpu_tail_pct']:.2f} % CPU · objetivo 250 MB / 1 %"
            )
        else:
            self.card_idle_value.configure(text="—")
            self.card_idle_sub.configure(text="mide con «Idle app»")
        self.card_pixels_value.configure(text=f"{pixels['mean_ink']:.1f} %")
        self.card_pixels_sub.configure(
            text=f"{pixels['mismatched']:,} px ΔE>2 de {pixels['pixels']:,}"
        )
        self._update_worst_lists()
        app = self.store.app_idle or {}
        idle = ""
        if app.get("status") == "ok":
            idle = (f"\nidle {app.get('rss_tail_mb', 0):.0f} MB · "
                    f"{app.get('cpu_tail_pct', 0):.2f} % CPU")
        perf_total = len(self.store.perf_catalog or []) or perf["total"]
        self.sidebar_status.configure(
            text=f"{visual['total']}/{pages_total} páginas medidas\n"
                 f"{perf['total']}/{perf_total} escenarios{idle}"
        )

    def _update_worst_lists(self):
        pages = sorted(self.store.visual_rows, key=lambda r: r.get("overall") or 0)
        lines = ["Peores páginas por fidelidad:"]
        for row in pages[:5]:
            lines.append(
                f"{row.get('page', '')[:42]:42} {_num(row.get('overall'), 1):>5} %  "
                f"{row.get('verdict', '')}"
            )
        self.summary_worst_pages.configure(state="normal")
        self.summary_worst_pages.delete("1.0", "end")
        self.summary_worst_pages.insert("1.0", "\n".join(lines))
        self.summary_worst_pages.configure(state="disabled")

        scenarios = sorted(
            [
                row for row in self.store.perf_rows
                if row.get("kind") != "scroll"
                and (row.get("nativax") or {}).get("status") == "ok"
                and (row.get("chromium") or {}).get("status") == "ok"
                and self.store.perf_work(row, "chromium") > 0
            ],
            key=lambda r: self.store.perf_work(r, "nativax") / self.store.perf_work(r, "chromium"),
            reverse=True,
        )
        lines = ["Peores escenarios por ratio de trabajo:"]
        for row in scenarios[:5]:
            n = self.store.perf_work(row, "nativax")
            c = self.store.perf_work(row, "chromium")
            ratio = f"{n / c:.2f}x" if c > 0 and (row.get("nativax") or {}).get("status") == "ok" and (row.get("chromium") or {}).get("status") == "ok" else "—"
            lines.append(f"{row.get('scenario', '')[:40]:40} {ratio:>8}  {row.get('verdict', '')}")
        self.summary_worst_scenarios.configure(state="normal")
        self.summary_worst_scenarios.delete("1.0", "end")
        self.summary_worst_scenarios.insert("1.0", "\n".join(lines))
        self.summary_worst_scenarios.configure(state="disabled")

    def _fill_perf_table(self):
        query = self.perf_filter.get().lower() if hasattr(self, "perf_filter") else ""
        selected = self.perf_tree.selection()
        view = self.perf_tree.yview()
        for item in self.perf_tree.get_children():
            self.perf_tree.delete(item)
        measured = {row.get("scenario"): row for row in self.store.perf_rows}
        entries = []
        if self.store.perf_catalog:
            entries = [entry.get("id") for entry in self.store.perf_catalog]
            for scenario_id in measured:
                if scenario_id not in entries:
                    entries.append(scenario_id)
        else:
            entries = list(measured.keys())
        catalog = {
            entry.get("id"): entry for entry in (self.store.perf_catalog or [])
        }
        for index, scenario_id in enumerate(entries):
            if query and query not in (scenario_id or "").lower():
                continue
            row = measured.get(scenario_id)
            tags = []
            if index % 2:
                tags.append("odd")
            if row is None:
                tags.insert(0, "pending")
                self.perf_tree.insert("", "end", iid=scenario_id, tags=tuple(tags), values=(
                    scenario_id,
                    "pendiente",
                    "—",
                    "—",
                    "—",
                    "—",
                    "—",
                    "—",
                ))
                continue
            nativa = row.get("nativax") or {}
            chrome = row.get("chromium") or {}
            ok = nativa.get("status") == "ok" and chrome.get("status") == "ok"
            nwork = self.store.perf_work(row, "nativax")
            cwork = self.store.perf_work(row, "chromium")
            ratio = nwork / cwork if ok and cwork > 0.0001 else None
            p95 = (nativa.get("frame_ms") or {}).get("p95")
            tags.insert(0, row.get("verdict", ""))
            self.perf_tree.insert("", "end", iid=scenario_id, tags=tuple(tags), values=(
                scenario_id,
                row.get("verdict", ""),
                _num(nwork, 1) if ok else "—",
                _num(cwork, 1) if ok else "—",
                f"{_num(ratio, 2)}x" if ratio is not None else "—",
                f"{nativa.get('nodes', '—') if ok else '—'}/{chrome.get('nodes', '—') if ok else '—'}",
                _num(p95, 1) if p95 else "—",
                _num(nativa.get("rss_peak_mb"), 0),
            ))
        children = self.perf_tree.get_children()
        keep = selected[0] if selected and self.perf_tree.exists(selected[0]) else None
        if keep:
            self.perf_tree.selection_set(keep)
        elif children:
            self.perf_tree.selection_set(children[0])
        if view:
            self.perf_tree.yview_moveto(view[0])
        if hasattr(self, "perf_summary"):
            self.perf_summary.configure(
                text=f"{len(measured)}/{len(entries)} medidos"
            )
        self._on_perf_select()

    def _fill_visual_table(self):
        query = self.visual_filter.get().lower() if hasattr(self, "visual_filter") else ""
        selected = self.visual_tree.selection()
        view = self.visual_tree.yview()
        for item in self.visual_tree.get_children():
            self.visual_tree.delete(item)
        measured = {row.get("page"): row for row in self.store.visual_rows}
        entries = []
        if self.store.catalog:
            entries = [entry.get("id") for entry in self.store.catalog]
            for page_id in measured:
                if page_id not in entries:
                    entries.append(page_id)
        else:
            entries = list(measured.keys())
        for index, page_id in enumerate(entries):
            if query and query not in (page_id or "").lower():
                continue
            row = measured.get(page_id)
            if row:
                tags = (row.get("verdict", ""),)
                if index % 2:
                    tags = tags + ("odd",)
                self.visual_tree.insert("", "end", iid=page_id,
                    tags=tags, values=(
                        page_id,
                        row.get("verdict", ""),
                        _num(row.get("overall"), 1),
                        _num(row.get("position"), 1),
                        _num(row.get("layout"), 1),
                        _num(row.get("color"), 1),
                        _num(row.get("design"), 1),
                    ))
            else:
                tags = ("pending",)
                if index % 2:
                    tags = tags + ("odd",)
                self.visual_tree.insert("", "end", iid=page_id, tags=tags, values=(
                    page_id, "pendiente", "—", "—", "—", "—", "—",
                ))
        total = len(entries)
        done = sum(1 for entry in entries if entry in measured)
        self.visual_summary.configure(text=f"{done}/{total} medidas")
        children = self.visual_tree.get_children()
        keep = selected[0] if selected and self.visual_tree.exists(selected[0]) else None
        if keep:
            self.visual_tree.selection_set(keep)
        elif children:
            self.visual_tree.selection_set(children[0])
        if view:
            self.visual_tree.yview_moveto(view[0])
        self._on_visual_select()

    def _selected_row(self, tree, rows, key):
        selection = tree.selection()
        if not selection:
            return None
        for row in rows:
            if row.get(key) == selection[0]:
                return row
        return None

    def _on_perf_select(self, _event=None):
        self.selected_perf = self._selected_row(self.perf_tree, self.store.perf_rows, "scenario")
        self.selected_perf_pending = None
        if self.selected_perf is None:
            selection = self.perf_tree.selection()
            scenario_id = selection[0] if selection else None
            if scenario_id:
                self.selected_perf_pending = next(
                    (entry for entry in (self.store.perf_catalog or [])
                     if entry.get("id") == scenario_id),
                    None,
                )
        self._draw_perf_detail()
        self._draw_perf_charts()

    def _on_visual_select(self, _event=None):
        selection = self.visual_tree.selection()
        page_id = selection[0] if selection else None
        self.selected_visual = None
        for row in self.store.visual_rows:
            if row.get("page") == page_id:
                self.selected_visual = row
                break
        if self.selected_visual is None and page_id:
            entry = next(
                (e for e in (self.store.catalog or []) if e.get("id") == page_id),
                None,
            )
            if entry:
                lines = [
                    page_id,
                    f"Suite: {entry.get('suite', '—')}",
                    "Estado: pendiente de medir",
                    "",
                    f"HTML: {entry.get('entry', '—')}",
                    f"Directorio: {entry.get('directory', '—')}",
                    "",
                    "Pulsa «Visual 300» para ejecutar esta página y las demás.",
                ]
                self.visual_detail.configure(state="normal")
                self.visual_detail.delete("1.0", "end")
                self.visual_detail.insert("1.0", "\n".join(lines))
                self.visual_detail.configure(state="disabled")
            self._draw_visual_charts()
            self._load_thumbnails()
            return
        self._draw_visual_detail()
        self._draw_visual_charts()
        self._load_thumbnails()

    # ------------------------------------------------------------- drawings
    def _draw_summary(self):
        categories = self.store.visual_categories()
        items = []
        for name, value in categories.items():
            color = GREEN if value >= 90 else (YELLOW if value >= 70 else RED)
            items.append((name, value, color))
        self.chart_bar(
            self.summary_categories,
            "Fidelidad media por categoría (51 páginas)",
            items,
            target=90,
            max_value=100,
            unit=" %",
        )
        self.chart_donut(
            self.summary_donut_visual,
            "Fidelidad visual",
            {
                name: self.store.visual_summary()[name]
                for name in ("PASS", "WARN", "FAIL", "INVALID")
            },
        )
        self.chart_donut(
            self.summary_donut_perf,
            "Rendimiento",
            {
                name: self.store.perf_summary()[name]
                for name in ("PASS", "WARN", "FAIL", "INVALID")
            },
        )

    def _draw_perf_detail(self):
        row = self.selected_perf
        if not row:
            entry = self.selected_perf_pending
            if entry:
                lines = [
                    f"{entry.get('id', '')}  ·  pendiente",
                    entry.get("title", ""),
                    f"Tipo: {entry.get('kind', '—')}",
                    f"Fuente: {entry.get('source', '—')}",
                    "",
                    entry.get("description", ""),
                    "",
                    "Pulsa «Solo rendimiento» para ejecutar los 100 escenarios.",
                ]
                self.perf_detail.configure(state="normal")
                self.perf_detail.delete("1.0", "end")
                self.perf_detail.insert("1.0", "\n".join(lines))
                self.perf_detail.configure(state="disabled")
            else:
                self.perf_detail.configure(state="normal")
                self.perf_detail.delete("1.0", "end")
                self.perf_detail.insert("1.0", "Selecciona un escenario.")
                self.perf_detail.configure(state="disabled")
            return
        nativa = row.get("nativax") or {}
        chrome = row.get("chromium") or {}
        lines = [
            f"{row.get('scenario')}  ·  {row.get('verdict')}",
            f"{row.get('title', '')}",
            f"Fuente: {row.get('source', '')}",
            "",
            f"NativaX: {_num(self.store.perf_work(row, 'nativax'), 1)} ms "
            f"({_num(nativa.get('scenario_ms'), 1)} js + {_num(nativa.get('render_ms'), 1)} frame)",
            f"Chromium: {_num(self.store.perf_work(row, 'chromium'), 1)} ms "
            f"({_num(chrome.get('scenario_ms'), 1)} js + {_num(chrome.get('render_ms'), 1)} layout/style)",
            f"Nodos: {nativa.get('nodes')} / {chrome.get('nodes')}",
            f"Frame p95/max: {_num((nativa.get('frame_ms') or {}).get('p95'), 1)} / "
            f"{_num((nativa.get('frame_ms') or {}).get('max'), 1)} ms",
            f"Heap: {_num(chrome.get('heap_mb'), 2)} MB (solo Chromium)",
            f"RSS: {_num(nativa.get('rss_peak_mb'), 0)} MB · CPU "
            f"{_num(nativa.get('cpu_peak_pct'), 1)} %",
        ]
        reasons = row.get("reasons") or []
        if reasons:
            lines.append("")
            lines.append("Motivos:")
            lines.extend(f"· {reason}" for reason in reasons)
        ops = (nativa.get("extra") or {}).get("ops") or []
        if ops:
            lines.append("")
            lines.append("Operaciones:")
            for op in ops[:6]:
                if "error" in op:
                    lines.append(f"· {op.get('name')}: error")
                else:
                    lines.append(
                        f"· {op.get('name')}: js {_num(op.get('eval_ms'), 1)} ms · "
                        f"frame {_num(op.get('pump_ms'), 1)} ms"
                    )
        read = (nativa.get("extra") or {}).get("read")
        if read:
            lines.append("")
            lines.append("Resultado de la página:")
            lines.append(json.dumps(read, indent=2)[:1200])
        self.perf_detail.configure(state="normal")
        self.perf_detail.delete("1.0", "end")
        self.perf_detail.insert("1.0", "\n".join(lines))
        self.perf_detail.configure(state="disabled")

    def _draw_perf_charts(self):
        rows = sorted(
            self.store.perf_rows,
            key=lambda r: self.store.perf_work(r, "nativax"),
            reverse=True,
        )[:10]
        labels = [row.get("scenario", "") for row in rows]
        chart = self.perf_work_chart
        # Grouped bars for the ten slowest scenarios on a log axis; the table
        # still lists every scenario.
        if labels:
            self.chart_grouped(
                chart,
                "Trabajo de los 10 escenarios más lentos (ms, log)",
                labels,
                [
                    ("NativaX", [self.store.perf_work(r, "nativax") for r in rows], ACCENT),
                    ("Chromium", [self.store.perf_work(r, "chromium") for r in rows], GREEN),
                ],
            )
        else:
            self.chart_grouped(chart, "Trabajo por escenario", [], [])
        row = self.selected_perf
        if not row:
            self.chart_timeline(self.perf_timeline, "RSS del escenario", [])
            return
        nativa = row.get("nativax") or {}
        chrome = row.get("chromium") or {}
        series = []
        for name, data, color in (("NativaX", nativa, ACCENT), ("Chromium", chrome, GREEN)):
            samples = data.get("samples") or []
            points = [(s.get("elapsed_ms", 0), s.get("rss_mb", 0)) for s in samples if s.get("rss_mb")]
            if points:
                series.append((name, points, color))
        self.chart_timeline(
            self.perf_timeline,
            f"RSS durante «{row.get('scenario')}»",
            series,
        )

    def _visual_report(self, row):
        if not row:
            return None
        path = Path(row.get("artifacts", "")) / "report.json"
        key = str(path)
        if key not in self.visual_report_cache:
            self.visual_report_cache[key] = _load_json(path)
        return self.visual_report_cache[key]

    def _draw_visual_detail(self):
        row = self.selected_visual
        if not row:
            self.visual_detail.configure(state="normal")
            self.visual_detail.delete("1.0", "end")
            self.visual_detail.insert("1.0", "Selecciona una página.")
            self.visual_detail.configure(state="disabled")
            return
        report = self._visual_report(row) or {}
        lines = [
            f"{row.get('page')}  ·  {row.get('verdict')}",
            f"Overall {_num(row.get('overall'), 1)} % · Posición {_num(row.get('position'), 1)} % · "
            f"Layout {_num(row.get('layout'), 1)} % · Color {_num(row.get('color'), 1)} % · "
            f"Diseño {_num(row.get('design'), 1)} %",
            f"Píxeles: {_num(row.get('mismatched_pct'), 2)} % ΔE>2 · "
            f"tinta {_num(row.get('ink_mismatch_pct'), 2)} % · ΔE medio "
            f"{_num(row.get('mean_delta_e'), 2)}",
            f"Nodos: {row.get('matched')} emparejados · {row.get('missing')} faltan · "
            f"{row.get('extra')} sobran",
        ]
        geometry = report.get("geometry") or {}
        roots = geometry.get("rootCauses") or []
        if roots:
            lines.append("")
            lines.append("Peores causas de posición/layout:")
            for delta in roots[:4]:
                lines.append(
                    f"· {delta.get('path', '')[:60]}  Δpos {_num(delta.get('positionDelta'), 1)}"
                    f"  Δsize {_num(delta.get('sizeDelta'), 1)}"
                )
        colors = ((report.get("colors") or {}).get("failures") or [])
        if colors:
            lines.append("")
            lines.append("Peores colores:")
            for item in colors[:3]:
                lines.append(
                    f"· {item.get('path', '')[:55]}  ΔE {_num(item.get('meanDeltaE'), 1)}"
                )
        designs = report.get("designFailures") or []
        if designs:
            lines.append("")
            lines.append("Peores estilos:")
            for item in designs[:3]:
                props = ", ".join(
                    f"{m.get('property')} {m.get('chrome')}→{m.get('nativa')}"
                    for m in (item.get("mismatches") or [])[:3]
                )
                lines.append(f"· {item.get('path', '')[:45]}  {props}")
        self.visual_detail.configure(state="normal")
        self.visual_detail.delete("1.0", "end")
        self.visual_detail.insert("1.0", "\n".join(lines))
        self.visual_detail.configure(state="disabled")

    def _draw_visual_charts(self):
        row = self.selected_visual
        if not row:
            self.chart_bar(self.visual_categories, "Categorías", [])
            self.chart_bar(self.visual_pixels, "Píxeles", [])
            return
        self.chart_bar(
            self.visual_categories,
            f"Categorías · {row.get('page')}",
            [
                ("Posición", row.get("position") or 0,
                 GREEN if (row.get("position") or 0) >= 90 else YELLOW),
                ("Layout", row.get("layout") or 0,
                 GREEN if (row.get("layout") or 0) >= 90 else YELLOW),
                ("Color" if row.get("color") is not None else "Color (n/d)",
                 row.get("color") or 0,
                 GREEN if (row.get("color") or 0) >= 90 else YELLOW),
                ("Diseño", row.get("design") or 0,
                 GREEN if (row.get("design") or 0) >= 90 else YELLOW),
                ("Overall", row.get("overall") or 0,
                 GREEN if (row.get("overall") or 0) >= 90 else YELLOW),
            ],
            target=90,
            max_value=100,
            unit=" %",
        )
        pixel_pct = row.get("mismatched_pct") or 0
        ink_pct = row.get("ink_mismatch_pct") or 0
        delta = row.get("mean_delta_e") or 0
        self.chart_bar(
            self.visual_pixels,
            "Píxeles y color",
            [
                ("Píxeles distintos %", pixel_pct, RED if pixel_pct > 5 else YELLOW),
                ("Tinta distinta %", ink_pct, RED if ink_pct > 50 else YELLOW),
                ("ΔE medio (0-100)", delta, RED if delta > 10 else YELLOW),
            ],
            max_value=100,
            unit="",
        )

    def _load_thumbnails(self):
        for label in self.thumb_labels:
            label.configure(image="", text="sin captura")
        self.thumb_refs = []
        row = self.selected_visual
        if not row:
            return
        for label, key in zip(self.thumb_labels, ("chrome_png", "nativax_png", "diff_png")):
            path = row.get(key)
            if not path or not Path(path).exists():
                continue
            try:
                if Image is not None and ImageTk is not None:
                    image = Image.open(path).convert("RGB")
                    image.thumbnail((240, 240))
                    photo = ImageTk.PhotoImage(image)
                else:
                    # Tk 8.6 can read PNG natively; subsample keeps it small.
                    source = tk.PhotoImage(file=path)
                    factor = max(1, math.ceil(max(source.width() / 240, source.height() / 240)))
                    photo = source.subsample(factor, factor)
                self.thumb_refs.append(photo)
                label.configure(image=photo, text="")
            except Exception as error:
                label.configure(text=f"no se pudo cargar: {error}")

    def _fill_idle(self):
        app = self.store.app_idle
        if not app or app.get("status") != "ok":
            self.idle_rss_value.configure(text="—")
            self.idle_cpu_value.configure(text="—")
            self.idle_gpu_value.configure(text="—")
            self.idle_note.delete("1.0", "end")
            self.idle_note.insert(
                "1.0",
                "Sin medición. Pulsa «Idle app» para abrir la app Linux en una "
                "página blanca y medir RSS/CPU reales (el arnés flutter test no "
                "cuenta para el objetivo de 250 MB).",
            )
            return
        rss = app.get("rss_tail_mb") or 0
        cpu = app.get("cpu_tail_pct") or 0
        gpu = app.get("gpu_busy_pct")
        self.idle_rss_value.configure(text=f"{rss:.1f} MB")
        self.idle_cpu_value.configure(text=f"{cpu:.2f} %")
        self.idle_gpu_value.configure(text="—" if gpu is None else f"{gpu:.1f} %")
        rss_color = GREEN if rss <= 250 else RED
        cpu_color = GREEN if cpu <= 1 else RED
        self.idle_rss_value.configure(fg=rss_color)
        self.idle_cpu_value.configure(fg=cpu_color)
        self.idle_rss_sub.configure(text="objetivo ≤ 250 MB · " + ("OK" if rss <= 250 else "FUERA"))
        self.idle_cpu_sub.configure(text="objetivo ≤ 1 % · " + ("OK" if cpu <= 1 else "FUERA"))
        self.idle_gpu_sub.configure(
            text="no expuesta por el kernel" if gpu is None else "lectura /sys/class/drm"
        )
        self.idle_note.delete("1.0", "end")
        self.idle_note.insert(
            "1.0",
            "Medición del proceso real de la app Flutter Linux con una página "
            "blanca: 3 s de calentamiento + 5 s de reposo. PSS/CPU vía /proc. "
            "El idle.blank del arnés no decide este objetivo.",
        )

    def _draw_idle(self):
        app = self.store.app_idle
        series = []
        if app and app.get("status") == "ok":
            samples = app.get("samples") or []
            points = [(s.get("elapsed_ms", 0), s.get("rss_mb", 0)) for s in samples if s.get("rss_mb")]
            if points:
                series.append(("RSS app", points, ACCENT))
        self.chart_timeline(self.idle_timeline, "RSS de la app durante el idle (MB)", series)

    def _report_path(self):
        choice = self.report_choice.get() if hasattr(self, "report_choice") else "En vivo"
        return {
            "En vivo": LIVE_REPORT,
            "Recomendaciones": RECOMMENDATIONS_REPORT,
            "Conformidad": CONFORMANCE_REPORT,
            "Histórico consolidado": CONSOLIDATED,
            "Histórico visual": ROOT / "progress" / "reports" / "visual-50projects50days-latest.md",
            "Histórico rendimiento": ROOT / "progress" / "reports" / "perf-latest.md",
            "Histórico quality gate": ROOT / "progress" / "reports" / "quality-gate-latest.md",
        }.get(choice, LIVE_REPORT)

    def _recommendation_data(self):
        return {
            "visual": self.store.visual,
            "perf": self.store.perf,
            "app_idle": self.store.app_idle,
            "matrix": self.store.matrix,
            "perf_catalog": self.store.perf_catalog,
            "visual_catalog": self.store.catalog,
            "leaks": self.leak_run,
            "security": self.security_run,
            "capabilities": {"video": False, "game_player": False},
        }

    def _refresh_auxiliary_runs(self):
        if recommendation_engine is None:
            return
        self.leak_run = recommendation_engine.load_latest_run(
            ROOT / "benchmarks" / "leaks"
        )
        self.security_run = recommendation_engine.load_latest_run(
            ROOT / "benchmarks" / "security"
        )

    def _write_recommendations_report(self):
        self._refresh_auxiliary_runs()
        if recommendation_engine is None:
            text = (
                "# NativaX — recomendaciones\n\n"
                "El motor de recomendaciones no está disponible "
                "(tools/recommend.py).\n"
            )
        else:
            text = recommendation_engine.build_markdown(
                self._recommendation_data()
            )
        RECOMMENDATIONS_REPORT.parent.mkdir(parents=True, exist_ok=True)
        tmp = RECOMMENDATIONS_REPORT.with_suffix(".md.tmp")
        tmp.write_text(text)
        tmp.replace(RECOMMENDATIONS_REPORT)

    def _write_live_report(self):
        if not hasattr(self, "report_choice") or self.report_choice.get() != "En vivo":
            return
        self._refresh_auxiliary_runs()
        store = self.store
        visual = store.visual_summary()
        perf = store.perf_summary()
        categories = store.visual_categories()
        pixels = store.visual_pixels()
        app = store.app_idle or {}
        visual_total = len(store.catalog or []) or visual["total"]
        perf_total = len(store.perf_catalog or []) or perf["total"]
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        lines = [
            "# NativaX — informe en vivo",
            "",
            f"**Generado:** {now}. Se recalcula con los datos actuales del panel; "
            "no es una copia de un informe histórico.",
            "",
            "## Resumen",
            "",
            "| Área | Resultado |",
            "|---|---|",
            f"| Fidelidad visual | {visual['total']}/{visual_total} medidas · "
            f"{visual['PASS']} PASS, {visual['WARN']} WARN, {visual['FAIL']} FAIL, "
            f"{visual['INVALID']} INVALID |",
            f"| Rendimiento | {perf['total']}/{perf_total} medidos · "
            f"{perf['PASS']} PASS, {perf['WARN']} WARN, {perf['FAIL']} FAIL, "
            f"{perf['INVALID']} INVALID |",
            f"| App idle | {_num(app.get('rss_tail_mb'), 0)} MB · "
            f"{_num(app.get('cpu_tail_pct'), 2)} % CPU |",
            f"| Píxeles | {pixels['mismatched']:,} con ΔE > 2 de "
            f"{pixels['pixels']:,} |",
            "",
        ]
        if recommendation_engine is not None:
            rec_data = self._recommendation_data()
            recs = recommendation_engine.build_recommendations(rec_data)
            lines.extend(recommendation_engine.markdown_lines(rec_data, recs))
            lines.append("")
        lines.extend(["## Fidelidad visual", "", "| Categoría | Media |", "|---|---:|"])
        for name, value in categories.items():
            lines.append(f"| {name} | {_num(value, 2)} % |")
        lines.extend(["", f"Páginas medidas: **{visual['total']}** de "
                      f"**{visual_total}**.", "", "### Peores páginas", "",
                      "| Página | Veredicto | Overall | Posición | Layout | Color | Diseño |",
                      "|---|---|---:|---:|---:|---:|---:|"])
        for row in sorted(store.visual_rows,
                          key=lambda r: r.get("overall") or 0)[:10]:
            lines.append(
                f"| {row.get('page', '')} | {row.get('verdict', '')} | "
                f"{_num(row.get('overall'), 1)} | {_num(row.get('position'), 1)} | "
                f"{_num(row.get('layout'), 1)} | {_num(row.get('color'), 1)} | "
                f"{_num(row.get('design'), 1)} |"
            )
        lines.extend(["", "## Rendimiento", "",
                      f"Escenarios medidos: **{perf['total']}** de **{perf_total}**.",
                      "", "| Escenario | Veredicto | NativaX ms | Chromium ms | "
                      "Ratio | Frame p95 | RSS arnés MB |",
                      "|---|---|---:|---:|---:|---:|---:|"])
        for row in store.perf_rows:
            nativa = row.get("nativax") or {}
            chrome = row.get("chromium") or {}
            nwork = store.perf_work(row, "nativax")
            cwork = store.perf_work(row, "chromium")
            ratio = nwork / cwork if cwork > 0.0001 else None
            lines.append(
                f"| {row.get('scenario', '')} | {row.get('verdict', '')} | "
                f"{_num(nwork, 1)} | {_num(cwork, 1)} | "
                f"{(_num(ratio, 2) + 'x') if ratio is not None else '—'} | "
                f"{_num((nativa.get('frame_ms') or {}).get('p95'), 1)} | "
                f"{_num(nativa.get('rss_peak_mb'), 0)} |"
            )
        lines.extend(["", "## Idle real de la app", "",
                      f"- RSS: **{_num(app.get('rss_tail_mb'), 1)} MB** "
                      f"(objetivo 250 MB).",
                      f"- CPU: **{_num(app.get('cpu_tail_pct'), 2)} %** "
                      f"(objetivo 1 %).",
                      f"- GPU: {app.get('gpu') or 'no expuesta'}.", ""])
        if store.matrix:
            lines.extend(["## Contenedores", "",
                          f"Configuraciones: **{len(store.matrix_configs)}** · "
                          f"escenarios: **{len(store.matrix_scenarios)}**.", ""])
        lines.extend([
            "## Cómo se calcula",
            "",
            "- Fidelidad: píxeles, posición, layout, color y diseño computado "
            "contra Chromium headless.",
            "- Rendimiento: trabajo de NativaX frente a Chromium; frame p95, "
            "nodos, RSS y CPU.",
            "- Los valores de esta página se construyen desde `results.json`, "
            "`app-idle.json` y la matriz Docker; se actualizan solos.",
            "",
        ])
        LIVE_REPORT.parent.mkdir(parents=True, exist_ok=True)
        tmp = LIVE_REPORT.with_suffix(".md.tmp")
        tmp.write_text("\n".join(lines))
        tmp.replace(LIVE_REPORT)

    def _load_report(self):
        if self._live_report_timer is not None:
            try:
                self.root.after_cancel(self._live_report_timer)
            except tk.TclError:
                pass
            self._live_report_timer = None
        path = self._report_path()
        if self.report_choice.get() == "En vivo":
            self._write_live_report()
        elif self.report_choice.get() == "Recomendaciones":
            self._write_recommendations_report()
        elif self.report_choice.get() == "Conformidad":
            self._write_conformance_report()
        if self.report_choice.get() in ("En vivo", "Recomendaciones", "Conformidad"):
            if self.process is not None:
                try:
                    self.report_view.render(path.read_text(), path.parent)
                    self._report_sig = path.stat().st_mtime_ns
                except OSError:
                    pass
                return
        try:
            self._report_sig = path.stat().st_mtime_ns
        except OSError:
            self._report_sig = 0
        if not path.exists():
            self.report_view.render(
                f"# Sin informe\n\nNo existe todavía: `{path}`.\n\n"
                "Ejecuta la suite correspondiente.",
                path.parent,
            )
            return
        png = ROOT / ".perf" / "preview" / f"{path.stem}.png"
        try:
            if png.exists() and png.stat().st_mtime >= path.stat().st_mtime:
                self.report_view.show_png(png)
                return
        except OSError:
            pass
        # Show the readable text immediately, then replace it with the exact
        # HTML-rendered capture when headless Chrome finishes.
        self.report_view.render(path.read_text(), path.parent)
        self._queue_preview(path, png)

    def _queue_preview(self, path: Path, png: Path):
        key = str(path)
        if key in self.preview_jobs:
            return
        self.preview_jobs.add(key)

        def work():
            try:
                subprocess.run(
                    ["python3", "tools/render_report.py", str(path), "--png"],
                    cwd=ROOT,
                    capture_output=True,
                    timeout=120,
                )
            except Exception as error:
                self.log_queue.put(f"preview: {error}\n")
            self.preview_jobs.discard(key)
            self.preview_results.put((path, png))

        threading.Thread(target=work, daemon=True).start()

    # --------------------------------------------------------- row actions
    @staticmethod
    def _slug(value: str) -> str:
        return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_")[:120]

    def _write_json_atomic(self, path: Path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2) + "\n")
        tmp.replace(path)

    def _perf_context_menu(self, event):
        iid = self.perf_tree.identify_row(event.y)
        if not iid:
            return
        self.perf_tree.selection_set(iid)
        self._on_perf_select()
        self._popup_perf_menu(event.x_root, event.y_root, iid)

    def _perf_actions_menu(self):
        selected = self.perf_tree.selection()
        children = self.perf_tree.get_children()
        iid = selected[0] if selected else (children[0] if children else None)
        if not iid:
            return
        self.perf_tree.selection_set(iid)
        self._on_perf_select()
        self._popup_perf_menu(
            self.perf_actions.winfo_rootx(),
            self.perf_actions.winfo_rooty() + self.perf_actions.winfo_height(),
            iid,
        )

    def _popup_perf_menu(self, x, y, scenario_id):
        menu = tk.Menu(
            self.root, tearoff=0, bg=PANEL, fg=FG,
            activebackground=HOVER, activeforeground=FG,
            bd=0, relief="flat", font=(FONT, 9),
        )
        can_run = self.process is None
        menu.add_command(
            label="Ver detalles",
            command=lambda: self.open_detail("perf", scenario_id),
        )
        menu.add_command(
            label="Ejecutar este escenario y ver el resultado",
            command=lambda: self.run_perf_scenario(scenario_id),
            state="normal" if can_run else "disabled",
        )
        menu.add_separator()
        menu.add_command(
            label="Copiar id",
            command=lambda: self._copy_text(scenario_id),
        )
        try:
            menu.tk_popup(x, y)
        finally:
            menu.grab_release()

    def _visual_context_menu(self, event):
        iid = self.visual_tree.identify_row(event.y)
        if not iid:
            return
        self.visual_tree.selection_set(iid)
        self._on_visual_select()
        self._popup_visual_menu(event.x_root, event.y_root, iid)

    def _visual_actions_menu(self):
        selected = self.visual_tree.selection()
        children = self.visual_tree.get_children()
        iid = selected[0] if selected else (children[0] if children else None)
        if not iid:
            return
        self.visual_tree.selection_set(iid)
        self._on_visual_select()
        self._popup_visual_menu(
            self.visual_actions.winfo_rootx(),
            self.visual_actions.winfo_rooty() + self.visual_actions.winfo_height(),
            iid,
        )

    def _popup_visual_menu(self, x, y, page_id):
        menu = tk.Menu(
            self.root, tearoff=0, bg=PANEL, fg=FG,
            activebackground=HOVER, activeforeground=FG,
            bd=0, relief="flat", font=(FONT, 9),
        )
        can_run = self.process is None
        menu.add_command(
            label="Ver detalles",
            command=lambda: self.open_detail("visual", page_id),
        )
        menu.add_command(
            label="Ejecutar esta página y ver el resultado",
            command=lambda: self.run_visual_page(page_id),
            state="normal" if can_run else "disabled",
        )
        menu.add_separator()
        menu.add_command(label="Copiar id", command=lambda: self._copy_text(page_id))
        try:
            menu.tk_popup(x, y)
        finally:
            menu.grab_release()

    def _copy_text(self, text):
        self.root.clipboard_clear()
        self.root.clipboard_append(text)

    def _perf_detail_text(self, scenario_id):
        row = next(
            (r for r in self.store.perf_rows if r.get("scenario") == scenario_id),
            None,
        )
        entry = next(
            (e for e in (self.store.perf_catalog or []) if e.get("id") == scenario_id),
            None,
        )
        lines = []
        if row:
            nativa = row.get("nativax") or {}
            chrome = row.get("chromium") or {}
            lines.extend([
                f"{scenario_id}  ·  {row.get('verdict', '—')}",
                row.get("title", ""),
                f"Tipo: {row.get('kind', '—')}",
                f"Fuente: {row.get('source', '—')}",
                "",
                f"NativaX: {_num(self.store.perf_work(row, 'nativax'), 1)} ms "
                f"({_num(nativa.get('scenario_ms'), 1)} js + "
                f"{_num(nativa.get('render_ms'), 1)} frame)",
                f"Chromium: {_num(self.store.perf_work(row, 'chromium'), 1)} ms "
                f"({_num(chrome.get('scenario_ms'), 1)} js + "
                f"{_num(chrome.get('render_ms'), 1)} layout/style)",
                f"Nodos: {nativa.get('nodes')} / {chrome.get('nodes')}",
                f"Frame p95/max: {_num((nativa.get('frame_ms') or {}).get('p95'), 1)} / "
                f"{_num((nativa.get('frame_ms') or {}).get('max'), 1)} ms",
                f"Heap: {_num(chrome.get('heap_mb'), 2)} MB (solo Chromium)",
                f"RSS arnés: {_num(nativa.get('rss_peak_mb'), 0)} MB · CPU "
                f"{_num(nativa.get('cpu_peak_pct'), 1)} %",
            ])
            reasons = row.get("reasons") or []
            if reasons:
                lines.extend(["", "Motivos:"] + [f"· {r}" for r in reasons])
            ops = (nativa.get("extra") or {}).get("ops") or []
            if ops:
                lines.extend(["", "Operaciones:"])
                for op in ops:
                    if "error" in op:
                        lines.append(f"· {op.get('name')}: error")
                    else:
                        lines.append(
                            f"· {op.get('name')}: js {_num(op.get('eval_ms'), 1)} ms · "
                            f"frame {_num(op.get('pump_ms'), 1)} ms"
                        )
            read = (nativa.get("extra") or {}).get("read")
            if read:
                lines.extend(["", "Resultado de la página:", json.dumps(read, indent=2)[:2000]])
        elif entry:
            lines.extend([
                f"{scenario_id}  ·  pendiente",
                entry.get("title", ""),
                f"Tipo: {entry.get('kind', '—')}",
                f"Fuente: {entry.get('source', '—')}",
                "",
                entry.get("description", ""),
                "",
                "Este escenario todavía no se ha medido.",
                "Usa «Ejecutar este escenario y ver el resultado».",
            ])
        else:
            lines.append(f"{scenario_id}: sin datos.")
        return "\n".join(lines)

    def _visual_detail_text(self, page_id):
        row = next(
            (r for r in self.store.visual_rows if r.get("page") == page_id),
            None,
        )
        entry = next(
            (e for e in (self.store.catalog or []) if e.get("id") == page_id),
            None,
        )
        if row:
            lines = [
                f"{page_id}  ·  {row.get('verdict', '—')}",
                f"Suite: {row.get('suite', '—')}",
                "",
                f"Overall: {_num(row.get('overall'), 1)} %",
                f"Posición: {_num(row.get('position'), 1)} %",
                f"Layout: {_num(row.get('layout'), 1)} %",
                f"Color: {_num(row.get('color'), 1)} %",
                f"Diseño: {_num(row.get('design'), 1)} %",
                "",
                f"Píxeles distintos: {_num(row.get('mismatched_pct'), 2)} %",
                f"Tinta distinta: {_num(row.get('ink_mismatch_pct'), 2)} %",
                f"ΔE medio: {_num(row.get('mean_delta_e'), 2)} · "
                f"ΔE máximo: {_num(row.get('max_delta_e'), 2)}",
                f"Elementos: {row.get('matched', '—')} emparejados · "
                f"{row.get('missing', '—')} faltan · {row.get('extra', '—')} sobran",
                "",
                f"Chromium: {row.get('chrome_png', '—')}",
                f"NativaX: {row.get('nativax_png', '—')}",
                f"Diferencia: {row.get('diff_png', '—')}",
            ]
            if row.get("failure"):
                lines.extend(["", f"Fallo: {row['failure']}"])
        elif entry:
            lines = [
                f"{page_id}  ·  pendiente",
                f"Suite: {entry.get('suite', '—')}",
                "",
                f"HTML: {entry.get('entry', '—')}",
                f"Directorio: {entry.get('directory', '—')}",
                "",
                "Esta página todavía no se ha medido.",
                "Usa «Ejecutar esta página y ver el resultado».",
            ]
        else:
            lines = [f"{page_id}: sin datos."]
        return "\n".join(lines)

    def open_detail(self, kind, item_id=None):
        if item_id is None:
            tree = self.perf_tree if kind == "perf" else self.visual_tree
            selected = tree.selection()
            if not selected:
                return
            item_id = selected[0]
        title = f"{'Escenario' if kind == 'perf' else 'Página'} · {item_id}"
        text_value = (self._perf_detail_text(item_id) if kind == "perf"
                      else self._visual_detail_text(item_id))
        win = tk.Toplevel(self.root)
        win.title(title)
        win.geometry("960x680")
        win.configure(bg=BG)
        win.transient(self.root)
        tk.Label(
            win, text=title, bg=BG, fg=FG, font=(FONT, 16, "bold"),
            anchor="w", padx=18, pady=12,
        ).pack(fill="x")
        body = tk.Frame(win, bg=PANEL)
        body.pack(fill="both", expand=True, padx=18, pady=(0, 10))
        text = tk.Text(
            body, bg=PANEL, fg=FG, relief="flat", wrap="word",
            padx=14, pady=10, font=(MONO, 9),
            insertbackground=FG,
        )
        scroll = ttk.Scrollbar(body, orient="vertical", command=text.yview)
        text.configure(yscrollcommand=scroll.set)
        text.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        text.insert("1.0", text_value)
        text.configure(state="disabled")
        buttons = tk.Frame(win, bg=BG)
        buttons.pack(fill="x", padx=18, pady=(0, 14))
        tk.Button(
            buttons, text="Cerrar", command=win.destroy,
            bg=PANEL2, fg=FG, relief="flat", padx=12, pady=5,
        ).pack(side="right", padx=(6, 0))

        def run_and_close():
            win.destroy()
            if kind == "perf":
                self.run_perf_scenario(item_id)
            else:
                self.run_visual_page(item_id)

        tk.Button(
            buttons, text="Ejecutar y ver resultado", command=run_and_close,
            bg=ACCENT, fg="#07101f", relief="flat", padx=12, pady=5,
            state="normal" if self.process is None else "disabled",
        ).pack(side="right")
        win.bind("<Escape>", lambda _e: win.destroy())

    def run_perf_scenario(self, scenario_id):
        if self.process is not None:
            messagebox.showinfo("En curso", "Ya hay una ejecución en marcha.")
            return
        out = ROOT / ".perf" / "single" / self._slug(scenario_id)
        if out.exists():
            shutil.rmtree(out, ignore_errors=True)
        self._start(
            ["dart", "run", "tools/perf/bin/perf.dart", "run",
             "--only", f"^{re.escape(scenario_id)}$", "--out", str(out)],
            f"escenario {scenario_id}",
            action={
                "kind": "perf", "id": scenario_id, "out": out,
                "open_detail": True,
            },
        )

    def run_visual_page(self, page_id):
        if self.process is not None:
            messagebox.showinfo("En curso", "Ya hay una ejecución en marcha.")
            return
        out = ROOT / ".visual" / "single" / self._slug(page_id)
        if out.exists():
            shutil.rmtree(out, ignore_errors=True)
        self._start(
            ["dart", "run", "tools/visual/bin/visual_check.dart",
             "--all", "--only", f"^{re.escape(page_id)}$", "--out", str(out)],
            f"página {page_id}",
            action={
                "kind": "visual", "id": page_id, "out": out,
                "open_detail": True,
            },
        )

    def _merge_single(self, action):
        kind = action["kind"]
        item_id = action["id"]
        out = Path(action["out"])
        data = _load_json(out / "results.json")
        if not data:
            self._append_log(
                f"[single] {item_id}: no hay results.json; no se fusiona\n"
            )
            return
        if kind == "perf":
            rows = data.get("results") or []
            new = next(
                (r for r in rows if r.get("scenario") == item_id),
                None,
            )
            if new is None:
                self._append_log(f"[single] {item_id}: resultado no encontrado\n")
                return
            base = _load_json(PERF_RESULTS) or data
            base_rows = base.get("results") or []
            for index, row in enumerate(base_rows):
                if row.get("scenario") == item_id:
                    base_rows[index] = new
                    break
            else:
                base_rows.append(new)
            base["results"] = base_rows
            if not isinstance(base.get("summary"), dict):
                base["summary"] = {}
            for verdict in ("pass", "warn", "fail", "invalid"):
                base["summary"][verdict] = sum(
                    1 for row in base_rows
                    if str(row.get("verdict", "")).lower() == verdict
                )
            base["summary"]["scenarios"] = len(base_rows)
            base["generated_at"] = datetime.now().isoformat(timespec="seconds")
            self._write_json_atomic(PERF_RESULTS, base)
            self._append_log(f"[single] {item_id}: resultado actualizado\n")
        else:
            rows = data.get("rows") or []
            new = next((r for r in rows if r.get("page") == item_id), None)
            if new is None and len(rows) == 1:
                new = rows[0]
            if new is None:
                self._append_log(f"[single] {item_id}: resultado no encontrado\n")
                return
            base = (
                _load_json(VISUAL_CANDIDATES[0])
                or _load_json(VISUAL_CANDIDATES[1])
                or self.store.visual
                or data
            )
            base_rows = base.get("rows") or []
            for index, row in enumerate(base_rows):
                if row.get("page") == item_id:
                    base_rows[index] = new
                    break
            else:
                base_rows.append(new)
            base["rows"] = base_rows
            scores = [r.get("overall") for r in base_rows
                      if isinstance(r.get("overall"), (int, float))]
            if not isinstance(base.get("summary"), dict):
                base["summary"] = {}
            base["summary"]["pages"] = len(base_rows)
            base["summary"]["meanOverall"] = (
                sum(scores) / len(scores) if scores else 0
            )
            base["generatedAt"] = datetime.now().isoformat(timespec="seconds")
            self._write_json_atomic(VISUAL_CANDIDATES[0], base)
            self._append_log(f"[single] {item_id}: resultado actualizado\n")

    def _set_running(self, running: bool):
        state = "disabled" if running else "normal"
        for button in self.buttons:
            if button is not self.stop_button:
                button.configure(state=state)
        self.stop_button.configure(state="normal" if running else "disabled")
        if running:
            self.progress.start(12)
            self.status.configure(text="ejecutando…")
        else:
            self.progress.stop()
            self.status.configure(text="listo")

    def _start(self, command, label, action=None):
        if self.process is not None:
            messagebox.showinfo("En curso", "Ya hay una ejecución en marcha.")
            return
        self.pending_action = action
        self._set_running(True)
        self._run_done = 0
        self._run_total = 0
        self._append_log(f"\n$ {label}\n")
        try:
            self.process = subprocess.Popen(
                command,
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
        except Exception as error:
            self._append_log(f"error: {error}\n")
            self.process = None
            self.pending_action = None
            self._set_running(False)
            return

        def reader(proc):
            assert proc.stdout is not None
            for line in proc.stdout:
                self.log_queue.put(line)
            proc.wait()

        threading.Thread(target=reader, args=(self.process,), daemon=True).start()

    def _append_log(self, text):
        self.log.configure(state="normal")
        self.log.insert("end", text)
        self.log.see("end")
        self.log.configure(state="disabled")
        progress = re.findall(r"\[\s*(\d+)\s*/\s*(\d+)\s*\]", text)
        if progress and self.process is not None:
            done, total = progress[-1]
            self._run_done = int(done)
            self._run_total = int(total)
            self.status.configure(text=f"{done}/{total} · ejecutando…")

    def _drain_log(self):
        try:
            while True:
                self._append_log(self.log_queue.get_nowait())
        except queue.Empty:
            pass
        while True:
            try:
                path, png = self.preview_results.get_nowait()
            except queue.Empty:
                break
            try:
                if (self._report_path() == path and png.exists()
                        and png.stat().st_mtime_ns >= path.stat().st_mtime_ns):
                    self.report_view.show_png(png)
                elif self._report_path() == path and png.exists():
                    self._report_sig = None
            except OSError:
                pass
        while True:
            try:
                kind = self.catalog_results.get_nowait()
            except queue.Empty:
                break
            self._append_log(f"[catálogo {kind} actualizado]\n")
            self._last_data_sig = None
            self._refresh_data()
        if self.process is not None and self.process.poll() is not None:
            self.process = None
            self._set_running(False)
            action = self.pending_action
            self.pending_action = None
            if action:
                try:
                    self._merge_single(action)
                except Exception as error:
                    self._append_log(f"[single] error al fusionar: {error}\n")
            self.reload()
            if action and action.get("open_detail"):
                try:
                    self.open_detail(action["kind"], action["id"])
                except Exception as error:
                    self._append_log(f"[single] error al abrir detalle: {error}\n")
        self.root.after(150, self._drain_log)

    def run_all(self):
        self._start(["tools/quality_report.sh"], "tools/quality_report.sh")

    def run_visual(self):
        self._start(
            ["dart", "run", "tools/visual/bin/visual_check.dart",
             "--suite", "50projects50days", "--out", str(VISUAL_DIR)],
            "juicio visual 50projects50days",
        )

    def run_visual_all(self):
        self._start(
            ["dart", "run", "tools/visual/bin/visual_check.dart",
             "--all", "--catalog", str(ROOT / ".visual" / "catalog.json"),
             "--out", str(VISUAL_DIR)],
            "juicio visual completo (300 páginas)",
        )

    def run_perf(self):
        self._start(
            ["dart", "run", "tools/perf/bin/perf.dart", "run",
             "--app-idle", "--out", str(PERF_DIR)],
            "suite de rendimiento (100 escenarios)",
        )

    def run_idle(self):
        self._start(
            ["dart", "run", "tools/perf/bin/perf.dart", "idle-app",
             "--seconds", "5", "--out", str(PERF_DIR / "app-idle.json")],
            "idle real de la app",
        )

    def stop(self):
        if self.process is None:
            return
        try:
            os.killpg(os.getpgid(self.process.pid), signal.SIGKILL)
        except Exception:
            try:
                self.process.kill()
            except Exception:
                pass
        self._append_log("\n[detenido por el usuario]\n")

    def _toggle_log(self):
        if self.log_visible:
            self.log_container.pack_forget()
            self.log_toggle.configure(text="▸ Registro")
        else:
            self.log_container.pack(fill="x")
            self.log_toggle.configure(text="▾ Registro")
        self.log_visible = not self.log_visible

    def open_folder(self):
        folder = PERF_DIR if PERF_DIR.exists() else ROOT
        subprocess.Popen(["xdg-open", str(folder)])


def main():
    root = tk.Tk()
    if os.environ.get("NATIVAX_GUI_TOPMOST") == "1":
        root.attributes("-topmost", True)
    dashboard = Dashboard(root)

    def on_close():
        if dashboard.process is not None:
            dashboard.stop()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    root.mainloop()


if __name__ == "__main__":
    main()

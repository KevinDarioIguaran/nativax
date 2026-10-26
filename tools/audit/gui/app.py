#!/usr/bin/env python3
"""Juez de auditoría JSON — visual explorer for the reports `nxaudit` writes.

  python3 tools/audit/gui/app.py [--root .audit] [--unit PATH]

Every run folder is an independent report. The folder tree on the left
navigates any folder layout; opening a report loads only that report, and
every section shows only its data. Two reports are compared only in the
explicit Comparación view, which keeps both origins labelled.

The GUI never writes inside a report folder. Actions that run the engine
(run, replay, verify, promote) call `tools/audit/audit.py` and say so.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

sys.path.insert(0, str(Path(__file__).resolve().parent))

import jsondiff  # noqa: E402
import store  # noqa: E402
from widgets import (ACCENT, BG, BORDER, FG, FONT, MONO, MUTED, PANEL, PANEL2, RED,  # noqa: E402
                     STATUS_COLORS, UNKNOWN, YELLOW, BarChart, DiffView, Histogram, JsonView, KeyValue,
                     LineChart, Table, button, copy, entry, fmt, label, style)

from nxaudit.catalog import COMPONENTS, PROPERTIES  # noqa: E402
from nxaudit.compile import compile_screen, walk  # noqa: E402

ROOT = store.ROOT
DEFAULT_ROOT = ROOT / ".audit"
PREFS = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "nativax-audit-gui.json"

SECTIONS = [
    ("reports", "Informes (carpetas)"),
    ("summary", "Resumen"),
    ("runs", "Ejecuciones"),
    ("catalog", "Catálogo de pantallas"),
    ("inspector", "Inspector de escenario"),
    ("issues", "Centro de defectos"),
    ("issue", "Defecto"),
    ("traces", "Trazas y evidencias"),
    ("matrix", "Componentes y propiedades"),
    ("coverage", "Cobertura"),
    ("algorithm", "Algoritmo de exploración"),
    ("compare", "Comparación"),
    ("minimize", "Minimización y reproducción"),
    ("perf", "Rendimiento y recursos"),
    ("regressions", "Historial de regresiones"),
    ("files", "Archivos y exportación"),
    ("execute", "Ejecutar el motor"),
]


def load_prefs() -> dict:
    try:
        return json.loads(PREFS.read_text())
    except (OSError, ValueError):
        return {}


def save_prefs(data: dict):
    try:
        PREFS.parent.mkdir(parents=True, exist_ok=True)
        PREFS.write_text(json.dumps(data, indent=2))
    except OSError:
        pass


def value_class(prop, value):
    """Where an authored value sits in the catalog domain (display only)."""
    domain = PROPERTIES.get(prop)
    if domain is None:
        return "propiedad fuera del catálogo"
    for name in ("valid", "boundary", "invalid"):
        if value in domain.get(name, []):
            return {"valid": "válido", "boundary": "límite", "invalid": "inválido"}[name]
    return "desconocido (fuera de los dominios del catálogo)"


class App:
    def __init__(self, root: tk.Tk, report_root: Path, unit: Path | None = None):
        self.tk = root
        self.prefs = load_prefs()
        self.report_root = Path(report_root)
        self.folder = self.report_root
        self.unit: store.Unit | None = None
        self.units: dict[str, store.Unit] = {}
        self.process = None
        self.proc_queue: queue.Queue = queue.Queue()
        self.section = None
        self.frames: dict[str, tk.Frame] = {}
        self.built: set[str] = set()
        self.issue_id = None
        self.scenario_ref = None   # (unit path, scenario_id) or raw dict
        self.compare_pair: list[str] = []
        root.title("NativaX · Juez de auditoría JSON")
        root.geometry("1600x980")
        root.minsize(1100, 700)
        root.configure(bg=BG)
        style(root)
        self._build_shell()
        root.bind("<Control-f>", lambda _e: self.search_entry.focus_set())
        root.bind("<F5>", lambda _e: self.reload())
        self.tk.after(100, self._drain_proc)
        target = unit or (Path(self.prefs["unit"]) if self.prefs.get("unit") else None)
        self._fill_tree()
        if target and store.is_unit(target):
            self.open_unit(target, section=self.prefs.get("section") or "summary")
        else:
            self.show("reports")

    # ------------------------------------------------------------------ shell
    def _build_shell(self):
        top = tk.Frame(self.tk, bg=PANEL, padx=10, pady=6)
        top.pack(fill="x")
        label(top, "Juez de auditoría JSON", fg=FG, size=12, bold=True, bg=PANEL).pack(side="left")
        self.identity = label(top, "ningún informe abierto", fg=MUTED, mono=True, bg=PANEL)
        self.identity.pack(side="left", padx=14)
        self.search_all = tk.BooleanVar(value=False)
        tk.Checkbutton(top, text="en toda la carpeta", variable=self.search_all, bg=PANEL, fg=MUTED,
                       selectcolor=PANEL2, activebackground=PANEL, font=(FONT, 8)).pack(side="right")
        button(top, "Buscar", self.global_search).pack(side="right", padx=4)
        self.search_entry = entry(top, 30)
        self.search_entry.pack(side="right")
        self.search_entry.bind("<Return>", lambda _e: self.global_search())
        label(top, "Búsqueda global (Ctrl+F)", bg=PANEL).pack(side="right", padx=6)

        body = tk.PanedWindow(self.tk, orient="horizontal", bg=BG, sashwidth=5, bd=0)
        body.pack(fill="both", expand=True)
        side = tk.Frame(body, bg="#0c1117", width=300)
        body.add(side, stretch="never", minsize=240)
        self.nav = {}
        for key, text in SECTIONS:
            lab = tk.Label(side, text=text, bg="#0c1117", fg=MUTED, anchor="w", padx=14, pady=3,
                           font=(FONT, 9, "bold"), cursor="hand2", takefocus=1)
            lab.pack(fill="x")
            lab.bind("<Button-1>", lambda _e, k=key: self.show(k))
            lab.bind("<Return>", lambda _e, k=key: self.show(k))
            self.nav[key] = lab
        tk.Frame(side, bg=BORDER, height=1).pack(fill="x", pady=6)
        row = tk.Frame(side, bg="#0c1117")
        row.pack(fill="x", padx=6)
        label(row, "Carpetas de informes", bg="#0c1117").pack(side="left")
        button(row, "Abrir carpeta…", self.choose_root).pack(side="right")
        button(row, "↻", self.reload).pack(side="right", padx=2)
        self.root_label = label(side, str(self.report_root), mono=True, bg="#0c1117", size=8,
                                wraplength=280, justify="left")
        self.root_label.pack(fill="x", padx=8)
        tf = tk.Frame(side, bg="#0c1117")
        tf.pack(fill="both", expand=True, padx=4, pady=4)
        self.folder_tree = ttk.Treeview(tf, show="tree", selectmode="browse")
        ys = ttk.Scrollbar(tf, orient="vertical", command=self.folder_tree.yview)
        self.folder_tree.configure(yscrollcommand=ys.set)
        self.folder_tree.pack(side="left", fill="both", expand=True)
        ys.pack(side="left", fill="y")
        for name, color in STATUS_COLORS.items():
            self.folder_tree.tag_configure(name, foreground=color)
        self.folder_tree.bind("<<TreeviewOpen>>", self._tree_open)
        self.folder_tree.bind("<<TreeviewSelect>>", self._tree_select)
        self.folder_tree.bind("<Double-1>", self._tree_activate)
        self.folder_tree.bind("<Return>", self._tree_activate)

        self.main = tk.Frame(body, bg=BG, padx=10, pady=6)
        body.add(self.main, stretch="always")
        self.status = label(self.tk, "", bg=PANEL, anchor="w", padx=10)
        self.status.pack(fill="x", side="bottom")

    def set_status(self, text, color=MUTED):
        self.status.configure(text=text, fg=color)
        self.tk.update_idletasks()

    def show(self, key):
        if key not in self.frames:
            frame = tk.Frame(self.main, bg=BG)
            self.frames[key] = frame
        for k, f in self.frames.items():
            f.pack_forget()
        for k, lab in self.nav.items():
            lab.configure(fg=FG if k == key else MUTED, bg="#151d27" if k == key else "#0c1117")
        frame = self.frames[key]
        frame.pack(fill="both", expand=True)
        if key not in self.built:
            self.built.add(key)
            getattr(self, f"_build_{key}")(frame)
        self.section = key
        self.prefs["section"] = key
        save_prefs(self.prefs)
        try:
            getattr(self, f"_fill_{key}")()
        except Exception as error:  # noqa: BLE001 - a broken report must not kill the GUI
            self.set_status(f"Error al mostrar «{key}»: {error}", RED)
            raise

    def header(self, frame, title, subtitle=""):
        bar = tk.Frame(frame, bg=BG)
        bar.pack(fill="x", pady=(0, 4))
        label(bar, title, fg=FG, size=13, bold=True).pack(side="left")
        sub = label(bar, subtitle)
        sub.pack(side="left", padx=10)
        return bar, sub

    def need_unit(self, frame_key) -> bool:
        if self.unit is None:
            self.set_status("Abre un informe en «Informes (carpetas)» o en el árbol de la izquierda.", YELLOW)
            return False
        return True

    # --------------------------------------------------------------- folders
    def choose_root(self):
        d = filedialog.askdirectory(initialdir=str(self.report_root), title="Carpeta raíz de informes")
        if d:
            self.report_root = Path(d)
            self.folder = self.report_root
            self.root_label.configure(text=str(self.report_root))
            self._fill_tree()
            self.show("reports")

    def reload(self):
        self.units.clear()
        path = self.unit.path if self.unit else None
        self._fill_tree()
        if path:
            self.open_unit(path, section=self.section or "summary")
        elif self.section:
            self.show(self.section)

    def _fill_tree(self):
        t = self.folder_tree
        t.delete(*t.get_children())
        self._insert_dir("", self.report_root, open_=True)

    def _insert_dir(self, parent, path: Path, open_=False):
        if store.is_unit(path):
            m = store.unit_meta(path)
            text = f"▣ {path.name}" + (f"  (copia de {m.alias_of})" if m.alias_of else "")
            t = self.folder_tree.insert(parent, "end", iid=str(path), text=text, tags=(m.health,),
                                        values=("unit",))
            return t
        node = self.folder_tree.insert(parent, "end", iid=str(path), text=f"▸ {path.name}/", open=open_,
                                       values=("dir",))
        kids = store.child_dirs(path)
        if open_:
            for k in kids:
                self._insert_dir(node, k)
        elif kids:
            self.folder_tree.insert(node, "end", iid=str(path) + "::placeholder", text="…")
        return node

    def _tree_open(self, _e=None):
        item = self.folder_tree.focus()
        ph = item + "::placeholder"
        if self.folder_tree.exists(ph):
            self.folder_tree.delete(ph)
            for k in store.child_dirs(Path(item)):
                if not self.folder_tree.exists(str(k)):
                    self._insert_dir(item, k)

    def _tree_select(self, _e=None):
        sel = self.folder_tree.selection()
        if not sel or sel[0].endswith("::placeholder"):
            return
        path = Path(sel[0])
        if not store.is_unit(path):
            self.folder = path
            if self.section == "reports":
                self._fill_reports()

    def _tree_activate(self, _e=None):
        sel = self.folder_tree.selection()
        if sel and store.is_unit(Path(sel[0])):
            self.open_unit(Path(sel[0]))

    def get_unit(self, path) -> store.Unit:
        key = str(path)
        if key not in self.units:
            self.units[key] = store.Unit(Path(path))
        return self.units[key]

    def open_unit(self, path, section="summary"):
        self.set_status(f"cargando {path} …")
        self.unit = self.get_unit(path)
        m = self.unit.meta
        self.identity.configure(
            text=f"{m.kind} · {m.name} · {m.status} · {self._rel(m.path)}",
            fg=STATUS_COLORS.get(m.health, MUTED))
        self.prefs["unit"] = str(path)
        save_prefs(self.prefs)
        self.issue_id = None
        self.scenario_ref = None
        if self.folder_tree.exists(str(path)):
            self.folder_tree.see(str(path))
        self.show(section)
        self.set_status(f"informe abierto: {path}" + (f" · {m.note}" if m.note else ""))

    @staticmethod
    def _rel(p):
        try:
            return str(Path(p).relative_to(ROOT))
        except ValueError:
            return str(p)

    # --------------------------------------------------------------- reports
    def _build_reports(self, f):
        bar, self.reports_sub = self.header(f, "Informes", "cada carpeta de ejecución es un informe independiente")
        button(bar, "◀ Carpeta anterior", self.folder_up).pack(side="right")
        button(bar, "Comparar 2 seleccionados", self.compare_selected_reports).pack(side="right", padx=4)
        button(bar, "Abrir informe", lambda: [self.open_unit(Path(r["abs"])) for r in
                                              self.reports_table.selected_rows()[:1]]).pack(side="right")
        filt = tk.Frame(f, bg=BG)
        filt.pack(fill="x", pady=2)
        self.reports_recursive = tk.BooleanVar(value=True)
        tk.Checkbutton(filt, text="incluir subcarpetas", variable=self.reports_recursive, bg=BG, fg=FG,
                       selectcolor=PANEL2, activebackground=BG, command=self._fill_reports,
                       font=(FONT, 9)).pack(side="left")
        self.reports_filters = {}
        for key, values in (("kind", ["(todos)", "auditoría", "benchmark", "self-check"]),
                            ("status", ["(todos)", "complete", "incomplete", "corrupt"]),
                            ("health", ["(todos)", "error", "warn", "ok", "unknown"])):
            label(filt, key).pack(side="left", padx=(10, 2))
            cb = ttk.Combobox(filt, values=values, width=12, state="readonly")
            cb.current(0)
            cb.bind("<<ComboboxSelected>>", lambda _e: self._apply_report_filters())
            cb.pack(side="left")
            self.reports_filters[key] = cb
        self.reports_path = label(f, "", mono=True, fg=ACCENT)
        self.reports_path.pack(fill="x")
        self.reports_table = Table(f, [
            ("name", "Informe", 230, "w"), ("kind", "Tipo", 80, "w"), ("status", "Estado", 80, "w"),
            ("health", "Resultado", 70, "w"), ("started_at", "Inicio", 140, "w"),
            ("finished_at", "Fin / actualizado", 140, "w"), ("executed", "Ejecutados", 70, "e"),
            ("issues", "Defectos", 64, "e"), ("critical_high", "Crít./altos", 70, "e"),
            ("commit", "Commit", 70, "w"), ("alias_of", "Copia de", 150, "w"), ("rel", "Ruta", 300, "w"),
            ("note", "Nota", 260, "w")],
            tag_key="health", multi=True, on_open=lambda r: self.open_unit(Path(r["abs"])))
        self.reports_table.pack(fill="both", expand=True)

    def _fill_reports(self):
        paths = store.discover(self.folder) if self.reports_recursive.get() else \
            [p for p in store.child_dirs(self.folder) if store.is_unit(p)] + \
            ([self.folder] if store.is_unit(self.folder) else [])
        rows = []
        for p in paths:
            m = store.unit_meta(p)
            rows.append({**m.__dict__, "abs": str(p), "rel": self._rel(p), "path": str(p)})
        self.reports_table.set_rows(rows)
        self._apply_report_filters()
        self.reports_path.configure(text=f"carpeta: {self.folder}")
        self.reports_sub.configure(text=f"{len(rows)} informes en esta carpeta"
                                        + (" y subcarpetas" if self.reports_recursive.get() else ""))

    def _apply_report_filters(self):
        vals = {k: cb.get() for k, cb in self.reports_filters.items()}
        self.reports_table.set_predicate(lambda r: all(v == "(todos)" or r.get(k) == v for k, v in vals.items()))

    def folder_up(self):
        if self.folder != self.report_root and self.report_root in self.folder.parents:
            self.folder = self.folder.parent
        self._fill_reports()

    def compare_selected_reports(self):
        rows = self.reports_table.selected_rows()
        if len(rows) != 2:
            messagebox.showinfo("Comparar", "Selecciona exactamente dos informes (Ctrl+clic).")
            return
        self.compare_pair = [rows[0]["abs"], rows[1]["abs"]]
        self.show("compare")

    # --------------------------------------------------------------- summary
    def _build_summary(self, f):
        self.header(f, "Resumen", "cifras de este informe; clic en una cifra para ver sus registros")
        self.sum_banner = label(f, "", fg=YELLOW, anchor="w", justify="left")
        self.sum_banner.pack(fill="x")
        self.sum_grid = tk.Frame(f, bg=BG)
        self.sum_grid.pack(fill="x", pady=4)
        charts = tk.Frame(f, bg=BG)
        charts.pack(fill="x")
        self.sum_sev = BarChart(charts, height=150, on_click=lambda k: self.open_issues(severity=k))
        self.sum_sev.pack(side="left", fill="x", expand=True, padx=2)
        self.sum_sub = BarChart(charts, height=150, on_click=lambda k: self.open_issues(subsystem=k))
        self.sum_sub.pack(side="left", fill="x", expand=True, padx=2)
        self.sum_status = BarChart(charts, height=150, on_click=lambda k: self.open_runs(status=k))
        self.sum_status.pack(side="left", fill="x", expand=True, padx=2)
        label(f, "Todas las métricas registradas por el motor (metrics.json)", fg=FG, bold=True).pack(
            anchor="w", pady=(6, 0))
        self.sum_metrics = Table(f, [("metric", "Métrica", 260, "w"), ("value", "Valor", 160, "e"),
                                     ("source", "Origen", 300, "w")], page_size=120, height=10)
        self.sum_metrics.pack(fill="both", expand=True)

    def _fill_summary(self):
        if not self.need_unit("summary"):
            return
        u = self.unit
        for c in self.sum_grid.winfo_children():
            c.destroy()
        s, m = u.summary(), u.metrics()
        notes = []
        if not s.ok:
            notes.append(f"summary.json {s.error}.")
        if u.meta.status == "incomplete":
            st = u.state().value or {}
            notes.append(f"Informe incompleto: {st.get('executed', '—')} de {st.get('budget', '—')} escenarios "
                         f"ejecutados según state.json ({st.get('updated_at', '—')}); los datos de abajo salen "
                         "de results.jsonl.")
        raw = u.raw_results()
        if raw.skipped_lines:
            notes.append(f"results.jsonl: {raw.skipped_lines} líneas corruptas ignoradas (escritura interrumpida).")
        if raw.error and "no existe" not in raw.error:
            notes.append(f"results.jsonl {raw.error}.")
        self.sum_banner.configure(text=" ".join(notes))
        metrics = m.value if m.ok else (s.value or {}).get("metrics") if s.ok else {}
        metrics = metrics or {}
        rows = u.rows()
        state = u.state().value or {}
        pending = None
        budget = ((s.value or {}).get("config") or {}).get("budget") if s.ok else state.get("budget")
        if budget is not None:
            pending = max(0, budget - len(rows))
        issues = [r for r in u.issue_rows() if "error" not in r]
        confirmed = sum(1 for r in issues if r.get("root_cause") == "confirmed")
        dur = u.durations()
        tiles = [
            ("Generados", metrics.get("generated"), "candidatos generados (metrics.generated)", None),
            ("Rechazados por esquema", metrics.get("rejected"),
             f"de ellos negativos deliberados: {fmt(metrics.get('rejected_expected'))}", None),
            ("Escapes del validador", metrics.get("validator_escapes"), "negativos que pasaron: defecto del motor", None),
            ("Ejecutados", len(rows), "filas en results.jsonl", lambda: self.open_runs()),
            ("Pendientes", pending, f"presupuesto {fmt(budget)} − ejecutados", None),
            ("Verificados", metrics.get("verified"), "ambos motores con status ok", lambda: self.open_runs(verified=True)),
            ("Con defectos", sum(1 for r in rows if r["status"] == "failed"), "status = failed",
             lambda: self.open_runs(status="failed")),
            ("Sin defectos", sum(1 for r in rows if r["status"] == "passed"), "status = passed",
             lambda: self.open_runs(status="passed")),
            ("No concluyentes", sum(1 for r in rows if r["status"] == "inconclusive"), "referencia o arnés no disponibles",
             lambda: self.open_runs(status="inconclusive")),
            ("Defectos únicos", sum(1 for r in issues if r["status"] == "failed"), "issues/*.json con status failed",
             lambda: self.open_issues(status="failed")),
            ("Causa confirmada", confirmed, "root_cause.status = confirmed (solo con traza)",
             lambda: self.open_issues(root_cause="confirmed")),
            ("Causa sin confirmar", sum(1 for r in issues if r.get("root_cause") == "unconfirmed"),
             "hipótesis, no causas", lambda: self.open_issues(root_cause="unconfirmed")),
            ("Nuevos", sum(1 for r in issues if r.get("novelty") == "new"), "según el ledger al ejecutarse",
             lambda: self.open_issues(novelty="new")),
            ("Regresiones", sum(1 for r in issues if r.get("novelty") == "regression"), "marcados fixed y reaparecidos",
             lambda: self.open_issues(novelty="regression")),
            ("Conflictos de oráculo", sum(1 for r in issues if r["status"] == "oracle_conflict"),
             "no cuentan como defectos", lambda: self.open_issues(status="oracle_conflict")),
            ("Minimizados", sum(1 for r in issues if r.get("minimized")), "reproduction.minimized",
             lambda: self.show("minimize")),
            ("No reproducibles", sum(1 for r in issues if r.get("reproducible") is False), "re-ejecución sin la firma",
             lambda: self.open_issues(reproducible=False)),
            ("Sin re-ejecutar", sum(1 for r in issues if r.get("reproducible") is None), "reproducible = null",
             lambda: self.open_issues(reproducible=None)),
            ("Hallazgos brutos", metrics.get("findings"), "antes de agrupar", lambda: self.show("traces")),
            ("Tiempo total", metrics.get("wall_s"), "segundos de pared (metrics.wall_s)", lambda: self.show("perf")),
            ("Duración p50 / p95", None if dur["total"]["p50"] is None else
             f"{fmt(dur['total']['p50'], 0)} / {fmt(dur['total']['p95'], 0)} ms",
             f"timings.total_ms de NativaX, n={dur['measured']}", lambda: self.show("perf")),
            ("Defectos por minuto", metrics.get("issues_per_minute"), "únicos / minutos de pared", None),
            ("RSS máx. arnés", metrics.get("max_rss_mb"), "MB, flutter_tester", lambda: self.show("perf")),
        ]
        cov = ((s.value or {}).get("coverage") or {}) if s.ok else {}
        for dim in ("componentes", "propiedades", "pares de propiedades"):
            row = cov.get(dim) or {}
            if row:
                tiles.append((f"Cobertura {dim}", f"{fmt(row.get('verified'))}/{fmt(row.get('universe'))}",
                              "verificada / universo del catálogo", lambda: self.show("coverage")))
        for i, (name, value, source, action) in enumerate(tiles):
            box = tk.Frame(self.sum_grid, bg=PANEL, padx=8, pady=4, highlightthickness=1,
                           highlightbackground=BORDER, cursor="hand2" if action else "")
            box.grid(row=i // 7, column=i % 7, sticky="nsew", padx=2, pady=2)
            v = tk.Label(box, text="no medido" if value is None else fmt(value), bg=PANEL,
                         fg=UNKNOWN if value is None else FG, font=(MONO, 12, "bold"), anchor="w")
            v.pack(fill="x")
            tk.Label(box, text=name, bg=PANEL, fg=FG, font=(FONT, 8, "bold"), anchor="w").pack(fill="x")
            tk.Label(box, text=source, bg=PANEL, fg=MUTED, font=(FONT, 7), anchor="w", wraplength=180,
                     justify="left").pack(fill="x")
            if action:
                for w in (box, v):
                    w.bind("<Button-1>", lambda _e, a=action: a())
        for c in range(7):
            self.sum_grid.columnconfigure(c, weight=1)
        sev = {}
        sub = {}
        for r in issues:
            if r["status"] != "failed":
                continue
            sev[r["severity"]] = sev.get(r["severity"], 0) + 1
            sub[r["subsystem"]] = sub.get(r["subsystem"], 0) + 1
        self.sum_sev.set("Defectos por gravedad", [(k, sev.get(k, 0), k) for k in store.SEVERITIES])
        self.sum_sub.set("Defectos por subsistema", sorted(((k, v, ACCENT) for k, v in sub.items()),
                                                           key=lambda x: -x[1]))
        st = {}
        for r in rows:
            st[r["status"]] = st.get(r["status"], 0) + 1
        self.sum_status.set("Escenarios por resultado", [(k, v, k) for k, v in sorted(st.items())])
        src = "metrics.json" if m.ok else ("summary.json" if s.ok else "no disponible")
        mrows = [{"metric": k, "value": json.dumps(v, ensure_ascii=False) if isinstance(v, dict) else v,
                  "source": src} for k, v in sorted(metrics.items())]
        bench = u.benchmark()
        if bench.ok and isinstance(bench.value, dict):
            name = Path(bench.source).name
            mrows += [{"metric": f"{name}: {k}", "value": json.dumps(v, ensure_ascii=False)
                       if isinstance(v, (dict, list)) else v, "source": name} for k, v in sorted(bench.value.items())]
        self.sum_metrics.set_rows(mrows)

    # ------------------------------------------------------------------ runs
    def _build_runs(self, f):
        bar, self.runs_sub = self.header(f, "Ejecuciones", "un escenario ejecutado por fila (results.jsonl)")
        button(bar, "Comparar 2 escenarios", self.compare_selected_scenarios).pack(side="right")
        button(bar, "Exportar vista (CSV)", lambda: self.export_table(self.runs_table, "ejecuciones")).pack(
            side="right", padx=4)
        button(bar, "Limpiar filtros", self.clear_run_filters).pack(side="right")
        filt = tk.Frame(f, bg=BG)
        filt.pack(fill="x", pady=2)
        self.run_filters = {}
        for key, width in (("status", 11), ("category", 13), ("family", 12), ("subsystem", 16),
                           ("generator_version", 8)):
            label(filt, key).pack(side="left", padx=(6, 2))
            cb = ttk.Combobox(filt, width=width, state="readonly", values=["(todos)"])
            cb.current(0)
            cb.bind("<<ComboboxSelected>>", lambda _e: self._apply_run_filters())
            cb.pack(side="left")
            self.run_filters[key] = cb
        self.run_text = {}
        for key, width in (("issue", 12), ("tag", 12), ("feature", 18), ("seed", 7), ("ms_min", 6), ("ms_max", 6)):
            label(filt, key).pack(side="left", padx=(6, 2))
            e = entry(filt, width)
            e.pack(side="left")
            e.bind("<KeyRelease>", lambda _e: self._apply_run_filters())
            self.run_text[key] = e
        self.verified_only = tk.BooleanVar(value=False)
        tk.Checkbutton(filt, text="solo verificados", variable=self.verified_only, command=self._apply_run_filters,
                       bg=BG, fg=FG, selectcolor=PANEL2, activebackground=BG, font=(FONT, 9)).pack(side="left")
        label(f, "La fecha es por informe (summary.started_at); results.jsonl no registra hora por escenario.",
              fg=UNKNOWN, size=8).pack(anchor="w")
        self.runs_table = Table(f, [
            ("order", "#", 46, "e"), ("scenario_id", "Escenario", 300, "w"), ("family", "Familia", 92, "w"),
            ("category", "Categoría", 100, "w"), ("status", "Resultado", 80, "w"),
            ("nativa_status", "NativaX", 70, "w"), ("reference_status", "Chromium", 70, "w"),
            ("subsystems", "Subsistemas", 180, "w"), ("total_ms", "ms", 64, "e"), ("seed", "Semilla", 70, "e"),
            ("assertions", "Aserc.", 50, "e"), ("actions", "Acc.", 44, "e"), ("findings", "Hallazgos", 64, "e"),
            ("primary", "Prim.", 46, "e"), ("errors", "Errores", 52, "e"), ("issues", "Defectos", 220, "w"),
            ("engine", "Motor JS", 64, "w"), ("generator_version", "Gen.", 50, "w")],
            tag_key="status", multi=True, on_open=lambda r: self.open_scenario(r["scenario_id"]))
        self.runs_table.pack(fill="both", expand=True)
        self._pending_run_filter = {}

    def _fill_runs(self):
        if not self.need_unit("runs"):
            return
        rows = self.unit.rows()
        for r in rows:
            r["_search"] = " ".join(r["tags"])
        self.runs_table.set_rows(rows)
        for key, cb in self.run_filters.items():
            values = sorted({v for r in rows for v in (r[key] if isinstance(r.get(key), list) else [r.get(key)])
                             if v is not None}, key=str)
            cb.configure(values=["(todos)", *map(str, values)])
            want = self._pending_run_filter.get(key)
            cb.set(str(want) if want is not None else "(todos)")
        if "verified" in self._pending_run_filter:
            self.verified_only.set(True)
        self._pending_run_filter = {}
        self._apply_run_filters()
        self.runs_sub.configure(text=f"{len(rows):,} escenarios ejecutados en {self.unit.meta.name}")

    def _apply_run_filters(self):
        sel = {k: cb.get() for k, cb in self.run_filters.items() if cb.get() != "(todos)"}
        txt = {k: e.get().strip() for k, e in self.run_text.items() if e.get().strip()}
        verified = self.verified_only.get()

        def ok(r):
            for k, v in sel.items():
                val = r.get(k)
                if isinstance(val, list):
                    if v not in val:
                        return False
                elif str(val) != v:
                    return False
            if "issue" in txt and not any(txt["issue"].upper() in i for i in r["issues"]):
                return False
            if "tag" in txt and not any(txt["tag"] in t for t in r["tags"]):
                return False
            if "feature" in txt and not any(txt["feature"] in ft for ft in r["_features"]):
                return False
            if "seed" in txt and str(r.get("seed")) != txt["seed"]:
                return False
            ms = r.get("total_ms")
            try:
                if "ms_min" in txt and (ms is None or ms < float(txt["ms_min"])):
                    return False
                if "ms_max" in txt and (ms is None or ms > float(txt["ms_max"])):
                    return False
            except ValueError:
                pass
            if verified and not (r["nativa_status"] == "ok" and r["reference_status"] == "ok"):
                return False
            return True
        self.runs_table.set_predicate(ok)

    def clear_run_filters(self):
        for cb in self.run_filters.values():
            cb.set("(todos)")
        for e in self.run_text.values():
            e.delete(0, "end")
        self.verified_only.set(False)
        self._apply_run_filters()

    def open_runs(self, **filters):
        if "runs" in self.built:
            self.clear_run_filters()
        feature = filters.pop("feature", None)
        self._pending_run_filter = dict(filters)
        self.show("runs")
        if feature:
            self.run_text["feature"].delete(0, "end")
            self.run_text["feature"].insert(0, feature)
            self._apply_run_filters()

    def compare_selected_scenarios(self):
        rows = self.runs_table.selected_rows()
        if len(rows) != 2:
            messagebox.showinfo("Comparar", "Selecciona exactamente dos escenarios (Ctrl+clic).")
            return
        a = self.unit.scenario(rows[0]["scenario_id"]) or {}
        b = self.unit.scenario(rows[1]["scenario_id"]) or {}
        self.show_diff(a.get("scenario"), b.get("scenario"),
                       f"{rows[0]['scenario_id']} → {rows[1]['scenario_id']} ({self.unit.meta.name})",
                       jump_unit=self.unit, jump_scenario=rows[1]["scenario_id"])

    # --------------------------------------------------------------- catalog
    def _build_catalog(self, f):
        self.header(f, "Catálogo de pantallas", "escenarios ejecutados de este informe por familia y categoría")
        self.cat_note = label(f, "", fg=UNKNOWN, size=8, anchor="w", justify="left")
        self.cat_note.pack(fill="x")
        self.cat_tree = ttk.Treeview(f, columns=("count", "failed", "passed", "ms"), show="tree headings")
        for k, t, w in (("count", "Escenarios", 90), ("failed", "Con defectos", 90), ("passed", "Sin defectos", 90),
                        ("ms", "ms medio", 80)):
            self.cat_tree.heading(k, text=t)
            self.cat_tree.column(k, width=w, anchor="e")
        self.cat_tree.column("#0", width=420)
        self.cat_tree.pack(fill="both", expand=True)
        self.cat_tree.bind("<Double-1>", self._catalog_open)

    def _fill_catalog(self):
        if not self.need_unit("catalog"):
            return
        t = self.cat_tree
        t.delete(*t.get_children())
        groups: dict = {}
        for r in self.unit.rows():
            groups.setdefault(r["family"], {}).setdefault(r["category"], []).append(r)
        for fam, cats in sorted(groups.items(), key=lambda x: str(x[0])):
            allr = [r for v in cats.values() for r in v]
            node = t.insert("", "end", iid=f"f::{fam}", text=f"{fam}", open=True, values=self._cat_vals(allr))
            for cat, rs in sorted(cats.items(), key=lambda x: str(x[0])):
                t.insert(node, "end", iid=f"c::{fam}::{cat}", text=f"{cat}", values=self._cat_vals(rs))
        m = (self.unit.metrics().value or {}) if self.unit.metrics().ok else {}
        self.cat_note.configure(text=(
            f"Generados {fmt(m.get('generated'))} · rechazados {fmt(m.get('rejected'))}. Los candidatos "
            "generados pero no ejecutados (y los rechazados) no se guardan uno a uno: el motor solo registra "
            "sus contadores y, si existe, sus decisiones en selection.jsonl (ver «Algoritmo»). Doble clic abre "
            "las ejecuciones filtradas."))

    @staticmethod
    def _cat_vals(rows):
        ms = [r["total_ms"] for r in rows if r["total_ms"] is not None]
        return (len(rows), sum(1 for r in rows if r["status"] == "failed"),
                sum(1 for r in rows if r["status"] == "passed"),
                fmt(sum(ms) / len(ms), 0) if ms else "—")

    def _catalog_open(self, _e=None):
        sel = self.cat_tree.selection()
        if not sel:
            return
        parts = sel[0].split("::")
        if parts[0] == "f":
            self.open_runs(family=parts[1])
        else:
            self.open_runs(family=parts[1], category=parts[2])

    # ------------------------------------------------------------- inspector
    def _build_inspector(self, f):
        bar, self.ins_sub = self.header(f, "Inspector de escenario", "")
        button(bar, "Abrir escenario JSON…", self.open_scenario_file).pack(side="right")
        self.ins_parent_btn = button(bar, "Ir al padre (mutación)", self.open_parent_scenario)
        self.ins_parent_btn.pack(side="right", padx=4)
        panes = tk.PanedWindow(f, orient="horizontal", bg=BG, sashwidth=5)
        panes.pack(fill="both", expand=True)
        left = tk.Frame(panes, bg=BG)
        panes.add(left, minsize=240, width=320)
        label(left, "Árbol de componentes", fg=FG, bold=True).pack(anchor="w")
        self.comp_tree = ttk.Treeview(left, columns=("type",), show="tree headings")
        self.comp_tree.heading("type", text="Tipo")
        self.comp_tree.column("type", width=90)
        self.comp_tree.column("#0", width=200)
        self.comp_tree.pack(fill="both", expand=True)
        self.comp_tree.bind("<<TreeviewSelect>>", self._comp_selected)
        self.comp_tree.bind("<<TreeviewOpen>>", self._comp_open)
        mid = ttk.Notebook(panes)
        panes.add(mid, minsize=380, width=620)
        self.ins_json = JsonView(mid)
        self.ins_json.text.bind("<ButtonRelease-1>", self._json_clicked)
        mid.add(self.ins_json, text="JSON original")
        self.ins_html = tk.Text(mid, bg=PANEL, fg=FG, font=(MONO, 9), wrap="none")
        mid.add(self.ins_html, text="HTML compilado")
        lay = tk.Frame(mid, bg=PANEL)
        mid.add(lay, text="Disposición medida")
        lbar = tk.Frame(lay, bg=PANEL)
        lbar.pack(fill="x")
        label(lbar, "Estado", bg=PANEL).pack(side="left")
        self.ins_state = ttk.Combobox(lbar, width=26, state="readonly")
        self.ins_state.pack(side="left", padx=4)
        self.ins_state.bind("<<ComboboxSelected>>", lambda _e: (self._draw_layout(), self._fill_props()))
        label(lbar, "■ Chromium (referencia)", fg="#39c5cf", bg=PANEL).pack(side="left", padx=6)
        label(lbar, "■ NativaX", fg="#f0883e", bg=PANEL).pack(side="left")
        self.layout_canvas = tk.Canvas(lay, bg="#0d1117", highlightthickness=0)
        self.layout_canvas.pack(fill="both", expand=True)
        self.layout_canvas.bind("<Configure>", lambda _e: self._draw_layout())
        label(lay, "Rectángulos medidos por la sonda en cada motor (no es una captura de píxeles; el arnés de "
                   "auditoría no guarda capturas).", fg=UNKNOWN, size=8, bg=PANEL).pack(anchor="w")
        self.ins_obs_n = JsonView(mid)
        mid.add(self.ins_obs_n, text="Observación NativaX")
        self.ins_obs_c = JsonView(mid)
        mid.add(self.ins_obs_c, text="Observación Chromium")
        self.ins_findings = Table(mid, [("kind", "Tipo", 80, "w"), ("primary", "Primario", 60, "c"),
                                        ("state", "Estado", 110, "w"), ("element_id", "Elemento", 110, "w"),
                                        ("property", "Propiedad", 120, "w"), ("message", "Mensaje", 320, "w"),
                                        ("issue", "Defecto", 100, "w")],
                                  on_open=lambda r: r.get("issue") and self.open_issue(r["issue"]))
        mid.add(self.ins_findings, text="Hallazgos")
        right = tk.Frame(panes, bg=PANEL)
        panes.add(right, minsize=300, width=420)
        canvas = tk.Canvas(right, bg=PANEL, highlightthickness=0)
        sb = ttk.Scrollbar(right, orient="vertical", command=canvas.yview)
        self.props_frame = tk.Frame(canvas, bg=PANEL)
        self.props_frame.bind("<Configure>", lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=self.props_frame, anchor="nw")
        canvas.configure(yscrollcommand=sb.set)
        canvas.pack(side="left", fill="both", expand=True)
        sb.pack(side="left", fill="y")
        self.ins_node_path = None
        self.ins_data = None

    def open_scenario(self, scenario_id, path=None, unit=None):
        unit = unit or self.unit
        raw = unit.scenario(scenario_id) if unit else None
        if raw is None:
            messagebox.showinfo("Inspector", f"El escenario {scenario_id} no está en este informe.")
            return
        self.scenario_ref = {"unit": unit, "raw": raw, "focus": path}
        self.show("inspector")

    def open_scenario_file(self):
        p = filedialog.askopenfilename(initialdir=str(ROOT / "tools" / "audit" / "regressions"),
                                       filetypes=[("JSON", "*.json")])
        if not p:
            return
        try:
            data = json.loads(Path(p).read_text())
        except (OSError, ValueError) as error:
            messagebox.showerror("Inspector", f"No se pudo leer {p}: {error}")
            return
        self.scenario_ref = {"unit": None, "raw": {"scenario": data, "comparison": None, "file": p}, "focus": None}
        self.show("inspector")

    def open_parent_scenario(self):
        ref = self.scenario_ref
        if not ref:
            return
        parent = ((ref["raw"].get("scenario") or {}).get("source") or {}).get("parent")
        if parent and ref.get("unit") and ref["unit"].scenario(parent):
            self.open_scenario(parent, unit=ref["unit"])
        else:
            messagebox.showinfo("Inspector", f"El padre «{parent}» no está registrado en este informe."
                                if parent else "Este escenario no tiene padre registrado.")

    def _fill_inspector(self):
        ref = self.scenario_ref
        t = self.comp_tree
        t.delete(*t.get_children())
        for w in self.props_frame.winfo_children():
            w.destroy()
        if not ref:
            self.ins_sub.configure(text="abre un escenario desde Ejecuciones, un defecto o la búsqueda")
            return
        scen = ref["raw"].get("scenario") or {}
        unit = ref.get("unit")
        origin = ref["raw"].get("file") or (f"{unit.meta.name}" + (
            f" · incluido en {ref['raw']['embedded_in']}" if ref["raw"].get("embedded_in") else ""))
        self.ins_sub.configure(text=f"{scen.get('scenario_id')} · {origin}")
        self.ins_json.show(scen, title=scen.get("scenario_id", ""))
        self.ins_html.delete("1.0", "end")
        try:
            self.ins_html.insert("1.0", compile_screen(scen))
        except Exception as error:  # noqa: BLE001 - invalid scenarios still deserve inspection
            self.ins_html.insert("1.0", f"No compilable con nxaudit/compile.py: {error}")
        self.obs = None
        if unit is not None:
            obs = unit.observations()
            self.obs = obs.value.get(scen.get("scenario_id")) if obs.value else None
            if self.obs is None:
                self.obs_note = obs.error or "observación no registrada (informe anterior a observations.jsonl.gz o caso embebido)"
        n = (self.obs or {}).get("nativa")
        c = (self.obs or {}).get("chrome")
        if n is not None:
            self.ins_obs_n.show(n, "estados medidos en NativaX")
        else:
            self.ins_obs_n.show({"no_disponible": getattr(self, "obs_note", "sin observación")})
        if c is not None:
            self.ins_obs_c.show(c, "estados medidos en Chromium")
        else:
            self.ins_obs_c.show({"no_disponible": getattr(self, "obs_note", "sin observación")})
        states = [s.get("after") for s in (n or {}).get("states") or []]
        self.ins_state.configure(values=states or ["(sin estados)"])
        self.ins_state.current(0)
        idx = unit.fingerprint_index() if unit else {}
        from nxaudit.diagnose import fingerprint as fp
        comp = ref["raw"].get("comparison") or {}
        self.ins_findings.set_rows([{**f, "issue": idx.get(fp(f)) if f.get("primary", True) else None}
                                    for f in comp.get("findings") or []])
        self.ins_nodes = {}
        screen = scen.get("screen")
        if isinstance(screen, dict):
            self._insert_comp("", "screen", screen)
        focus = ref.get("focus") or "screen"
        self.select_node(focus)
        self._draw_layout()

    def _insert_comp(self, parent, path, node, depth=0):
        self.ins_nodes[path] = node
        kids = node.get("children") or []
        iid = self.comp_tree.insert(parent, "end", iid=path, open=depth < 2,
                                    text=f"{node.get('id', '«sin id»')}", values=(node.get("type", "—"),))
        if depth < 2 or len(kids) <= 0:
            for i, k in enumerate(kids):
                if isinstance(k, dict):
                    self._insert_comp(iid, f"{path}.children[{i}]", k, depth + 1)
        elif kids:
            self.comp_tree.insert(iid, "end", iid=path + "::ph", text="…")
        return iid

    def _comp_open(self, _e=None):
        item = self.comp_tree.focus()
        if self.comp_tree.exists(item + "::ph"):
            self.comp_tree.delete(item + "::ph")
            node = self.ins_nodes[item]
            for i, k in enumerate(node.get("children") or []):
                if isinstance(k, dict):
                    self._insert_comp(item, f"{item}.children[{i}]", k, 2)

    def select_node(self, path):
        """Selects a node by structural path, expanding lazily."""
        if path is None:
            return
        parts = ["screen"]
        rest = path[len("screen"):]
        while rest.startswith(".children["):
            end = rest.index("]") + 1
            parts.append(parts[-1] + rest[:end])
            rest = rest[end:]
        for p in parts[:-1]:
            if self.comp_tree.exists(p):
                self.comp_tree.item(p, open=True)
                self.comp_tree.focus(p)
                self._comp_open()
        if self.comp_tree.exists(path):
            self.comp_tree.selection_set(path)
            self.comp_tree.see(path)
        else:
            self.ins_json.highlight("$." + path)

    def _comp_selected(self, _e=None):
        sel = self.comp_tree.selection()
        if not sel or sel[0].endswith("::ph"):
            return
        self.ins_node_path = sel[0]
        self.ins_json.highlight("$." + sel[0])
        self._fill_props()
        self._draw_layout()

    def _json_clicked(self, _e=None):
        t = self.ins_json.text
        offset = int(t.count("1.0", "insert", "chars")[0]) if t.count("1.0", "insert", "chars") else 0
        best = None
        for path, (a, b) in self.ins_json.spans.items():
            if a <= offset <= b and path.startswith("$.screen") and (best is None or b - a < best[1]):
                best = (path, b - a)
        if best:
            node = jsondiff.to_nx_path(best[0])
            if node and self.comp_tree.exists(node) and node != self.ins_node_path:
                self.comp_tree.selection_set(node)
                self.comp_tree.see(node)

    def _probe_of(self, which, state):
        obs = (self.obs or {}).get(which) or {}
        for s in obs.get("states") or []:
            if s.get("after") == state:
                return s.get("probe") or {}
        return {}

    def _fill_props(self):
        for w in self.props_frame.winfo_children():
            w.destroy()
        path = self.ins_node_path
        node = self.ins_nodes.get(path) if path else None
        if node is None:
            return
        scen = (self.scenario_ref["raw"].get("scenario") or {})
        state = self.ins_state.get()

        def section(title):
            label(self.props_frame, title, fg=ACCENT, bold=True, bg=PANEL).pack(anchor="w", padx=6, pady=(8, 1))

        def kv(pairs):
            k = KeyValue(self.props_frame)
            k.set(pairs)
            k.pack(fill="x")

        row = tk.Frame(self.props_frame, bg=PANEL)
        row.pack(fill="x")
        label(row, path, fg=FG, mono=True, bg=PANEL, wraplength=360, justify="left").pack(side="left", padx=6)
        button(row, "Copiar ruta", lambda: copy(self.tk, path)).pack(side="right")
        nid = node.get("id")
        section("Nodo")
        kv([("id", nid if "id" in node else None), ("tipo", node.get("type")),
            ("html", (COMPONENTS.get(node.get("type")) or {}).get("tag")),
            ("texto", repr(node["text"]) if "text" in node else None),
            ("atributos", json.dumps(node["attrs"], ensure_ascii=False) if "attrs" in node else None),
            ("hijos", len(node.get("children") or [])),
            ("padre", path.rsplit(".children[", 1)[0] if ".children[" in path else None)])
        section("Estilo declarado (valor tal cual · clase en el catálogo)")
        style_ = node.get("style")
        if style_ is None:
            label(self.props_frame, "sin «style» (ausente, no vacío)", fg=UNKNOWN, bg=PANEL).pack(anchor="w", padx=8)
        else:
            kv([(k, f"{v!r}  · {value_class(k, v)}") for k, v in style_.items()] or [("(objeto vacío)", "{}")])
        n_el = next((e for e in self._probe_of("nativa", state).get("elements") or [] if e.get("id") == nid), None)
        c_el = next((e for e in self._probe_of("chrome", state).get("elements") or [] if e.get("id") == nid), None)
        section(f"Medido en el estado «{state}»")
        if n_el is None and c_el is None:
            label(self.props_frame, getattr(self, "obs_note", "sin observación para este nodo"), fg=UNKNOWN,
                  bg=PANEL, wraplength=380, justify="left").pack(anchor="w", padx=8)
        else:
            t = Table(self.props_frame, [("prop", "Propiedad", 150, "w"), ("chrome", "Chromium", 120, "w"),
                                         ("nativa", "NativaX", 120, "w"), ("same", "=", 30, "c")],
                      page_size=100, height=12)
            rows = []
            for key in ("rect", "client", "scroll", "text", "value", "checked"):
                a, b = (c_el or {}).get(key, "∅"), (n_el or {}).get(key, "∅")
                rows.append({"prop": key, "chrome": a, "nativa": b, "same": "✓" if a == b else "✗"})
            props = sorted(set((c_el or {}).get("styles", {})) | set((n_el or {}).get("styles", {})))
            from nxaudit.compare import same as same_value
            for p in props:
                a = (c_el or {}).get("styles", {}).get(p)
                b = (n_el or {}).get("styles", {}).get(p)
                rows.append({"prop": p, "chrome": a, "nativa": b, "same": "✓" if same_value(p, a, b) else "✗"})
            t.set_rows(rows)
            t.pack(fill="x", padx=4)
        section("Eventos, acciones y aserciones")
        handlers = node.get("on")
        kv([("manejadores", json.dumps(handlers, ensure_ascii=False) if handlers else None),
            ("acciones sobre el nodo", "; ".join(f"{i}:{a.get('op')}" for i, a in enumerate(scen.get("actions") or [])
                                                if a.get("target") == nid) or None),
            ("aserciones", "; ".join(f"{a.get('id')} {a.get('property')} {a.get('operator')} {a.get('expected')!r}"
                                     for a in scen.get("assertions") or [] if a.get("target") == nid) or None)])
        comp = self.scenario_ref["raw"].get("comparison") or {}
        mine = [f for f in comp.get("findings") or [] if f.get("element_id") == nid]
        section(f"Hallazgos sobre este nodo ({len(mine)})")
        for f in mine[:30]:
            label(self.props_frame, f"{'●' if f.get('primary', True) else '○'} {f.get('kind')} · {f.get('state')} · "
                                    f"{f.get('property')} — {f.get('message')}",
                  fg=STATUS_COLORS.get(f.get("severity"), FG), bg=PANEL, wraplength=380, justify="left",
                  size=8).pack(anchor="w", padx=8)
        src = scen.get("source") or {}
        section("Origen y mutaciones")
        kv([("tipo de origen", src.get("kind")), ("generador", src.get("generator")),
            ("versión", src.get("generator_version")), ("padre", src.get("parent")),
            ("semilla", scen.get("seed") if "seed" in scen else None),
            ("mutaciones", json.dumps(src.get("mutations"), ensure_ascii=False) if src.get("mutations") else None)])

    def _draw_layout(self):
        cv = self.layout_canvas
        cv.delete("all")
        state = self.ins_state.get() if hasattr(self, "ins_state") else None
        c = self._probe_of("chrome", state).get("elements") or []
        n = self._probe_of("nativa", state).get("elements") or []
        if not c and not n:
            cv.create_text(20, 20, anchor="nw", fill=UNKNOWN, text=getattr(self, "obs_note", "sin observación"))
            return
        vw = max([e["rect"][0] + e["rect"][2] for e in c + n] + [1])
        vh = max([e["rect"][1] + e["rect"][3] for e in c + n] + [1])
        w, h = max(cv.winfo_width(), 200), max(cv.winfo_height(), 200)
        k = min((w - 20) / vw, (h - 20) / vh, 2.0)
        sel_id = (self.ins_nodes.get(self.ins_node_path) or {}).get("id") if self.ins_node_path else None
        for els, color, dash in ((c, "#39c5cf", ()), (n, "#f0883e", (3, 2))):
            for e in els:
                x, y, ew, eh = e["rect"]
                width = 3 if e.get("id") == sel_id else 1
                cv.create_rectangle(10 + x * k, 10 + y * k, 10 + (x + ew) * k, 10 + (y + eh) * k,
                                    outline=color, dash=dash, width=width)
        cv.create_text(w - 8, h - 8, anchor="se", fill=MUTED, text=f"escala {k:.2f} · {vw:.0f}×{vh:.0f} CSS px")

    # ---------------------------------------------------------------- issues
    def _build_issues(self, f):
        bar, self.iss_sub = self.header(f, "Centro de defectos",
                                        "orden del motor: gravedad y luego ocurrencias (no calcula otra prioridad)")
        button(bar, "Exportar vista (CSV)", lambda: self.export_table(self.iss_table, "defectos")).pack(side="right")
        filt = tk.Frame(f, bg=BG)
        filt.pack(fill="x")
        self.iss_filters = {}
        for key, width in (("severity", 9), ("status", 13), ("kind", 11), ("subsystem", 15), ("novelty", 10),
                           ("reproducible", 6), ("minimized", 6), ("confidence", 8), ("root_cause", 11)):
            label(filt, key).pack(side="left", padx=(4, 1))
            cb = ttk.Combobox(filt, width=width, state="readonly", values=["(todos)"])
            cb.current(0)
            cb.bind("<<ComboboxSelected>>", lambda _e: self._apply_issue_filters())
            cb.pack(side="left")
            self.iss_filters[key] = cb
        label(filt, "agrupar").pack(side="left", padx=(8, 1))
        self.iss_group = ttk.Combobox(filt, width=12, state="readonly",
                                      values=["(sin agrupar)", "kind_group", "subsystem", "component", "property"])
        self.iss_group.current(0)
        self.iss_group.bind("<<ComboboxSelected>>", lambda _e: self._fill_issues())
        self.iss_group.pack(side="left")
        self.iss_table = Table(f, [
            ("issue_id", "Issue", 100, "w"), ("severity", "Gravedad", 66, "w"), ("status", "Estado", 96, "w"),
            ("root_cause", "Causa", 82, "w"), ("kind", "Tipo", 80, "w"), ("subsystem", "Subsistema", 110, "w"),
            ("stage", "Etapa", 110, "w"), ("component", "Componente", 140, "w"), ("property", "Propiedad", 120, "w"),
            ("count", "Ocurr.", 54, "e"), ("scenarios", "Escen.", 50, "e"), ("reproducible", "Repro", 50, "c"),
            ("minimized", "Min.", 40, "c"), ("min_size", "Tamaño", 70, "c"), ("confidence", "Certeza", 60, "w"),
            ("novelty", "Novedad", 74, "w"), ("first_seen", "1.ª vez (ledger)", 150, "w"),
            ("ledger_status", "Ledger", 60, "w"), ("message", "Descripción (determinista)", 420, "w")],
            tag_key="severity", on_open=lambda r: self.open_issue(r["issue_id"]) if "issue_id" in r and
            not r.get("_group") else self._group_open(r))
        self.iss_table.pack(fill="both", expand=True)
        self._pending_issue_filter = {}

    def _ledger(self, unit):
        home = store.home_of(unit.path)
        if home is None:
            return {}, None
        got = store.read_json(home / "ledger.json")
        return (got.value or {}) if got.ok else {}, home

    def _fill_issues(self):
        if not self.need_unit("issues"):
            return
        ledger, home = self._ledger(self.unit)
        rows = []
        broken = 0
        for r in self.unit.issue_rows():
            if "error" in r:
                broken += 1
                rows.append({"issue_id": r["issue_id"], "message": f"informe ilegible: {r['error']}",
                             "severity": None})
                continue
            entry_ = ledger.get(r["issue_id"]) or {}
            rows.append({**r, "first_seen": entry_.get("first_seen"), "ledger_status": entry_.get("status")})
        for key, cb in self.iss_filters.items():
            vals = sorted({fmt(r.get(key)) for r in rows})
            cb.configure(values=["(todos)", *vals])
            want = self._pending_issue_filter.get(key, "(todos)")
            cb.set(fmt(want) if want != "(todos)" else "(todos)")
        self._pending_issue_filter = {}
        group = self.iss_group.get()
        if group != "(sin agrupar)":
            groups = {}
            for r in rows:
                g = groups.setdefault(r.get(group) or "—", {"issue_id": r.get(group) or "—", "_group": group,
                                                          "count": 0, "scenarios": 0, "severity": "info",
                                                          "message": ""})
                g["scenarios"] += 1
                g["count"] += r.get("count") or 0
                if store.SEVERITIES.index(r.get("severity") or "info") < store.SEVERITIES.index(g["severity"]):
                    g["severity"] = r["severity"]
                g["message"] = f"{g['scenarios']} defectos agrupados por {group}"
            rows = sorted(groups.values(), key=lambda g: -g["count"])
        self.iss_table.set_rows(rows)
        self._apply_issue_filters()
        self.iss_sub.configure(text=f"{len(rows)} filas · {broken} informes de defecto ilegibles · "
                                    f"ledger: {home or 'no encontrado'}")

    def _group_open(self, r):
        self.iss_group.current(0)
        self._pending_issue_filter = {r["_group"]: r["issue_id"]} if r["_group"] in self.iss_filters else {}
        self._fill_issues()
        if r["_group"] not in self.iss_filters:
            self.iss_table.search_var.set(r["issue_id"])

    def _apply_issue_filters(self):
        sel = {k: cb.get() for k, cb in self.iss_filters.items() if cb.get() != "(todos)"}
        self.iss_table.set_predicate(lambda r: r.get("_group") or all(fmt(r.get(k)) == v for k, v in sel.items()))

    def open_issues(self, **filters):
        self._pending_issue_filter = filters
        if "issues" in self.built:
            self.iss_group.current(0)
        self.show("issues")

    # ----------------------------------------------------------------- issue
    def open_issue(self, issue_id, unit=None):
        if unit is not None and unit is not self.unit:
            self.open_unit(unit.path, section="summary")
        self.issue_id = issue_id
        self.show("issue")

    def _build_issue(self, f):
        bar, self.issue_sub = self.header(f, "Defecto", "")
        self.issue_actions = bar
        self.issue_nb = ttk.Notebook(f)
        self.issue_nb.pack(fill="both", expand=True)
        self.issue_tabs = {}
        for key, text in (("summary", "A · Resumen"), ("location", "B · Localización"),
                          ("repro", "C · Reproducción"), ("evidence", "D · Evidencias"),
                          ("cause", "E · Causa raíz"), ("fix", "F · Corrección y regresión"),
                          ("brief", "Instrucciones (plantilla determinista)"), ("json", "JSON original")):
            fr = tk.Frame(self.issue_nb, bg=PANEL)
            self.issue_nb.add(fr, text=text)
            self.issue_tabs[key] = fr

    def _clear(self, frame):
        for w in frame.winfo_children():
            w.destroy()

    def _scroll(self, frame):
        canvas = tk.Canvas(frame, bg=PANEL, highlightthickness=0)
        sb = ttk.Scrollbar(frame, orient="vertical", command=canvas.yview)
        inner = tk.Frame(canvas, bg=PANEL)
        inner.bind("<Configure>", lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
        win = canvas.create_window((0, 0), window=inner, anchor="nw")
        canvas.bind("<Configure>", lambda e: canvas.itemconfigure(win, width=e.width))
        canvas.configure(yscrollcommand=sb.set)
        canvas.pack(side="left", fill="both", expand=True)
        sb.pack(side="left", fill="y")
        return inner

    def _fill_issue(self):
        if not self.need_unit("issue"):
            return
        for w in list(self.issue_actions.winfo_children())[2:]:
            w.destroy()
        for fr in self.issue_tabs.values():
            self._clear(fr)
        if not self.issue_id:
            self.issue_sub.configure(text="abre un defecto desde el Centro de defectos")
            return
        got = self.unit.issues().get(self.issue_id)
        if got is None or not got.ok:
            self.issue_sub.configure(text=f"{self.issue_id}: {got.error if got else 'no está en este informe'}",
                                     fg=RED)
            return
        r = got.value
        c = r.get("classification") or {}
        loc = r.get("location") or {}
        rep = r.get("reproduction") or {}
        ev = r.get("evidence") or {}
        rc = r.get("root_cause") or {}
        inv = r.get("investigation") or {}
        ver = r.get("verification") or {}
        self.issue_sub.configure(text=f"{r.get('issue_id')} · {self.unit.meta.name} · {got.source}", fg=MUTED)
        bar = self.issue_actions
        button(bar, "Copiar JSON", lambda: copy(self.tk, json.dumps(r, indent=2, ensure_ascii=False))).pack(
            side="right")
        button(bar, "Promover a regresión", lambda: self.engine(["promote", got.source],
                                                                f"promover {self.issue_id}")).pack(side="right", padx=2)
        vb = button(bar, "Verificar corrección", lambda: self.engine(["verify", self.issue_id],
                                                                     f"verificar {self.issue_id}", confirm=True))
        vb.pack(side="right", padx=2)
        if not self._is_main_latest(self.unit):
            vb.configure(state="disabled")
            label(bar, "verificar solo actúa sobre .audit/latest", fg=UNKNOWN, size=8).pack(side="right")
        button(bar, "Reproducir (replay)", lambda: self.engine(["replay", got.source], f"replay {self.issue_id}")).pack(
            side="right", padx=2)

        # A · Resumen
        inner = self._scroll(self.issue_tabs["summary"])
        k = KeyValue(inner)
        k.set([("Qué falló", ev.get("message")), ("Debería", json.dumps(r.get("expected"), ensure_ascii=False)),
               ("Sucedió", json.dumps(r.get("actual"), ensure_ascii=False)),
               ("Diferencia", json.dumps(r.get("difference"), ensure_ascii=False)),
               ("Estado", r.get("status")), ("Gravedad", r.get("severity")), ("Novedad", r.get("novelty")),
               ("Certeza", (r.get("confidence") or {}).get("level")),
               ("Método de clasificación", (r.get("confidence") or {}).get("basis")),
               ("Tipo de oráculo", c.get("kind")), ("Subsistema", c.get("subsystem")), ("Etapa", c.get("stage")),
               ("Componente", c.get("component_type")), ("Tipos afectados", c.get("component_types")),
               ("Propiedad", c.get("property")), ("Firma", r.get("fingerprint")),
               ("Ocurrencias", (r.get("occurrences") or {}).get("count")),
               ("Familias", (r.get("occurrences") or {}).get("families")),
               ("Sistema", json.dumps({k2: v for k2, v in (r.get("system") or {}).items() if k2 != "environment"},
                                      ensure_ascii=False))])
        k.pack(fill="x", pady=4)
        occ = Table(inner, [("scenario_id", "Escenarios donde aparece", 520, "w")], page_size=50, height=8,
                    on_open=lambda row: self.open_scenario(row["scenario_id"]))
        occ.set_rows([{"scenario_id": s} for s in (r.get("occurrences") or {}).get("scenarios") or []])
        occ.pack(fill="x", padx=4)

        # B · Localización
        inner = self._scroll(self.issue_tabs["location"])
        k = KeyValue(inner)
        k.set([("Pantalla", loc.get("screen_id")), ("Escenario", r.get("scenario_id")),
               ("Elemento", loc.get("element_id")), ("Tipo", c.get("component_type")),
               ("Propiedad", c.get("property")), ("Ruta JSON", loc.get("json_path")),
               ("Ruta en el caso mínimo", loc.get("minimal_json_path")),
               ("Archivo fuente", loc.get("source_file")), ("Símbolo", loc.get("symbol")),
               ("Línea", loc.get("line")), ("Columna", None),
               ("Base de la ubicación", loc.get("basis") or "sin traza: el motor no confirma archivo ni línea")])
        k.pack(fill="x", pady=4)
        row = tk.Frame(inner, bg=PANEL)
        row.pack(fill="x", padx=6)
        button(row, "Ver elemento en el inspector", lambda: self.open_scenario(
            r.get("scenario_id"), path=loc.get("json_path"))).pack(side="left")
        if rep.get("minimal_scenario"):
            button(row, "Ver en el caso mínimo", lambda: self.open_scenario(
                rep["minimal_scenario"]["scenario_id"], path=loc.get("minimal_json_path"))).pack(side="left", padx=4)
        if loc.get("json_path"):
            button(row, "Copiar ruta JSON", lambda: copy(self.tk, loc["json_path"])).pack(side="left", padx=4)
        if loc.get("source_file") and (ROOT / loc["source_file"]).exists():
            button(row, f"Abrir {loc['source_file']}:{loc.get('line')}",
                   lambda: self.open_source(loc["source_file"], loc.get("line"))).pack(side="left", padx=4)
        label(inner, "Archivos a inspeccionar (cada uno con su base; «git grep» = coincidencia de búsqueda, "
                     "no causa)", fg=FG, bold=True, bg=PANEL).pack(anchor="w", padx=6, pady=(8, 0))
        files = Table(inner, [("file", "Archivo", 380, "w"), ("line", "Línea", 50, "e"),
                              ("basis", "Base", 230, "w"), ("match", "Coincidencia", 360, "w")],
                      page_size=50, height=8, on_open=lambda x: self.open_source(x["file"], x.get("line")))
        files.set_rows(inv.get("files_to_inspect") or [])
        files.pack(fill="x", padx=4)
        label(inner, "Dependencias y llamadas: el motor no registra grafo de llamadas; solo los marcos de la traza "
                     "(pestaña D).", fg=UNKNOWN, size=8, bg=PANEL).pack(anchor="w", padx=6)

        # C · Reproducción
        inner = self._scroll(self.issue_tabs["repro"])
        scen = rep.get("scenario") or {}
        summary_cfg = (self.unit.summary().value or {}).get("config") if self.unit.summary().ok else None
        k = KeyValue(inner)
        k.set([("Semilla", rep.get("seed")), ("Familia", rep.get("family")),
               ("Entorno", json.dumps(scen.get("environment"), ensure_ascii=False) if scen else None),
               ("Configuración de la ejecución", json.dumps(summary_cfg, ensure_ascii=False) if summary_cfg else None),
               ("Precondiciones", scen.get("preconditions") if scen.get("preconditions") else None),
               ("Aserción fallida", ev.get("assertion_id")),
               ("Reproducible al re-ejecutar", rep.get("reproducible")),
               ("Minimizado", rep.get("minimized")), ("Comando", rep.get("command"))])
        k.pack(fill="x", pady=4)
        row = tk.Frame(inner, bg=PANEL)
        row.pack(fill="x", padx=6)
        if rep.get("command"):
            button(row, "Copiar comando", lambda: copy(self.tk, rep["command"])).pack(side="left")
        label(inner, "Pasos", fg=FG, bold=True, bg=PANEL).pack(anchor="w", padx=6, pady=(6, 0))
        for i, step in enumerate(rep.get("steps") or []):
            label(inner, f"{i + 1}. {step}", fg=FG, bg=PANEL, wraplength=1100, justify="left", size=9).pack(
                anchor="w", padx=12)
        acts = Table(inner, [("i", "#", 30, "e"), ("op", "Acción", 70, "w"), ("target", "Objetivo", 120, "w"),
                             ("detail", "Detalle", 500, "w")], page_size=50, height=6)
        acts.set_rows([{"i": i, "op": a.get("op"), "target": a.get("target"),
                        "detail": json.dumps({k2: v for k2, v in a.items() if k2 not in ("op", "target")},
                                             ensure_ascii=False)} for i, a in enumerate(rep.get("actions") or [])])
        acts.pack(fill="x", padx=4, pady=4)
        mini = rep.get("minimization")
        label(inner, "Minimización", fg=FG, bold=True, bg=PANEL).pack(anchor="w", padx=6)
        k = KeyValue(inner)
        k.set([(key, json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else v)
               for key, v in (mini or {}).items()] or [("registro", None)])
        k.pack(fill="x")
        if rep.get("minimal_scenario") and scen:
            button(inner, "Diferencias original → mínimo", lambda: self.show_diff(
                scen, rep["minimal_scenario"], f"{self.issue_id}: original → mínimo", jump_unit=self.unit,
                jump_scenario=rep["minimal_scenario"]["scenario_id"])).pack(anchor="w", padx=6, pady=4)
        label(inner, "Salida de la última acción del motor en esta sesión", fg=FG, bold=True, bg=PANEL).pack(
            anchor="w", padx=6)
        self.issue_log = tk.Text(inner, bg="#070a0f", fg=MUTED, height=8, font=(MONO, 8))
        self.issue_log.pack(fill="x", padx=6, pady=4)

        # D · Evidencias
        tab = self.issue_tabs["evidence"]
        nb = ttk.Notebook(tab)
        nb.pack(fill="both", expand=True)
        fr = tk.Frame(nb, bg=PANEL)
        nb.add(fr, text="Esperado / observado")
        two = tk.PanedWindow(fr, orient="horizontal", bg=PANEL)
        two.pack(fill="both", expand=True)
        a, b = JsonView(two, height=12), JsonView(two, height=12)
        two.add(a)
        two.add(b)
        a.show(r.get("expected"), "esperado (referencia)")
        b.show(r.get("actual"), "observado (NativaX)")
        dv = DiffView(fr)
        dv.pack(fill="both", expand=True)
        dv.set(jsondiff.diff(r.get("expected"), r.get("actual")) if isinstance(r.get("expected"), (dict, list))
               else ([] if r.get("expected") == r.get("actual") else
                     [{"path": "$", "op": "changed", "before": r.get("expected"), "after": r.get("actual")}]),
               "diferencia estructural esperado → observado")
        fr = tk.Frame(nb, bg=PANEL)
        nb.add(fr, text="Traza")
        txt = tk.Text(fr, bg=PANEL, fg=FG, font=(MONO, 9))
        txt.pack(fill="both", expand=True)
        txt.insert("1.0", "\n".join(ev.get("stack") or []) or "Sin traza: el hallazgo no viene de una excepción.")
        fr = tk.Frame(nb, bg=PANEL)
        nb.add(fr, text="Hallazgo (formato original)")
        jv = JsonView(fr)
        jv.pack(fill="both", expand=True)
        jv.show(ev.get("finding"), "evidence.finding")
        fr = tk.Frame(nb, bg=PANEL)
        nb.add(fr, text="Artefactos")
        arts = Table(fr, [("path", "Artefacto", 520, "w"), ("exists", "Existe", 60, "c")], page_size=50)
        base = self.unit.path
        arts.set_rows([{"path": p, "exists": (base / "issues" / Path(p).name).exists() or (ROOT / p).exists()}
                       for p in ev.get("artifacts") or []])
        arts.pack(fill="both", expand=True)
        label(fr, f"Hallazgos consecuentes atribuidos: {fmt(ev.get('consequential_findings'))}. El arnés de "
                  "auditoría no genera capturas de pantalla.", fg=UNKNOWN, size=8, bg=PANEL).pack(anchor="w")

        # E · Causa raíz
        inner = self._scroll(self.issue_tabs["cause"])
        finding = ev.get("finding") or {}

        def block(title, color, lines):
            label(inner, title, fg=color, bold=True, bg=PANEL).pack(anchor="w", padx=6, pady=(8, 0))
            if not lines:
                label(inner, "— ninguno registrado —", fg=UNKNOWN, bg=PANEL).pack(anchor="w", padx=14)
            for line in lines:
                label(inner, f"• {line}", fg=FG, bg=PANEL, wraplength=1100, justify="left").pack(anchor="w", padx=14)

        block("Hechos observados (medidos)", "#3fb950", [
            f"estado {finding.get('state')}: esperado {json.dumps(finding.get('expected'), ensure_ascii=False)}",
            f"observado {json.dumps(finding.get('actual'), ensure_ascii=False)}",
            f"elemento {finding.get('element_id')} en {finding.get('json_path')}"])
        block("Inferencias del algoritmo (reglas deterministas)", ACCENT, [
            f"etapa «{c.get('stage')}» por el oráculo «{c.get('kind')}»",
            f"primario (primera divergencia): {finding.get('primary')}",
            *[f"consecuencia descartada: {x}" for x in finding.get("consequence_of") or []],
            f"certeza: {(r.get('confidence') or {}).get('level')} — {(r.get('confidence') or {}).get('basis')}"])
        for status, title, color in (("confirmed", "Causas confirmadas (con traza)", RED),
                                     ("unconfirmed", "Hipótesis sin confirmar", YELLOW),
                                     ("rejected", "Hipótesis descartadas", UNKNOWN)):
            hyps = [h for h in rc.get("hypotheses") or [] if h.get("status") == status]
            label(inner, f"{title} ({len(hyps)})", fg=color, bold=True, bg=PANEL).pack(anchor="w", padx=6,
                                                                                     pady=(8, 0))
            for h in hyps:
                label(inner, h.get("statement"), fg=FG, bg=PANEL, wraplength=1100, justify="left").pack(
                    anchor="w", padx=14)
                for e in h.get("evidence_for") or []:
                    label(inner, f"  a favor: {e}", fg="#3fb950", bg=PANEL, wraplength=1080, justify="left",
                          size=8).pack(anchor="w", padx=22)
                for e in h.get("evidence_against") or []:
                    label(inner, f"  en contra: {e}", fg=RED, bg=PANEL, wraplength=1080, justify="left",
                          size=8).pack(anchor="w", padx=22)
        block("Comprobaciones pendientes", MUTED, (inv.get("next_checks") or []) +
              [f"descartar: {x}" for x in rc.get("alternatives_to_rule_out") or []])

        # F · Corrección y regresión
        inner = self._scroll(self.issue_tabs["fix"])
        ledger, home = self._ledger(self.unit)
        k = KeyValue(inner)
        k.set([("Corrección aplicada", ver.get("fix_applied")),
               ("Reproducción tras corregir", ver.get("reproduction_passed")),
               ("Regresiones", ver.get("regression_passed")), ("Verificado", ver.get("verified_at")),
               ("Commit de la verificación", ver.get("git_commit")),
               ("Estado en el ledger", (ledger.get(self.issue_id) or {}).get("status")),
               ("Corregido en (ledger)", (ledger.get(self.issue_id) or {}).get("fixed_at")),
               ("Cambios asociados", None), ("Ledger", str(home) if home else None)])
        k.pack(fill="x", pady=4)
        label(inner, "El motor no registra qué cambios de código corrigen un defecto; solo el resultado de "
                     "«verificar».", fg=UNKNOWN, size=8, bg=PANEL).pack(anchor="w", padx=6)
        block("Requisitos de la corrección", FG, r.get("fix_requirements") or [])
        block("Restricciones", FG, r.get("constraints") or [])
        block("Pruebas de regresión", FG, r.get("regression_tests") or [])
        block("Criterios de aceptación", FG, r.get("acceptance_criteria") or [])

        # brief + json
        md = self.unit.issue_markdown(self.issue_id)
        t = tk.Text(self.issue_tabs["brief"], bg=PANEL, fg=FG, font=(MONO, 9), wrap="word")
        t.pack(fill="both", expand=True)
        t.insert("1.0", md.value if md.ok else f"no disponible: {md.error}")
        t.insert("1.0", "Texto generado por plantilla determinista (nxaudit/report.py), sin LLM.\n\n")
        t.configure(state="disabled")
        jv = JsonView(self.issue_tabs["json"])
        jv.pack(fill="both", expand=True)
        jv.show(r, got.source)

    @staticmethod
    def _is_main_latest(unit) -> bool:
        """`audit.py verify` acts on .audit/latest only: the report must be that
        copy or the run it duplicates."""
        latest = store.ROOT / ".audit" / "latest"
        if unit.path.resolve() == latest.resolve():
            return True
        got = store.read_json(latest / "summary.json")
        return bool(got.ok and unit.meta.run_id and (got.value or {}).get("run_id") == unit.meta.run_id
                    and store.home_of(unit.path) == store.ROOT / ".audit")

    def open_source(self, rel, line=None):
        p = ROOT / rel
        if not p.exists():
            messagebox.showinfo("Código", f"{rel} no existe en este checkout.")
            return
        if shutil.which("code"):
            subprocess.Popen(["code", "-g", f"{p}:{line or 1}"])
        else:
            subprocess.Popen(["xdg-open", str(p)])

    # ---------------------------------------------------------------- traces
    def _build_traces(self, f):
        bar, self.tr_sub = self.header(f, "Trazas y evidencias", "todos los hallazgos de este informe")
        filt = tk.Frame(f, bg=BG)
        filt.pack(fill="x")
        label(filt, "tipo").pack(side="left")
        self.tr_kind = ttk.Combobox(filt, width=14, state="readonly", values=["(todos)"])
        self.tr_kind.current(0)
        self.tr_kind.bind("<<ComboboxSelected>>", lambda _e: self._apply_tr())
        self.tr_kind.pack(side="left", padx=4)
        self.tr_stack = tk.BooleanVar(value=False)
        tk.Checkbutton(filt, text="solo con traza", variable=self.tr_stack, command=self._apply_tr, bg=BG, fg=FG,
                       selectcolor=PANEL2, activebackground=BG).pack(side="left")
        self.tr_primary = tk.BooleanVar(value=False)
        tk.Checkbutton(filt, text="solo primarios", variable=self.tr_primary, command=self._apply_tr, bg=BG, fg=FG,
                       selectcolor=PANEL2, activebackground=BG).pack(side="left")
        panes = tk.PanedWindow(f, orient="vertical", bg=BG, sashwidth=5)
        panes.pack(fill="both", expand=True)
        self.tr_table = Table(panes, [
            ("scenario_id", "Escenario", 260, "w"), ("kind", "Tipo", 80, "w"), ("stage", "Etapa", 100, "w"),
            ("severity", "Grav.", 60, "w"), ("primary", "Prim.", 44, "c"), ("state", "Estado", 110, "w"),
            ("element_id", "Elemento", 100, "w"), ("property", "Propiedad", 110, "w"),
            ("has_stack", "Traza", 44, "c"), ("message", "Mensaje", 420, "w")],
            tag_key="severity", on_select=self._tr_selected,
            on_open=lambda r: self.open_scenario(r["scenario_id"], path=r.get("json_path")))
        panes.add(self.tr_table, height=420)
        self.tr_json = JsonView(panes, height=14)
        panes.add(self.tr_json)

    def _fill_traces(self):
        if not self.need_unit("traces"):
            return
        rows = []
        for r in self.unit.raw_results().value or []:
            sid = (r.get("scenario") or {}).get("scenario_id")
            for f in (r.get("comparison") or {}).get("findings") or []:
                rows.append({**f, "scenario_id": sid, "has_stack": bool(f.get("stack"))})
            for note in (r.get("comparison") or {}).get("notes") or []:
                rows.append({"scenario_id": sid, "kind": "nota", "message": note, "severity": "info",
                             "primary": False, "has_stack": False})
        self.tr_rows = rows
        self.tr_kind.configure(values=["(todos)", *sorted({r["kind"] for r in rows})])
        self.tr_table.set_rows(rows)
        self._apply_tr()
        self.tr_sub.configure(text=f"{len(rows):,} hallazgos y notas en {self.unit.meta.name}")

    def _apply_tr(self):
        k = self.tr_kind.get()
        self.tr_table.set_predicate(lambda r: (k == "(todos)" or r["kind"] == k)
                                    and (not self.tr_stack.get() or r["has_stack"])
                                    and (not self.tr_primary.get() or r.get("primary")))

    def _tr_selected(self, r):
        self.tr_json.show({k: v for k, v in r.items() if k != "has_stack"}, "hallazgo tal como lo guardó el motor")

    # ---------------------------------------------------------------- matrix
    def _build_matrix(self, f):
        self.header(f, "Componentes y propiedades", "escenarios ejecutados con cada combinación y defectos asociados")
        self.mx_table = Table(f, [("component", "Componente", 140, "w"), ("property", "Propiedad", 180, "w"),
                                  ("executed", "Escenarios", 90, "e"), ("issues", "Defectos", 80, "e"),
                                  ("catalog", "En catálogo", 90, "c")],
                              on_open=lambda r: self.open_runs(feature=f"prop_on:{r['component']}:{r['property']}"
                                                               if r["property"] != "*" else f"type:{r['component']}"))
        self.mx_table.pack(fill="both", expand=True)
        label(f, "Doble clic: ejecuciones con esa combinación. «*» = componente sin propiedad concreta. "
                 "Las combinaciones con 0 escenarios son las que existen en el catálogo y no se ejercitaron.",
              fg=UNKNOWN, size=8).pack(anchor="w")

    def _fill_matrix(self):
        if not self.need_unit("matrix"):
            return
        m = self.unit.component_property_matrix()
        keys = set(m["executed"]) | set(m["issues"])
        for comp, spec in COMPONENTS.items():
            if not spec["executable"]:
                continue
            keys.add((comp, "*"))
            for prop in PROPERTIES:
                keys.add((comp, prop))
        rows = [{"component": c, "property": p, "executed": m["executed"].get((c, p), 0),
                 "issues": m["issues"].get((c, p), 0),
                 "catalog": c in COMPONENTS and (p == "*" or p in PROPERTIES)} for c, p in sorted(keys)]
        self.mx_table.set_rows(rows)

    # -------------------------------------------------------------- coverage
    def _build_coverage(self, f):
        self.header(f, "Cobertura", "generada / ejecutada / verificada frente al universo del catálogo")
        self.cov_chart = BarChart(f, height=230, unit=" %")
        self.cov_chart.pack(fill="x")
        self.cov_table = Table(f, [("dimension", "Dimensión", 220, "w"), ("generated", "Generada", 90, "e"),
                                   ("executed", "Ejecutada", 90, "e"), ("verified", "Verificada", 90, "e"),
                                   ("universe", "Universo", 90, "e"), ("pct", "% verificada", 90, "e")],
                               page_size=50, height=10)
        self.cov_table.pack(fill="x")
        label(f, "Rasgos ejecutados (coverage.json) y huecos", fg=FG, bold=True).pack(anchor="w", pady=(6, 0))
        self.cov_feats = Table(f, [("feature", "Rasgo", 420, "w"), ("state", "Estado", 120, "w")],
                               tag_key="state", on_open=lambda r: self.open_runs(feature=r["feature"])
                               if r["state"] == "ejecutado" else None)
        self.cov_feats.pack(fill="both", expand=True)

    def _fill_coverage(self):
        if not self.need_unit("coverage"):
            return
        cov = self.unit.coverage()
        table = (cov.value or {}).get("table") if cov.ok else None
        if table is None and self.unit.summary().ok:
            table = (self.unit.summary().value or {}).get("coverage")
        table = table or {}
        rows = []
        for d, row in table.items():
            pct = (100 * row["verified"] / row["universe"]) if row.get("universe") else None
            rows.append({"dimension": d, **row, "pct": pct})
        self.cov_table.set_rows(rows)
        self.cov_chart.set("Cobertura verificada (% del universo; «no medido» si no hay universo)",
                           [(r["dimension"], r["pct"], "#3fb950") for r in rows])
        executed = set((cov.value or {}).get("executed_features") or []) if cov.ok else set()
        feats = [{"feature": x, "state": "ejecutado"} for x in sorted(executed)]
        for comp, spec in COMPONENTS.items():
            if spec["executable"] and f"type:{comp}" not in executed:
                feats.append({"feature": f"type:{comp}", "state": "no ejercitado"})
        for prop in PROPERTIES:
            if f"prop:{prop}" not in executed:
                feats.append({"feature": f"prop:{prop}", "state": "no ejercitado"})
        if not cov.ok:
            feats.insert(0, {"feature": f"coverage.json {cov.error}", "state": "unknown"})
        self.cov_feats.set_rows(feats)

    # ------------------------------------------------------------- algorithm
    def _build_algorithm(self, f):
        self.header(f, "Algoritmo de exploración", "estrategias, decisiones registradas y evolución de la búsqueda")
        top = tk.Frame(f, bg=BG)
        top.pack(fill="x")
        self.alg_cfg = KeyValue(top, bg=BG)
        self.alg_cfg.pack(side="left", fill="x", expand=True)
        self.alg_curve = LineChart(f, height=200)
        self.alg_curve.pack(fill="x", pady=4)
        self.alg_strat = Table(f, [("family", "Estrategia (familia)", 140, "w"), ("executed", "Ejecutados", 80, "e"),
                                   ("mean_ms", "ms medio", 80, "e"), ("first_found", "Firmas nuevas", 90, "e"),
                                   ("yield", "Firmas/escenario", 100, "e")], page_size=30, height=7,
                               on_open=lambda r: self.open_runs(family=r["family"]))
        self.alg_strat.pack(fill="x")
        self.alg_note = label(f, "", fg=UNKNOWN, size=8, anchor="w", justify="left", wraplength=1200)
        self.alg_note.pack(fill="x")
        filt = tk.Frame(f, bg=BG)
        filt.pack(fill="x")
        label(filt, "decisiones de selection.jsonl").pack(side="left")
        self.alg_chosen = ttk.Combobox(filt, values=["(todas)", "elegidas", "descartadas"], width=12,
                                       state="readonly")
        self.alg_chosen.current(0)
        self.alg_chosen.bind("<<ComboboxSelected>>", lambda _e: self._apply_alg())
        self.alg_chosen.pack(side="left", padx=4)
        label(filt, "ronda").pack(side="left")
        self.alg_round = ttk.Combobox(filt, values=["(todas)"], width=6, state="readonly")
        self.alg_round.current(0)
        self.alg_round.bind("<<ComboboxSelected>>", lambda _e: self._apply_alg())
        self.alg_round.pack(side="left", padx=4)
        self.alg_sel = Table(f, [
            ("round", "Ronda", 50, "e"), ("rank", "Rango", 50, "e"), ("scenario_id", "Escenario", 280, "w"),
            ("family", "Familia", 100, "w"), ("novelty", "Novedad", 70, "e"), ("new_features", "Rasgos nuevos", 90, "e"),
            ("ucb", "UCB", 60, "e"), ("bonus", "Bonus", 50, "e"), ("score", "Puntuación", 70, "e"),
            ("chosen", "Elegido", 54, "c"), ("reason", "Razón", 300, "w")],
            on_open=lambda r: r["chosen"] and self.open_scenario(r["scenario_id"]))
        self.alg_sel.pack(fill="both", expand=True)

    def _fill_algorithm(self):
        if not self.need_unit("algorithm"):
            return
        s = (self.unit.summary().value or {}) if self.unit.summary().ok else {}
        cfg = s.get("config") or {}
        self.alg_cfg.set([("presupuesto", cfg.get("budget")), ("lote", cfg.get("batch")),
                          ("estrategias activas", cfg.get("families")), ("cuota máx. por familia", cfg.get("max_share")),
                          ("minimizar los primeros", cfg.get("minimize_top")), ("semilla", s.get("seed")),
                          ("fórmula", "puntuación = novedad + UCB(familia) [+2 si regresión]; 1 hueco por familia "
                                      "por ronda; tope max_share por familia (nxaudit/explore.py)")])
        curve = self.unit.discovery_curve()
        fams = self.unit.discovery_by_family()
        palette = ["#7aa2ff", "#3fb950", "#d29922", "#f85149", "#a371f7", "#39c5cf", "#f0883e", "#db61a2"]
        series = [("todas las familias", curve, "#e6edf3")] + [
            (fam, pts, palette[i % len(palette)]) for i, (fam, pts) in enumerate(sorted(fams.items()))]
        self.alg_curve.set("Firmas únicas acumuladas por orden de ejecución (derivado de results.jsonl)", series,
                           xlabel="escenario ejecutado", ylabel="firmas")
        self.alg_strat.set_rows([{"family": k, **v} for k, v in (s.get("strategies") or {}).items()])
        sel = self.unit.selection()
        rows = sel.value or []
        self.alg_rows = rows
        if not rows:
            self.alg_note.configure(text=(
                "selection.jsonl no disponible en este informe: se generó antes de que el motor registrara las "
                "decisiones por candidato. Sin él no hay puntuaciones, cola ni descartes que mostrar; las "
                "ejecuciones nuevas sí lo registran (round, rank, novelty, ucb, bonus, score, chosen, reason)."))
        else:
            chosen = sum(1 for r in rows if r.get("chosen"))
            self.alg_note.configure(text=f"{len(rows):,} decisiones registradas · {chosen:,} elegidas · "
                                         f"{len(rows) - chosen:,} descartadas · {sel.skipped_lines} líneas corruptas")
        self.alg_round.configure(values=["(todas)", *sorted({str(r.get("round")) for r in rows}, key=int)])
        self.alg_sel.set_rows(rows)
        self._apply_alg()

    def _apply_alg(self):
        c, rnd = self.alg_chosen.get(), self.alg_round.get()
        self.alg_sel.set_predicate(lambda r: (c == "(todas)" or bool(r.get("chosen")) == (c == "elegidas"))
                                   and (rnd == "(todas)" or str(r.get("round")) == rnd))

    # --------------------------------------------------------------- compare
    def _build_compare(self, f):
        self.header(f, "Comparación", "vista explícita de dos informes; cada cifra indica su origen")
        pick = tk.Frame(f, bg=BG)
        pick.pack(fill="x")
        self.cmp_a = ttk.Combobox(pick, width=70, state="readonly")
        self.cmp_b = ttk.Combobox(pick, width=70, state="readonly")
        label(pick, "A").pack(side="left")
        self.cmp_a.pack(side="left", padx=4)
        label(pick, "B").pack(side="left")
        self.cmp_b.pack(side="left", padx=4)
        button(pick, "Comparar", self._run_compare, accent=True).pack(side="left", padx=6)
        self.cmp_banner = label(f, "", fg=YELLOW, anchor="w", justify="left", wraplength=1300)
        self.cmp_banner.pack(fill="x")
        self.cmp_nb = ttk.Notebook(f)
        self.cmp_nb.pack(fill="both", expand=True)
        self.cmp_metrics = Table(self.cmp_nb, [("metric", "Métrica", 240, "w"), ("a", "A", 140, "e"),
                                               ("b", "B", 140, "e"), ("delta", "B − A", 120, "e")], page_size=200)
        self.cmp_nb.add(self.cmp_metrics, text="Métricas")
        fr = tk.Frame(self.cmp_nb, bg=BG)
        self.cmp_nb.add(fr, text="Defectos")
        self.cmp_issues = Table(fr, [("issue_id", "Issue", 110, "w"), ("where", "Presencia", 220, "w"),
                                     ("severity", "Gravedad", 70, "w"), ("kind", "Tipo", 90, "w"),
                                     ("message", "Descripción", 520, "w")], tag_key="severity",
                                on_open=self._cmp_issue_open)
        self.cmp_issues.pack(fill="both", expand=True)
        label(fr, "«solo en A» = no apareció en B: corregido o no ejercitado en B (el motor no distingue sin "
                  "re-ejecutar el escenario). Doble clic: diferencia del mismo defecto en A y B, o abre el defecto.",
              fg=UNKNOWN, size=8).pack(anchor="w")
        self.cmp_cov = Table(self.cmp_nb, [("dimension", "Dimensión", 220, "w"), ("a", "A verificada", 100, "e"),
                                           ("b", "B verificada", 100, "e"), ("universe", "Universo", 90, "e")])
        self.cmp_nb.add(self.cmp_cov, text="Cobertura")
        self.cmp_strat = Table(self.cmp_nb, [("family", "Familia", 140, "w"), ("a_executed", "A ejec.", 80, "e"),
                                             ("b_executed", "B ejec.", 80, "e"), ("a_yield", "A firmas/esc.", 100, "e"),
                                             ("b_yield", "B firmas/esc.", 100, "e")])
        self.cmp_nb.add(self.cmp_strat, text="Estrategias")
        self.diff_view = DiffView(self.cmp_nb, on_jump=self._diff_jump)
        self.cmp_nb.add(self.diff_view, text="Diferencias JSON")
        self._diff_ctx = None

    def _fill_compare(self):
        units = [str(p) for p in store.discover(self.report_root)]
        labels = [self._rel(p) for p in units]
        self._cmp_units = dict(zip(labels, units))
        self.cmp_a.configure(values=labels)
        self.cmp_b.configure(values=labels)
        if self.compare_pair:
            self.cmp_a.set(self._rel(self.compare_pair[0]))
            self.cmp_b.set(self._rel(self.compare_pair[1]))
            self.compare_pair = []
            self._run_compare()

    def _run_compare(self):
        a, b = self._cmp_units.get(self.cmp_a.get()), self._cmp_units.get(self.cmp_b.get())
        if not a or not b:
            return
        ua, ub = self.get_unit(a), self.get_unit(b)
        res = store.compare_units(ua, ub)
        self._cmp_res = (ua, ub)
        banner = f"A = {self._rel(a)}   ·   B = {self._rel(b)}\n"
        if res["config_diff"]:
            banner += ("Configuración o entorno distintos (" + ", ".join(
                f"{d['field']}: {fmt(d['a'])} → {fmt(d['b'])}" for d in res["config_diff"]) +
                "): una diferencia de métricas no es atribuible solo a un cambio de código.")
        else:
            banner += "Misma configuración, commit, versión del generador y motor registrados."
        banner += (f"\nEscenarios compartidos {res['scenarios_shared']} · solo A {res['scenarios_only_a']} · "
                   f"solo B {res['scenarios_only_b']}.")
        self.cmp_banner.configure(text=banner, fg=YELLOW if res["config_diff"] else "#3fb950")
        self.cmp_metrics.set_rows(res["metrics"])
        ia = {r["issue_id"]: r for r in ua.issue_rows() if "error" not in r}
        ib = {r["issue_id"]: r for r in ub.issue_rows() if "error" not in r}
        rows = []
        for iid in res["issues_only_b"]:
            rows.append({**ib[iid], "where": "solo en B (nuevo en B)" + (" · regresión" if iid in res["regressions_b"]
                                                                         else "")})
        for iid in res["issues_only_a"]:
            rows.append({**ia[iid], "where": "solo en A (ausente en B)"})
        for iid in res["issues_both"]:
            rows.append({**ib[iid], "where": "en A y en B"})
        self.cmp_issues.set_rows(rows)
        self.cmp_cov.set_rows(res["coverage"])
        self.cmp_strat.set_rows(res["strategies"])

    def _cmp_issue_open(self, row):
        ua, ub = self._cmp_res
        ga, gb = ua.issues().get(row["issue_id"]), ub.issues().get(row["issue_id"])
        if ga and gb and ga.ok and gb.ok:
            self.show_diff(ga.value, gb.value, f"{row['issue_id']}: A={ua.meta.name} → B={ub.meta.name}")
        else:
            self.open_issue(row["issue_id"], unit=ub if gb else ua)

    def show_diff(self, a, b, title, jump_unit=None, jump_scenario=None):
        self._diff_ctx = (jump_unit, jump_scenario)
        self.show("compare")
        self.cmp_nb.select(self.diff_view)
        self.diff_view.set(jsondiff.diff(a, b), title)

    def _diff_jump(self, path):
        unit, sid = self._diff_ctx or (None, None)
        node = jsondiff.to_nx_path(path.replace("$.scenario", "$")) or jsondiff.to_nx_path(path)
        if unit and sid and node:
            self.open_scenario(sid, path=node, unit=unit)

    # -------------------------------------------------------------- minimize
    def _build_minimize(self, f):
        self.header(f, "Minimización y reproducción", "eficacia de la reducción y estado de reproducción por defecto")
        self.min_chart = BarChart(f, height=200, unit=" %")
        self.min_chart.pack(fill="x")
        panes = tk.PanedWindow(f, orient="vertical", bg=BG, sashwidth=5)
        panes.pack(fill="both", expand=True)
        self.min_table = Table(panes, [
            ("issue_id", "Issue", 100, "w"), ("severity", "Grav.", 60, "w"), ("reproducible", "Repro", 50, "c"),
            ("minimized", "Min.", 44, "c"), ("rounds", "Rondas", 56, "e"), ("start", "Inicio", 60, "e"),
            ("final", "Final", 60, "e"), ("reduction", "Reducción %", 84, "e"), ("one_minimal", "1-mínimo", 64, "c"),
            ("necessary", "Condiciones", 76, "e"), ("note", "Nota", 360, "w")],
            tag_key="severity", on_select=self._min_selected, on_open=lambda r: self.open_issue(r["issue_id"]))
        panes.add(self.min_table, height=300)
        self.min_detail = tk.Text(panes, bg=PANEL, fg=FG, font=(MONO, 9), height=10)
        panes.add(self.min_detail)

    def _fill_minimize(self):
        if not self.need_unit("minimize"):
            return
        rows = []
        self.min_reports = {}
        for iid, got in self.unit.issues().items():
            if not got.ok:
                continue
            rep = got.value.get("reproduction") or {}
            mini = rep.get("minimization") or {}
            self.min_reports[iid] = got.value
            start, final = mini.get("start_size"), mini.get("final_size")
            rows.append({"issue_id": iid, "severity": got.value.get("severity"),
                         "reproducible": rep.get("reproducible"), "minimized": rep.get("minimized"),
                         "rounds": mini.get("rounds"), "start": start, "final": final,
                         "reduction": (100 * (start - final) / start) if start and final is not None and
                         rep.get("minimized") else None,
                         "one_minimal": mini.get("one_minimal"),
                         "necessary": len(mini.get("necessary_conditions") or []) if mini else None,
                         "note": mini.get("note") or ("" if mini else "no se intentó (fuera de minimize_top o no "
                                                                      "reproducible)")})
        self.min_table.set_rows(rows)
        self.min_chart.set("Reducción del caso (% de unidades eliminadas)",
                           [(r["issue_id"], r["reduction"], "#3fb950") for r in rows if r["minimized"]])

    def _min_selected(self, row):
        rep = (self.min_reports.get(row["issue_id"]) or {}).get("reproduction") or {}
        mini = rep.get("minimization") or {}
        self.min_detail.delete("1.0", "end")
        lines = [f"{row['issue_id']}  comando: {rep.get('command')}", "", "Eliminado en cada ronda:"]
        lines += [f"  - {u.get('description')}" for u in mini.get("removed") or []] or ["  (nada)"]
        lines += ["", "Condiciones necesarias (quitar cualquiera pierde el defecto):"]
        lines += [f"  - {u.get('description')}" for u in mini.get("necessary_conditions") or []] or \
                 ["  (no registradas: el caso no llegó a 1-mínimo o no se minimizó)"]
        self.min_detail.insert("1.0", "\n".join(lines))

    # ------------------------------------------------------------------ perf
    def _build_perf(self, f):
        self.header(f, "Rendimiento y recursos", "tiempos del arnés NativaX por escenario (no son benchmarks)")
        self.perf_kv = KeyValue(f, bg=BG)
        self.perf_kv.pack(fill="x")
        row = tk.Frame(f, bg=BG)
        row.pack(fill="x")
        self.perf_hist = Histogram(row, height=230, on_click=None)
        self.perf_hist.pack(side="left", fill="x", expand=True, padx=2)
        self.perf_stage = BarChart(row, height=230, unit=" ms")
        self.perf_stage.pack(side="left", fill="x", expand=True, padx=2)
        self.perf_fam = Table(f, [("family", "Familia", 140, "w"), ("n", "n", 50, "e"), ("mean", "media ms", 80, "e"),
                                  ("p50", "p50", 70, "e"), ("p90", "p90", 70, "e"), ("p95", "p95", 70, "e"),
                                  ("p99", "p99", 70, "e")], page_size=40, height=7)
        self.perf_fam.pack(fill="x")
        bar = tk.Frame(f, bg=BG)
        bar.pack(fill="x", pady=4)
        button(bar, "Cargar RSS por escenario (observations.jsonl.gz)", self._load_rss).pack(side="left")
        self.perf_rss = Table(f, [("scenario_id", "Escenario", 300, "w"), ("before", "RSS antes KB", 100, "e"),
                                  ("after", "RSS después KB", 100, "e"), ("growth", "Crecimiento KB", 100, "e")],
                              on_open=lambda r: self.open_scenario(r["scenario_id"]))
        self.perf_rss.pack(fill="both", expand=True)

    def _fill_perf(self):
        if not self.need_unit("perf"):
            return
        d = self.unit.durations()
        m = (self.unit.metrics().value or {}) if self.unit.metrics().ok else {}
        self.perf_kv.set([("tiempo de pared total (s)", m.get("wall_s")), ("lotes", m.get("batches")),
                          ("escenarios con tiempo medido", f"{d['measured']} de {d['rows']}"),
                          ("p50 / p90 / p95 / p99 (ms)", " / ".join(fmt(d["total"][k], 0) for k in
                                                                     ("p50", "p90", "p95", "p99"))),
                          ("RSS máx. del arnés (MB)", m.get("max_rss_mb")),
                          ("ms medio por etiqueta", json.dumps(m.get("mean_ms_by_subsystem"))[:300]
                           if m.get("mean_ms_by_subsystem") else None)])
        self.perf_hist.set_values("Distribución de timings.total_ms", [r["total_ms"] for r in self.unit.rows()])
        sm = d["stage_mean"]
        self.perf_stage.set("Tiempo medio por etapa del arnés", [
            ("montaje (mount)", sm.get("mount_ms"), "#7aa2ff"), ("asentado (settle)", sm.get("settle_ms"), "#39c5cf"),
            ("acciones", sm.get("actions_ms"), "#d29922"), ("total", sm.get("total_ms"), "#3fb950")])
        self.perf_fam.set_rows([{"family": k, **v} for k, v in d["per_family"].items()])

    def _load_rss(self):
        self.set_status("leyendo observations.jsonl.gz …")
        obs = self.unit.observations()
        rows = []
        for sid, o in (obs.value or {}).items():
            rss = (o.get("nativa") or {}).get("rss_kb") or {}
            b, a = rss.get("before"), rss.get("after")
            rows.append({"scenario_id": sid, "before": b, "after": a,
                         "growth": a - b if isinstance(a, int) and isinstance(b, int) else None})
        self.perf_rss.set_rows(rows)
        self.set_status(f"{len(rows)} observaciones" + (f" · {obs.error}" if obs.error else ""))

    # ----------------------------------------------------------- regressions
    def _build_regressions(self, f):
        self.header(f, "Historial de regresiones", "ledger del motor y casos de regresión guardados")
        self.reg_note = label(f, "", fg=MUTED, anchor="w")
        self.reg_note.pack(fill="x")
        self.reg_ledger = Table(f, [("issue_id", "Issue", 110, "w"), ("status", "Estado", 70, "w"),
                                    ("severity", "Grav.", 70, "w"), ("kind", "Tipo", 90, "w"),
                                    ("subsystem", "Subsistema", 120, "w"), ("first_seen", "Primera vez", 190, "w"),
                                    ("last_seen", "Última vez", 190, "w"), ("fixed_at", "Corregido", 150, "w")],
                                tag_key="severity", height=12,
                                on_open=lambda r: self.unit and self.unit.issues().get(r["issue_id"]) and
                                self.open_issue(r["issue_id"]))
        self.reg_ledger.pack(fill="both", expand=True)
        label(f, "Casos en tools/audit/regressions/ (se ejecutan en cada auditoría)", fg=FG, bold=True).pack(anchor="w")
        self.reg_files = Table(f, [("file", "Archivo", 300, "w"), ("scenario_id", "Escenario", 300, "w"),
                                   ("objective", "Objetivo", 500, "w")], height=8, on_open=self._open_reg_file)
        self.reg_files.pack(fill="both", expand=True)

    def _fill_regressions(self):
        home = store.home_of(self.unit.path) if self.unit else store.ROOT / ".audit"
        got = store.read_json((home or Path("/nonexistent")) / "ledger.json")
        rows = [{"issue_id": k, **v} for k, v in (got.value or {}).items()] if got.ok else []
        self.reg_ledger.set_rows(rows)
        self.reg_note.configure(text=(f"ledger: {home}/ledger.json — registro del motor compartido por los informes de "
                                      f"esa carpeta ({len(rows)} entradas)") if got.ok else
                                f"ledger no disponible ({got.error})")
        reg = ROOT / "tools" / "audit" / "regressions"
        files = []
        for p in sorted(reg.glob("*.json")) if reg.exists() else []:
            g = store.read_json(p)
            v = g.value if g.ok else {}
            files.append({"file": p.name, "scenario_id": v.get("scenario_id") if v else f"ilegible: {g.error}",
                          "objective": v.get("objective") if v else None, "abs": str(p)})
        self.reg_files.set_rows(files)

    def _open_reg_file(self, row):
        g = store.read_json(Path(row["abs"]))
        if g.ok:
            self.scenario_ref = {"unit": None, "raw": {"scenario": g.value, "comparison": None, "file": row["abs"]},
                                 "focus": None}
            self.show("inspector")

    # ----------------------------------------------------------------- files
    def _build_files(self, f):
        bar, self.files_sub = self.header(f, "Archivos y exportación", "artefactos originales (solo lectura)")
        button(bar, "Exportar copia de los seleccionados…", self.export_files).pack(side="right")
        button(bar, "Abrir con el sistema", lambda: [subprocess.Popen(["xdg-open", r["abs"]])
                                                     for r in self.files_table.selected_rows()[:1]]).pack(
            side="right", padx=4)
        button(bar, "Copiar ruta", lambda: [copy(self.tk, r["abs"]) for r in self.files_table.selected_rows()[:1]]).pack(
            side="right")
        panes = tk.PanedWindow(f, orient="vertical", bg=BG, sashwidth=5)
        panes.pack(fill="both", expand=True)
        self.files_table = Table(panes, [("path", "Archivo", 520, "w"), ("size", "Bytes", 100, "e"),
                                         ("modified", "Modificado", 160, "w")], multi=True,
                                 on_select=self._file_preview)
        panes.add(self.files_table, height=320)
        self.files_view = JsonView(panes)
        panes.add(self.files_view)

    def _fill_files(self):
        if not self.need_unit("files"):
            return
        rows = self.unit.files()
        self.files_table.set_rows(rows)
        self.files_sub.configure(text=f"{len(rows)} archivos en {self.unit.path}")

    def _file_preview(self, row):
        p = Path(row["abs"])
        if p.suffix == ".json" and row["size"] < 20_000_000:
            g = store.read_json(p)
            self.files_view.show(g.value if g.ok else {"error": g.error}, row["path"])
        elif p.suffix in (".jsonl", ".gz"):
            g = store.read_jsonl(p, gz=p.suffix == ".gz")
            self.files_view.show({"lineas": len(g.value or []), "lineas_corruptas": g.skipped_lines,
                                  "error": g.error, "primeras_5": (g.value or [])[:5]}, row["path"])
        elif p.suffix in (".md", ".txt", ".html") and row["size"] < 5_000_000:
            self.files_view.show(p.read_text(encoding="utf-8", errors="replace"), row["path"])
        else:
            self.files_view.show({"vista_previa": "no disponible para este tipo", "bytes": row["size"]}, row["path"])

    def export_files(self):
        rows = self.files_table.selected_rows()
        if not rows:
            return
        dest = filedialog.askdirectory(title="Carpeta de destino (fuera del informe)")
        if not dest:
            return
        dest = Path(dest)
        if dest == self.unit.path or self.unit.path in dest.parents:
            messagebox.showerror("Exportar", "El destino está dentro del informe; elige otra carpeta.")
            return
        for r in rows:
            target = dest / self.unit.meta.name / r["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(r["abs"], target)
        self.set_status(f"{len(rows)} archivos copiados a {dest / self.unit.meta.name}")

    def export_table(self, table: Table, name):
        p = filedialog.asksaveasfilename(defaultextension=".csv", initialfile=f"{self.unit.meta.name}-{name}.csv",
                                         filetypes=[("CSV", "*.csv"), ("JSON", "*.json")])
        if not p:
            return
        if self.unit and Path(p).resolve().is_relative_to(self.unit.path.resolve()):
            messagebox.showerror("Exportar", "No se escribe dentro del informe.")
            return
        rows = [{k: v for k, v in r.items() if not k.startswith("_")} for r in table.view_rows]
        if p.endswith(".json"):
            Path(p).write_text(json.dumps(rows, indent=2, ensure_ascii=False, default=str))
        else:
            keys = [c[0] for c in table.columns]
            with open(p, "w", newline="") as fh:
                w = csv.DictWriter(fh, fieldnames=keys, extrasaction="ignore")
                w.writeheader()
                for r in rows:
                    w.writerow({k: fmt(r.get(k)) for k in keys})
        self.set_status(f"{len(rows)} filas exportadas a {p}")

    # --------------------------------------------------------------- execute
    def _build_execute(self, f):
        self.header(f, "Ejecutar el motor", "lanza tools/audit/audit.py; los informes nuevos aparecen en su carpeta")
        form = tk.Frame(f, bg=BG)
        form.pack(fill="x")
        self.exec_mode = ttk.Combobox(form, values=["run", "benchmark", "self-check"], width=12, state="readonly")
        self.exec_mode.current(0)
        self.exec_fields = {}
        label(form, "modo").grid(row=0, column=0, sticky="w")
        self.exec_mode.grid(row=0, column=1, sticky="w")
        for i, (key, default) in enumerate((("--budget", "200"), ("--batch", "40"), ("--seed", "1"),
                                            ("--minimize-top", "5"), ("--families", ""), ("--time-limit", ""))):
            label(form, key).grid(row=1 + i // 3, column=(i % 3) * 2, sticky="w", padx=(0, 4))
            e = entry(form, 16)
            e.insert(0, default)
            e.grid(row=1 + i // 3, column=(i % 3) * 2 + 1, sticky="w", pady=2)
            self.exec_fields[key] = e
        self.exec_norepro = tk.BooleanVar(value=False)
        tk.Checkbutton(form, text="--no-reproduce (solo run)", variable=self.exec_norepro, bg=BG, fg=FG,
                       selectcolor=PANEL2, activebackground=BG).grid(row=3, column=0, columnspan=2, sticky="w")
        bar = tk.Frame(f, bg=BG)
        bar.pack(fill="x", pady=4)
        button(bar, "▶ Ejecutar", self._exec_run, accent=True).pack(side="left")
        self.exec_stop = button(bar, "■ Detener", self.stop_engine)
        self.exec_stop.pack(side="left", padx=4)
        self.exec_state = label(bar, "inactivo")
        self.exec_state.pack(side="left", padx=8)
        self.exec_log = tk.Text(f, bg="#070a0f", fg=MUTED, font=(MONO, 9))
        self.exec_log.pack(fill="both", expand=True)

    def _fill_execute(self):
        pass

    def _exec_run(self):
        mode = self.exec_mode.get()
        args = [mode]
        allowed = {"run": ["--budget", "--batch", "--seed", "--minimize-top", "--families", "--time-limit"],
                   "benchmark": ["--budget", "--batch", "--seed", "--minimize-top"],
                   "self-check": ["--budget", "--batch", "--seed", "--minimize-top"]}[mode]
        for key in allowed:
            v = self.exec_fields[key].get().strip()
            if v:
                args += [key, v]
        if mode == "run" and self.exec_norepro.get():
            args.append("--no-reproduce")
        self.engine(args, f"audit.py {' '.join(args)}")

    def engine(self, args, label_text, confirm=False):
        if self.process is not None:
            messagebox.showinfo("Motor", "Ya hay una operación del motor en curso.")
            return
        if confirm and not messagebox.askyesno("Motor", f"{label_text}\n\nEsta operación del motor actualiza el "
                                                        "informe del defecto y el ledger. ¿Continuar?"):
            return
        cmd = [sys.executable, "-u", str(ROOT / "tools" / "audit" / "audit.py"), *args]
        try:
            self.process = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                            bufsize=1, start_new_session=True)
        except OSError as error:
            messagebox.showerror("Motor", str(error))
            return
        self._proc_label = label_text
        self._log(f"$ {' '.join(cmd)}\n")
        self.set_status(f"motor: {label_text} …", ACCENT)

        def reader(proc):
            for line in proc.stdout:
                self.proc_queue.put(line)
            proc.wait()
            self.proc_queue.put(None)
        threading.Thread(target=reader, args=(self.process,), daemon=True).start()

    def stop_engine(self):
        if self.process is not None:
            try:
                os.killpg(self.process.pid, 9)
            except OSError:
                pass

    def _log(self, text):
        for w in (getattr(self, "exec_log", None), getattr(self, "issue_log", None)):
            try:
                if w is not None and w.winfo_exists():
                    w.insert("end", text)
                    w.see("end")
            except tk.TclError:
                pass

    def _drain_proc(self):
        try:
            while True:
                line = self.proc_queue.get_nowait()
                if line is None:
                    code = self.process.returncode if self.process else None
                    self._log(f"[terminado con código {code}]\n")
                    self.set_status(f"motor: {self._proc_label} terminado (código {code})",
                                    "#3fb950" if code == 0 else RED)
                    if hasattr(self, "exec_state"):
                        self.exec_state.configure(text=f"terminado ({code})")
                    self.process = None
                    self.units.clear()
                    self._fill_tree()
                else:
                    self._log(line)
                    if hasattr(self, "exec_state"):
                        self.exec_state.configure(text=line.strip()[:120])
        except queue.Empty:
            pass
        self.tk.after(100, self._drain_proc)

    # ---------------------------------------------------------------- search
    def global_search(self):
        q = self.search_entry.get().strip()
        if not q:
            return
        units = [self.get_unit(p) for p in store.discover(self.folder)] if self.search_all.get() or not self.unit \
            else [self.unit]
        self.set_status(f"buscando «{q}» en {len(units)} informe(s) …")
        hits = store.global_search(units, q)
        win = tk.Toplevel(self.tk, bg=BG)
        win.title(f"Resultados: {q}")
        win.geometry("1000x520")
        label(win, f"{len(hits)} resultados para «{q}» (cada uno indica su informe)", fg=FG).pack(anchor="w", padx=6)
        t = Table(win, [("type", "Tipo", 80, "w"), ("id", "Identificador", 300, "w"), ("text", "Detalle", 300, "w"),
                        ("unit_rel", "Informe", 300, "w")],
                  on_open=lambda r: (win.destroy(), self._open_hit(r)))
        t.set_rows([{**h, "unit_rel": self._rel(h["unit"])} for h in hits])
        t.pack(fill="both", expand=True)
        t.tree.focus_set()
        self.set_status(f"{len(hits)} resultados")

    def _open_hit(self, h):
        unit = self.get_unit(h["unit"])
        if unit is not self.unit:
            self.open_unit(unit.path)
        if h["type"] == "defecto":
            self.open_issue(h["id"])
        elif h["type"] == "escenario":
            self.open_scenario(h["id"])


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", default=str(DEFAULT_ROOT), help="carpeta raíz de informes (por defecto .audit)")
    p.add_argument("--unit", help="informe que abrir al iniciar")
    args = p.parse_args(argv)
    root = tk.Tk()
    App(root, Path(args.root), Path(args.unit) if args.unit else None)
    root.mainloop()


if __name__ == "__main__":
    main()

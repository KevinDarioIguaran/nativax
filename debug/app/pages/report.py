"""Report workspace: one report at a time. Common tabs (Summary, Raw
evidence, History, Files) plus the dedicated tabs of the report's type
(debug/app/pages/workspaces/<type>.py)."""
from __future__ import annotations

import importlib
import json
import shutil
import subprocess
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

from debug.app.components.basic import KeyValue, button, copy, fmt, frame, label, scroll_frame, section
from debug.app.components.json_views import JsonTree
from debug.app.components.table import Table
from debug.styles import theme as t

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "debug" / "logic"))
import storage  # noqa: E402
import workspaces  # noqa: E402

WORKSPACES = {
    "visual_comparison": "visual", "performance": "performance", "memory": "records",
    "security": "records", "microbenchmarks": "records", "compatibility": "records",
    "bug_detection": "bug_detection", "engine_audit": "bug_detection",
}


class Page:
    def __init__(self, frm, app):
        self.app, self.frm = app, frm
        self.focus = None
        bar = frame(frm)
        bar.pack(fill="x")
        self.title = label(bar, "Report workspace", role="title", fg="text-primary")
        self.title.pack(side="left")
        self.sub = label(bar, "", role="code-small")
        self.sub.pack(side="left", padx=t.space("lg"))
        button(bar, "Copy path", lambda: self.app.state.current and copy(self.frm, self.app.state.current.path)).pack(
            side="right")
        button(bar, "Open folder", self.open_folder).pack(side="right", padx=t.space("sm"))
        self.nb = ttk.Notebook(frm)
        self.nb.pack(fill="both", expand=True)
        self.workspace = None

    def open_folder(self):
        ref = self.app.state.current
        if ref:
            target = Path(ref.path)
            subprocess.Popen(["xdg-open", str(target if target.is_dir() else target.parent)])

    def refresh(self):
        for tab in self.nb.tabs():
            self.nb.forget(tab)
        ref = self.app.state.current
        if ref is None:
            empty = frame(self.nb)
            label(empty, "No report open. Choose one in the Report explorer.", fg="status-unknown").pack(
                padx=t.space("xl"), pady=t.space("xl"))
            self.nb.add(empty, text="No report")
            self.title.configure(text="Report workspace")
            self.sub.configure(text="")
            return
        self.title.configure(text=f"{ref.type.replace('_', ' ').capitalize()} — {ref.id}")
        self.sub.configure(text=f"{ref.layout} · {ref.path}")
        self.app.set_status(f"loading {ref.id} …")
        module = WORKSPACES.get(ref.type)
        if module:
            ws = importlib.import_module(f"debug.app.pages.workspaces.{module}")
            self.workspace = ws.Workspace(self.nb, self.app, ref, focus=self.focus)
        self.focus = None
        self._summary_tab(ref)
        self._evidence_tab(ref)
        if ref.layout.startswith("run-manifest"):
            self._history_tab(ref)
        self._files_tab(ref)
        self.app.set_status(f"report {ref.id} open")

    # ------------------------------------------------------------- summary
    def _summary_tab(self, ref):
        tab = frame(self.nb, "surface-raised")
        self.nb.add(tab, text="Summary")
        inner = scroll_frame(tab)
        info = workspaces.common(ref)
        manifest = info["manifest"] or {}
        section(inner, "Identity")
        kv = KeyValue(inner)
        kv.set([("Report id", ref.id), ("Type", ref.type), ("Area", ref.area), ("Layout", ref.layout),
                ("Path", ref.path), ("Created / archived", ref.created_at), ("Status", ref.status),
                ("Health", ref.health), ("Engine", ref.engine), ("Code revision", ref.commit),
                ("Command", " ".join(manifest.get("argv") or []) or None),
                ("Source directory", manifest.get("source")),
                ("Lineage key", ref.lineage_key), ("Previous run in lineage", ref.previous)])
        kv.pack(fill="x")
        section(inner, "Outcome (as recorded by the engine)")
        kv = KeyValue(inner)
        kv.set([("Outcome", ref.summary or None)] + [(k, v) for k, v in (ref.counts or {}).items()])
        kv.pack(fill="x")
        section(inner, "Integrity")
        if info["verify"] is None:
            label(inner, "This layout carries no integrity record.", fg="status-unknown",
                  surface="surface-raised").pack(anchor="w", padx=t.space("xl"))
        elif not info["verify"]:
            label(inner, "Every archived file matches integrity.json (sha256 and size).", fg="status-ok",
                  surface="surface-raised").pack(anchor="w", padx=t.space("xl"))
        else:
            for problem in info["verify"]:
                label(inner, problem, fg="status-error", surface="surface-raised").pack(anchor="w", padx=t.space("xl"))
        section(inner, "Read problems")
        if ref.errors:
            for e in ref.errors:
                label(inner, e, fg="status-error", surface="surface-raised").pack(anchor="w", padx=t.space("xl"))
        else:
            label(inner, "none", fg="text-secondary", surface="surface-raised").pack(anchor="w", padx=t.space("xl"))
        if manifest.get("notes"):
            section(inner, "Notes")
            label(inner, manifest["notes"], fg="text-primary", surface="surface-raised", wraplength=1100,
                  justify="left").pack(anchor="w", padx=t.space("xl"))

    # ------------------------------------------------------------ evidence
    def _evidence_tab(self, ref):
        tab = frame(self.nb)
        self.nb.add(tab, text="Raw evidence")
        files = self._files(ref)
        json_files = [f for f in files if f["path"].endswith((".json", ".jsonl"))]
        bar = frame(tab)
        bar.pack(fill="x")
        label(bar, "File").pack(side="left")
        names = [f["path"] for f in json_files]
        self.ev_choice = ttk.Combobox(bar, values=names, width=90, state="readonly")
        self.ev_choice.pack(side="left", padx=t.space("sm"))
        tree = JsonTree(tab)
        tree.pack(fill="both", expand=True)

        def load(_e=None):
            name = self.ev_choice.get()
            path = Path(ref.path) / name if Path(ref.path).is_dir() else Path(ref.path).parent / name
            errors = []
            try:
                if name.endswith(".jsonl"):
                    rows = []
                    with path.open(encoding="utf-8") as fh:
                        for i, line in enumerate(fh):
                            if i >= 5000:
                                errors.append("display limited to the first 5000 lines")
                                break
                            try:
                                rows.append(json.loads(line))
                            except ValueError:
                                errors.append(f"line {i + 1}: invalid JSON")
                    doc = rows
                else:
                    doc = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, ValueError) as error:
                doc, errors = None, [f"cannot read {name}: {error}"]
            if name.endswith("manifest.json") and isinstance(doc, dict):
                errors += storage.check_manifest(doc)
            tree.show(doc, errors)
        self.ev_choice.bind("<<ComboboxSelected>>", load)
        if names:
            first = next((n for n in names if n.endswith(("manifest.json", ".summary.json"))), names[0])
            self.ev_choice.set(first)
            load()

    # ------------------------------------------------------------- history
    def _history_tab(self, ref):
        tab = frame(self.nb)
        self.nb.add(tab, text="History")
        bar = frame(tab)
        bar.pack(fill="x")
        label(bar, "Append-only entries under history/. Evidence is never edited.").pack(side="left")
        button(bar, "Add annotation…", lambda: self._annotate(ref)).pack(side="right")
        rows = storage.history(ref.path)
        table = Table(tab, [("file", "Entry", 330, "w"), ("kind", "Kind", 110, "w"),
                            ("created_at", "Created", 190, "w"), ("author", "Author", 220, "w"),
                            ("refs", "References", 240, "w"), ("data", "Data", 520, "w")],
                      status_key="kind", height=14)
        table.set_rows([{**h, "data": h.get("data") or h.get("error")} for h in rows])
        table.pack(fill="both", expand=True)

    def _annotate(self, ref):
        text = simpledialog.askstring("Annotation", "Annotation text (stored as a new history entry):",
                                      parent=self.frm)
        if not text:
            return
        storage.append_history(ref.path, "annotation", {"text": text}, author="debug app (user)")
        self.refresh()

    # --------------------------------------------------------------- files
    def _files(self, ref):
        base = Path(ref.path)
        if base.is_file():   # conformance summary: the unit is the summary + its JSONL
            out = [{"path": base.name, "bytes": base.stat().st_size, "abs": str(base)}]
            try:
                linked = json.loads(base.read_text()).get("resultsFile")
            except (OSError, ValueError):
                linked = None
            if linked and (base.parent / linked).exists():
                out.append({"path": linked, "bytes": (base.parent / linked).stat().st_size,
                            "abs": str(base.parent / linked)})
            return out
        integrity = {}
        try:
            for f in json.loads((base / "integrity.json").read_text()).get("files") or []:
                integrity[f["path"]] = f["sha256"]
        except (OSError, ValueError):
            pass
        out = []
        for p in sorted(base.rglob("*")):
            if p.is_file():
                rel = p.relative_to(base).as_posix()
                out.append({"path": rel, "bytes": p.stat().st_size, "abs": str(p), "sha256": integrity.get(rel)})
        return out

    def _files_tab(self, ref):
        tab = frame(self.nb)
        self.nb.add(tab, text="Files")
        bar = frame(tab)
        bar.pack(fill="x")
        label(bar, "Original artifacts (read-only). Export copies them elsewhere.").pack(side="left")
        table = Table(tab, [("path", "File", 620, "w"), ("bytes", "Bytes", 100, "e"),
                            ("sha256", "sha256 (integrity.json)", 300, "w")], multi=True,
                      on_open=lambda r: subprocess.Popen(["xdg-open", r["abs"]]))
        table.set_rows(self._files(ref))
        table.pack(fill="both", expand=True)

        def export():
            rows = table.selected_rows()
            if not rows:
                return
            dest = filedialog.askdirectory(title="Destination folder (outside the report)")
            if not dest:
                return
            dest = Path(dest)
            unit = Path(ref.path) if Path(ref.path).is_dir() else Path(ref.path).parent
            if dest.resolve() == unit.resolve() or unit.resolve() in dest.resolve().parents:
                messagebox.showerror("Export", "The destination is inside the report; choose another folder.")
                return
            for r in rows:
                target = dest / ref.id / r["path"]
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(r["abs"], target)
            self.app.set_status(f"{len(rows)} file(s) copied to {dest / ref.id}")
        button(bar, "Export copies…", export).pack(side="right")

#!/usr/bin/env python3
"""Tkinter GUI for the NativaX debug laboratory (data-driven)."""
from __future__ import annotations

import json
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable
DEBUG = ROOT / "debug"
LAB = DEBUG / "lab"
CORPUS = LAB / "corpus.json"


def load_corpus():
    if not CORPUS.exists():
        return {"cases": []}
    return json.loads(CORPUS.read_text())


class App:
    def __init__(self):
        import tkinter as tk
        from tkinter import ttk, scrolledtext
        self.tk = tk
        self.ttk = ttk
        self.scrolledtext = scrolledtext
        self.root = tk.Tk()
        self.root.title("NativaX Debug Lab")
        self.root.geometry("1100x700")
        self.corpus = load_corpus()
        self.cases = self.corpus.get("cases", [])
        self._build()

    def _build(self):
        tk = self.tk
        ttk = self.ttk
        frm = ttk.Frame(self.root)
        frm.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        left = ttk.Frame(frm)
        left.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 8))

        ttk.Label(left, text="Sección").pack()
        self.section_var = tk.StringVar(value="1")
        ttk.Entry(left, textvariable=self.section_var, width=6).pack()
        ttk.Button(left, text="Ejecutar sección", command=self.run_section).pack(fill=tk.X, pady=2)
        ttk.Button(left, text="Ejecutar todo", command=self.run_all).pack(fill=tk.X, pady=2)
        ttk.Button(left, text="Quality gate", command=self.run_gate).pack(fill=tk.X, pady=2)
        ttk.Button(left, text="Historial", command=self.run_history).pack(fill=tk.X, pady=2)
        ttk.Button(left, text="Abrir dashboard HTML", command=self.open_dashboard).pack(fill=tk.X, pady=2)

        ttk.Label(left, text=f"Casos reales: {len(self.cases)}").pack(pady=(8, 0))
        ttk.Label(left, text=f"Gaps s17: 26").pack()

        right = ttk.Frame(frm)
        right.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

        self.notebook = ttk.Notebook(right)
        self.notebook.pack(fill=tk.BOTH, expand=True)

        # Tab: sections
        sec_frame = ttk.Frame(self.notebook)
        self.notebook.add(sec_frame, text="Secciones")
        cols = ("section", "casos", "prefijo")
        self.sec_tree = ttk.Treeview(sec_frame, columns=cols, show="headings")
        for c in cols:
            self.sec_tree.heading(c, text=c)
        self.sec_tree.pack(fill=tk.BOTH, expand=True)
        self._fill_sections()

        # Tab: cases
        case_frame = ttk.Frame(self.notebook)
        self.notebook.add(case_frame, text="Casos")
        cols = ("id", "section", "repo", "facts", "bytes")
        self.case_tree = ttk.Treeview(case_frame, columns=cols, show="headings")
        for c in cols:
            self.case_tree.heading(c, text=c)
        self.case_tree.pack(fill=tk.BOTH, expand=True)
        self._fill_cases()

        # Tab: output
        out_frame = ttk.Frame(self.notebook)
        self.notebook.add(out_frame, text="Salida")
        self.out = self.scrolledtext.ScrolledText(out_frame, wrap="word")
        self.out.pack(fill=tk.BOTH, expand=True)

    def _fill_sections(self):
        from collections import Counter
        counts = Counter(c["section"] for c in self.cases)
        for sec in sorted(counts):
            prefix = {1: "html", 2: "css", 3: "box", 4: "typo", 5: "color", 6: "anim",
                      7: "resp", 8: "flex", 9: "pos", 10: "jsdom", 11: "events",
                      12: "forms", 13: "a11y", 14: "media", 15: "perf", 16: "integ"}.get(sec, "?")
            self.sec_tree.insert("", "end", values=(f"s{sec:02d}", counts[sec], prefix))

    def _fill_cases(self):
        for c in self.cases[:500]:
            self.case_tree.insert("", "end", values=(
                c["id"], c["section"], c["source"]["repo"], len(c["facts"].get("ids", [])) +
                len(c["facts"].get("classes", [])), c.get("bytes", 0)))

    def append(self, text):
        self.out.insert("end", text)
        self.out.see("end")

    def run_cmd(self, cmd):
        def worker():
            self.append("$ " + " ".join(cmd) + "\n")
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, cwd=ROOT)
            for line in p.stdout:
                self.append(line)
            p.wait()
            self.append(f"\n[exit {p.returncode}]\n")
        threading.Thread(target=worker, daemon=True).start()

    def run_section(self):
        self.run_cmd([PY, "debug/lab/run_lab.py", "--section", self.section_var.get()])

    def run_all(self):
        self.run_cmd([PY, "debug/lab/run_lab.py", "--all"])

    def run_gate(self):
        self.run_cmd([PY, "debug/judges/quality_gate/gate.py"])

    def run_history(self):
        self.run_cmd([PY, "debug/history/history.py", "list"])

    def open_dashboard(self):
        dash = DEBUG / "dashboard.html"
        if dash.exists():
            webbrowser.open(dash.as_uri())
            self.append(f"opened {dash}\n")
        else:
            self.append(f"dashboard not found: {dash}\n")

    def mainloop(self):
        self.root.mainloop()


if __name__ == "__main__":
    App().mainloop()
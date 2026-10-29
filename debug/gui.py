#!/usr/bin/env python3
"""GUI for the NativaX debug laboratory.

Prefers a real web view (pywebview) so the HTML dashboard renders natively;
falls back to a Tkinter dashboard driven by corpus.json when pywebview is
not installed.
"""
from __future__ import annotations

import json
import subprocess
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable
DEBUG = ROOT / "debug"
LAB = DEBUG / "lab"
CORPUS = LAB / "corpus.json"
DASHBOARD = DEBUG / "dashboard.html"


def main() -> int:
    try:
        import webview  # type: ignore
    except Exception:
        webview = None

    if webview is not None and DASHBOARD.exists():
        webview.create_window("NativaX Debug Lab", DASHBOARD.as_uri(), width=1280, height=820)
        webview.start()
        return 0

    # Fallback: Tkinter dashboard driven by real corpus data.
    import tkinter as tk
    from tkinter import ttk, scrolledtext

    corpus = json.loads(CORPUS.read_text()) if CORPUS.exists() else {"cases": []}
    cases = corpus.get("cases", [])

    root = tk.Tk()
    root.title("NativaX Debug Lab")
    root.geometry("1100x700")
    frm = ttk.Frame(root)
    frm.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

    left = ttk.Frame(frm)
    left.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 8))
    ttk.Label(left, text="Sección").pack()
    section_var = tk.StringVar(value="1")
    ttk.Entry(left, textvariable=section_var, width=6).pack()
    ttk.Button(left, text="Ejecutar sección",
               command=lambda: run_cmd([PY, "debug/lab/run_lab.py", "--section", section_var.get()])).pack(fill=tk.X, pady=2)
    ttk.Button(left, text="Ejecutar todo",
               command=lambda: run_cmd([PY, "debug/lab/run_lab.py", "--all"])).pack(fill=tk.X, pady=2)
    ttk.Button(left, text="Quality gate",
               command=lambda: run_cmd([PY, "debug/judges/quality_gate/gate.py"])).pack(fill=tk.X, pady=2)
    ttk.Label(left, text=f"Casos reales: {len(cases)}").pack(pady=(8, 0))

    out = scrolledtext.ScrolledText(frm, wrap="word")
    out.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

    def append(text):
        out.insert("end", text)
        out.see("end")

    def run_cmd(cmd):
        def worker():
            append("$ " + " ".join(cmd) + "\n")
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, cwd=ROOT)
            for line in p.stdout:
                append(line)
            p.wait()
            append(f"\n[exit {p.returncode}]\n")
        threading.Thread(target=worker, daemon=True).start()

    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
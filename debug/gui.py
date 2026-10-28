#!/usr/bin/env python3
"""Minimal Tkinter GUI for the NativaX debug laboratory."""
import subprocess
import sys
import threading
from pathlib import Path
import tkinter as tk
from tkinter import ttk, scrolledtext

ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("NativaX Debug Lab")
        self.geometry("900x600")
        frm = ttk.Frame(self)
        frm.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        left = ttk.Frame(frm)
        left.pack(side=tk.LEFT, fill=tk.Y)
        ttk.Label(left, text="Section").pack()
        self.section = tk.StringVar(value="1")
        ttk.Entry(left, textvariable=self.section, width=6).pack()
        ttk.Button(left, text="Run section", command=self.run_section).pack(fill=tk.X, pady=2)
        ttk.Button(left, text="Run all", command=self.run_all).pack(fill=tk.X, pady=2)
        ttk.Button(left, text="Quality gate", command=self.run_gate).pack(fill=tk.X, pady=2)
        ttk.Button(left, text="History list", command=self.run_history).pack(fill=tk.X, pady=2)

        self.out = scrolledtext.ScrolledText(frm, wrap=tk.WORD)
        self.out.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)

    def append(self, text):
        self.out.insert(tk.END, text)
        self.out.see(tk.END)

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
        self.run_cmd([PY, "debug/lab/run_lab.py", "--section", self.section.get()])

    def run_all(self):
        self.run_cmd([PY, "debug/lab/run_lab.py", "--all"])

    def run_gate(self):
        self.run_cmd([PY, "debug/judges/quality_gate/gate.py"])

    def run_history(self):
        self.run_cmd([PY, "debug/history/history.py", "list"])


if __name__ == "__main__":
    App().mainloop()

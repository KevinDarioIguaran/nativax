#!/usr/bin/env python3
"""Measure nativax-debug parse time over a smoke case."""
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EXE = ROOT / "build" / "nativax-debug"
HTML = ROOT / "debug" / "cases" / "smoke.html"
CSS = ROOT / "debug" / "cases" / "smoke.css"
OUT = ROOT / "debug" / "artifacts" / "bench" / "parse"

if not EXE.exists():
    print("build nativax-debug first", file=sys.stderr)
    raise SystemExit(2)
OUT.mkdir(parents=True, exist_ok=True)
start = time.perf_counter()
proc = subprocess.run([str(EXE), "--html", str(HTML), "--css", str(CSS), "--out", str(OUT)])
elapsed = time.perf_counter() - start
print(f"elapsed_seconds={elapsed:.6f} returncode={proc.returncode}")
raise SystemExit(proc.returncode)
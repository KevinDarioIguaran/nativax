#!/usr/bin/env python3
"""Two identical windowed runs of the REAL application must produce
byte-identical screenshots (DPI pinned to 1.0 with --deterministic).

Repaired: the runtime is now invoked with an explicit --root; without it the
entry resolved to the current working directory, the application failed to
load, no screenshot was ever written and the comparison crashed instead of
testing determinism.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2].parent
EXE = ROOT / "build" / "nativax-runtime"
JUDGE = ROOT / "debug" / "judges" / "visual" / "compare.py"
APP = ROOT / "examples" / "counter"

def main():
    if not os.environ.get("DISPLAY"):
        print("SKIP: no DISPLAY")
        return 0
    if not EXE.exists():
        print("SKIP: binary missing")
        return 0
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        a = td / "a.png"; b = td / "b.png"
        for out in (a, b):
            subprocess.run([str(EXE), "--deterministic", "--root", str(APP),
                            "--size", "1024", "768",
                            "--screenshot", str(out), "--frames", "4"],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        r = subprocess.run([sys.executable, str(JUDGE), str(a), str(b)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print("FAIL: screenshots differ")
            print(r.stdout)
            print(r.stderr)
            return 1
    print("screenshot determinism: OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

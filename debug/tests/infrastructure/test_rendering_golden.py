#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2].parent
EXE = ROOT / "build" / "nativax-runtime"
JUDGE = ROOT / "debug" / "judges" / "visual" / "compare.py"
GOLDEN = ROOT / "tests" / "goldens" / "smoke_render.png"

def main():
    if not os.environ.get("DISPLAY"):
        print("SKIP: no DISPLAY")
        return 0
    if not EXE.exists() or not GOLDEN.exists():
        print("SKIP: missing binary or golden")
        return 0
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        cur = td / "cur.png"
        subprocess.run([str(EXE), "--screenshot", str(cur), "--frames", "3"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        r = subprocess.run([sys.executable, str(JUDGE), str(GOLDEN), str(cur)], capture_output=True, text=True)
        if r.returncode != 0:
            print("FAIL: rendering golden mismatch")
            print(r.stdout)
            return 1
    print("rendering golden: OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
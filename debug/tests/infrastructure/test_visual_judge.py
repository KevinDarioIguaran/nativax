#!/usr/bin/env python3
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

JUDGE = Path(__file__).resolve().parents[2] / "judges" / "visual" / "compare.py"

def make(path, color):
    Image.new("RGB", (8, 8), color).save(path)

def run(a, b):
    return subprocess.run([sys.executable, str(JUDGE), str(a), str(b)], capture_output=True, text=True)

def main():
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        a = td / "a.png"; b = td / "b.png"; c = td / "c.png"
        make(a, (255, 0, 0)); make(b, (255, 0, 0)); make(c, (0, 0, 255))
        r1 = run(a, b)
        assert r1.returncode == 0, r1.stdout + r1.stderr
        r2 = run(a, c)
        assert r2.returncode != 0, r2.stdout + r2.stderr
    print("visual judge self-test: OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
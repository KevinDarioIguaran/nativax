#!/usr/bin/env python3
"""The Chrome vs NativaX comparison tool must be usable on this machine.

Runs the real self-check (numpy + pillow + playwright + Chromium launch and a
known 32x32 screenshot).  This replaces the old s17 "Chromium comparison"
blocked gap, which stopped being true when the visual judge was implemented.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "debug" / "judges" / "visual" / "chrome_compare.py"


def main():
    if not TOOL.exists():
        print("FAIL: chrome_compare.py is missing")
        return 1
    r = subprocess.run([sys.executable, str(TOOL), "--self-check"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("FAIL: Chrome comparison self-check failed")
        print((r.stdout or "") + (r.stderr or ""))
        return 1
    print("chrome comparison self-check: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

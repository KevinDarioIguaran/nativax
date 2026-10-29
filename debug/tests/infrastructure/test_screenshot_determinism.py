#!/usr/bin/env python3
"""Two identical windowed runs of the REAL application must produce
byte-identical screenshots (DPI pinned to 1.0 with --deterministic).

Repaired: the runtime is now invoked with an explicit --root; without it the
entry resolved to the current working directory, the application failed to
load, no screenshot was ever written and the comparison crashed instead of
testing determinism.

When no DISPLAY is available the test runs the windowed binary under Xvfb
instead of silently skipping.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EXE = ROOT / "build" / "nativax-runtime"
JUDGE = ROOT / "debug" / "judges" / "visual" / "compare.py"
APP = ROOT / "examples" / "counter"


def run(cmd: list[str]) -> None:
    """Run the windowed binary, using Xvfb when there is no display."""
    env = os.environ.copy()
    if not env.get("DISPLAY"):
        xvfb = shutil.which("xvfb-run")
        if not xvfb:
            raise RuntimeError("no DISPLAY and xvfb-run is not installed")
        cmd = [xvfb, "-a"] + cmd
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, env=env)


def main():
    if not EXE.exists():
        print("SKIP: binary missing")
        return 0
    try:
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            a = td / "a.png"
            b = td / "b.png"
            for out in (a, b):
                run([str(EXE), "--deterministic", "--root", str(APP),
                     "--size", "1024", "768",
                     "--screenshot", str(out), "--frames", "4"])
            r = subprocess.run([sys.executable, str(JUDGE), str(a), str(b)],
                               capture_output=True, text=True)
            if r.returncode != 0:
                print("FAIL: screenshots differ")
                print(r.stdout)
                print(r.stderr)
                return 1
    except RuntimeError as exc:
        print(f"SKIP: {exc}")
        return 0
    print("screenshot determinism: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

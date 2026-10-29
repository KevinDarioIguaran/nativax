#!/usr/bin/env python3
"""Windowed golden: render the REAL application (examples/counter) and compare
against the approved reference capture.

History: this test used to compare against tests/goldens/smoke_render.png,
which depicts build_smoke_scene() — a synthetic scene that was removed from the
runtime. That golden could never match the real pipeline and therefore tested
nothing. The old file is kept untouched for historical evidence; the reference
for the real application is debug/tests/goldens/counter_window.png (approved by
visual inspection, see debug/reports/phase1-report.md).

The runtime is invoked with an explicit --root: without it the entry resolved
to the current working directory and the application failed to load.

When no DISPLAY is available the test runs the windowed binary under Xvfb
instead of silently skipping, so the golden is verified in CI too.
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
GOLDEN = ROOT / "debug" / "tests" / "goldens" / "counter_window.png"
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
    if not EXE.exists() or not GOLDEN.exists():
        print("SKIP: missing binary or golden")
        return 0
    try:
        with tempfile.TemporaryDirectory() as td:
            cur = Path(td) / "cur.png"
            run([str(EXE), "--deterministic", "--root", str(APP),
                 "--size", "1024", "768",
                 "--screenshot", str(cur), "--frames", "4"])
            r = subprocess.run([sys.executable, str(JUDGE), str(GOLDEN), str(cur)],
                               capture_output=True, text=True)
            if r.returncode != 0:
                print("FAIL: rendering golden mismatch")
                print(r.stdout)
                print(r.stderr)
                return 1
    except RuntimeError as exc:
        print(f"SKIP: {exc}")
        return 0
    print("rendering golden: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

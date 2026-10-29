#!/usr/bin/env python3
"""NativaX debug quality gate.

Runs the debug tooling tests, the compatibility smoke matrix and verifies the
native binaries exist.  Only real results count: a test that exits 0 but prints
``SKIP:`` is reported as SKIP, never as PASS.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / "build"
DEBUG = ROOT / "debug"


def pick_python() -> str:
    """Prefer the laboratory venv, which has Pillow/numpy/playwright."""
    venv = DEBUG / ".venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if venv.exists():
        return str(venv)
    return sys.executable


PY = pick_python()


def run_test(path: Path) -> tuple[str, str]:
    r = subprocess.run([PY, str(path)], capture_output=True, text=True, cwd=ROOT)
    output = (r.stdout or "") + (r.stderr or "")
    if r.returncode != 0:
        return "FAIL", output.strip()[-1200:]
    if "SKIP:" in output:
        return "SKIP", output.strip()[-400:]
    return "PASS", ""


def is_tooling_test(path: Path) -> bool:
    """Only run our tests: skip venvs, caches and third-party packages."""
    parts = path.relative_to(ROOT).parts
    if any(part.startswith(".") for part in parts):
        return False
    if any(part in ("third_party", "node_modules", "site-packages")
           for part in parts):
        return False
    return True


def main() -> int:
    failures = 0
    skips = 0
    print(f"quality gate: python={PY}")

    def check(name: str, status: str, detail: str = "") -> None:
        nonlocal failures, skips
        print(f"{status:4s} {name}")
        if detail:
            for line in detail.splitlines():
                print(f"     {line}")
        if status == "FAIL":
            failures += 1
        elif status == "SKIP":
            skips += 1

    check("build dir exists", "PASS" if BUILD.exists() else "FAIL")
    for binary in ("nativax-debug", "nativax-runtime"):
        check(f"binary {binary}", "PASS" if (BUILD / binary).exists() else "FAIL")

    for tp in sorted(DEBUG.rglob("test_*.py")):
        if not is_tooling_test(tp):
            continue
        status, detail = run_test(tp)
        check(f"debug test {tp.relative_to(ROOT)}", status, detail)

    manifest = DEBUG / "tests" / "manifest.json"
    if manifest.exists():
        try:
            json.loads(manifest.read_text())
            check("manifest exists and is valid JSON", "PASS")
        except Exception as exc:  # noqa: BLE001
            check("manifest exists and is valid JSON", "FAIL", str(exc))
    else:
        check("manifest exists", "FAIL")

    compat = subprocess.run([PY, str(DEBUG / "compat" / "run_compat.py")],
                            capture_output=True, text=True, cwd=ROOT)
    check("compat runner", "PASS" if compat.returncode == 0 else "FAIL",
          "" if compat.returncode == 0 else (compat.stdout + compat.stderr)[-1200:])

    if failures:
        print(f"QUALITY GATE: FAIL ({failures} failure(s), {skips} skip(s))")
        return 1
    print(f"QUALITY GATE: PASS ({skips} skip(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

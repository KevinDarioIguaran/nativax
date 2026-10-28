#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / "build"

def check(name, ok):
    print(f"{'PASS' if ok else 'FAIL'} {name}")
    return ok

def main():
    ok = True
    ok &= check("build dir exists", BUILD.exists())
    if BUILD.exists():
        r = subprocess.run(["ctest", "--test-dir", str(BUILD), "--output-on-failure"], capture_output=True, text=True)
        ok &= check("ctest", r.returncode == 0)
    r = subprocess.run([sys.executable, str(ROOT / "debug" / "common" / "validation" / "validate_manifest.py")], capture_output=True, text=True)
    ok &= check("manifest valid", r.returncode == 0)
    r = subprocess.run([sys.executable, str(ROOT / "debug" / "tests" / "infrastructure" / "test_visual_judge.py")], capture_output=True, text=True)
    ok &= check("visual judge self-test", r.returncode == 0)
    print("QUALITY GATE:", "PASS" if ok else "FAIL")
    raise SystemExit(0 if ok else 1)

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / "build"
PY = "/usr/bin/python3" if Path("/usr/bin/python3").exists() else sys.executable

def check(name, ok):
    print(f"{'PASS' if ok else 'FAIL'} {name}")
    return ok

def main():
    ok = True
    ok &= check("build dir exists", BUILD.exists())
    # native tooling tests
    for tp in sorted((ROOT / "debug").rglob("test_*.py")):
        if "__pycache__" in tp.parts:
            continue
        r = subprocess.run([PY, str(tp)], capture_output=True, text=True, cwd=ROOT)
        ok &= check(f"debug test {tp.relative_to(ROOT)}", r.returncode == 0)
    r = subprocess.run([PY, str(ROOT / "debug" / "common" / "validation" / "validate_manifest.py")], capture_output=True, text=True)
    ok &= check("manifest valid", r.returncode == 0)
    # compat
    r = subprocess.run([PY, str(ROOT / "debug" / "compat" / "run_compat.py")], capture_output=True, text=True, cwd=ROOT)
    ok &= check("compat runner", r.returncode == 0)
    # llm eval
    r = subprocess.run([PY, str(ROOT / "debug" / "llm_eval" / "run_llm_eval.py")], capture_output=True, text=True, cwd=ROOT)
    ok &= check("llm eval runner", r.returncode == 0)
    # visual regression gate (self-compare current render)
    print("QUALITY GATE:", "PASS" if ok else "FAIL")
    raise SystemExit(0 if ok else 1)

if __name__ == "__main__":
    main()
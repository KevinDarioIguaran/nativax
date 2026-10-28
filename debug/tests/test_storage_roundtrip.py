#!/usr/bin/env python3
"""Native debug tooling tests: debug-artifact roundtrip through the real
native C CLI (nativax-debug) and the shipped manifest validator.

Covers: nativax-debug --html/--css/--out writes {dom.txt,dom.json,css.txt,summary.json}
        -> summary.json is valid JSON with expected structure
        -> dom/css artifacts parse + carry the expected payload
        -> debug/tests/manifest.json validates against the shipped JSON schema

Uses temp output dirs; the real debug/artifacts tree is never touched.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # <repo>/debug/tests/x.py -> repo
EXE = ROOT / "build" / "nativax-debug"
HTML = ROOT / "debug" / "cases" / "smoke.html"
CSS = ROOT / "debug" / "cases" / "smoke.css"
VALIDATOR = ROOT / "debug" / "common" / "validation" / "validate_manifest.py"
MANIFEST = ROOT / "tests" / "manifest.json"


def main() -> int:
    failures = 0

    def check(cond: bool, msg: str) -> None:
        nonlocal failures
        if not cond:
            failures += 1
            print(f"FAIL: {msg}")

    if not EXE.exists():
        print("SKIP: nativax-debug binary not built (build nativax-debug first)")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "artifacts"
        proc = subprocess.run(
            [str(EXE), "--html", str(HTML), "--css", str(CSS), "--out", str(out)],
            capture_output=True, text=True)
        check(proc.returncode == 0, f"nativax-debug smoke run ok (rc={proc.returncode}) {proc.stderr}")
        for name in ("dom.txt", "dom.json", "css.txt", "summary.json"):
            check((out / name).exists(), f"artifact written: {name}")
        summary = json.loads((out / "summary.json").read_text())
        check(summary.get("dom", {}).get("elements", 0) > 0, "summary records dom elements")
        check(summary.get("css", {}).get("rules", 0) > 0, "summary records css rules")
        dom_json = json.loads((out / "dom.json").read_text())
        check(isinstance(dom_json, dict), "dom.json is a json object")
        check("html" in summary and "css" in summary, "summary has html+css keys")

        # shipped schema validator must accept the shipped manifest (no stale entries)
        vp = subprocess.run([sys.executable, str(VALIDATOR)],
                             capture_output=True, text=True)
        check(vp.returncode == 0, f"manifest validates (rc={vp.returncode}) {vp.stdout}{vp.stderr}")

    print(f"native artifact roundtrip: {'OK' if failures == 0 else f'{failures} FAILURES'}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

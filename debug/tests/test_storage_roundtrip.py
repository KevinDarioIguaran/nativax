#!/usr/bin/env python3
"""Native debug tooling tests: debug-artifact roundtrip through the real
native C CLI (nativax-debug).

Covers: nativax-debug --html/--css/--out writes {dom.txt,dom.json,css.txt,summary.json}
        -> summary.json is valid JSON with expected structure
        -> dom/css artifacts parse + carry the expected payload
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXE = ROOT / "build" / "nativax-debug"


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
        work = Path(tmp)
        html = work / "smoke.html"
        css = work / "smoke.css"
        out = work / "artifacts"
        html.write_text("<!doctype html><html><body><div id=t>hi</div></body></html>")
        css.write_text("div { color: red; }")
        proc = subprocess.run(
            [str(EXE), "--html", str(html), "--css", str(css), "--out", str(out)],
            capture_output=True, text=True)
        check(proc.returncode == 0, f"nativax-debug smoke run ok (rc={proc.returncode}) {proc.stderr}")
        for name in ("dom.txt", "dom.json", "css.txt", "summary.json"):
            check((out / name).exists(), f"artifact written: {name}")
        if (out / "summary.json").exists():
            summary = json.loads((out / "summary.json").read_text())
            check(summary.get("dom", {}).get("elements", 0) > 0, "summary records dom elements")
            check(summary.get("css", {}).get("rules", 0) > 0, "summary records css rules")
            check("html" in summary and "css" in summary, "summary has html+css keys")
        if (out / "dom.json").exists():
            dom_json = json.loads((out / "dom.json").read_text())
            check(isinstance(dom_json, dict), "dom.json is a json object")

    print(f"native artifact roundtrip: {'OK' if failures == 0 else f'{failures} FAILURES'}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

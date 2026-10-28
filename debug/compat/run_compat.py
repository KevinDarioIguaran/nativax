#!/usr/bin/env python3
"""Run compatibility snippets through nativax-debug and report results."""
import json, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
DEBUG = ROOT / "debug"
EXE = BUILD / "nativax-debug"
PY = "/usr/bin/python3" if Path("/usr/bin/python3").exists() else sys.executable

def main():
    cases = json.loads((Path(__file__).parent / "cases.json").read_text())
    results = []
    for c in cases:
        d = Path(tempfile.mkdtemp())
        html = d / "t.html"
        css = d / "t.css"
        out = d / "out"
        html.write_text(c["html"])
        css.write_text(c.get("css", ""))
        r = subprocess.run([str(EXE), "--html", str(html), "--css", str(css),
                            "--out", str(out), "--width", "320", "--height", "200"],
                           capture_output=True, text=True)
        results.append({"id": c["id"], "ok": r.returncode == 0,
                        "stderr": r.stderr.strip()[:200]})
        if r.returncode != 0:
            print("FAIL", c["id"], r.stderr.strip()[:120])
        else:
            print("PASS", c["id"])
    report = ROOT / "debug" / "reports" / "compatibility-matrix.json"
    report.write_text(json.dumps({"cases": results}, indent=2))
    print("Wrote", report)
    raise SystemExit(0 if all(r["ok"] for r in results) else 1)

if __name__ == "__main__":
    main()

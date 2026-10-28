#!/usr/bin/env python3
"""Run a lightweight conformance suite against nativax-debug."""
import json, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
EXE = BUILD / "nativax-debug"

def main():
    feats = json.loads((Path(__file__).parent / "features.json").read_text())
    results = []
    for domain, cases in feats.items():
        for c in cases:
            d = Path(tempfile.mkdtemp())
            html = d / "t.html"; css = d / "t.css"; out = d / "out"
            html.write_text(c.get("html", "<html><body></body></html>"))
            css.write_text(c.get("css", ""))
            r = subprocess.run([str(EXE), "--html", str(html), "--css", str(css),
                                "--out", str(out)], capture_output=True, text=True)
            results.append({"domain": domain, "id": c["id"], "ok": r.returncode == 0,
                            "stderr": r.stderr.strip()[:120]})
            print("PASS" if r.returncode == 0 else "FAIL", domain, c["id"])
    report = ROOT / "debug" / "reports" / "conformance.json"
    report.write_text(json.dumps({"results": results}, indent=2))
    print("Wrote", report)
    raise SystemExit(0 if all(r["ok"] for r in results) else 1)

if __name__ == "__main__":
    main()

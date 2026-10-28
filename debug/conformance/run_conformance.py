#!/usr/bin/env python3
"""Run conformance cases against nativax-debug."""
import json, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
EXE = BUILD / "nativax-debug"

def main():
    all_results = []
    for jf in sorted(Path(__file__).parent.glob("*.json")):
        data = json.loads(jf.read_text())
        if isinstance(data, list):
            domains = {"general": data}
        elif "cases" in data:
            domains = {"general": data["cases"]}
        else:
            domains = data
        for domain, cases in domains.items():
            for c in cases:
                d = Path(tempfile.mkdtemp())
                html = d / "t.html"; css = d / "t.css"; out = d / "out"
                html.write_text(c.get("html", "<html><body></body></html>"))
                css.write_text(c.get("css", ""))
                r = subprocess.run([str(EXE), "--html", str(html), "--css", str(css),
                                    "--out", str(out)], capture_output=True, text=True)
                all_results.append({"domain": domain, "id": c["id"], "ok": r.returncode == 0,
                                "stderr": r.stderr.strip()[:120]})
                print("PASS" if r.returncode == 0 else "FAIL", domain, c["id"])
    report = ROOT / "debug" / "reports" / "conformance.json"
    report.write_text(json.dumps({"results": all_results}, indent=2))
    print("Wrote", report, "total", len(all_results))
    raise SystemExit(0 if all(r["ok"] for r in all_results) else 1)

if __name__ == "__main__":
    main()
PY
#!/usr/bin/env python3
"""Generate debug/dashboard_data.js from the real corpus and latest report."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEBUG = ROOT / "debug"
LAB = DEBUG / "lab"
CORPUS = LAB / "corpus.json"
REPORT = DEBUG / "reports" / "lab" / "latest.json"
OUT = DEBUG / "dashboard_data.js"

PREFIX = {
    1: "html", 2: "css", 3: "box", 4: "typo", 5: "color", 6: "anim",
    7: "resp", 8: "flex", 9: "pos", 10: "jsdom", 11: "events", 12: "forms",
    13: "a11y", 14: "media", 15: "perf", 16: "integ",
}

TREE = """debug/
├─ bootstrap.py
├─ README.md
├─ progress/
├─ tools/
│  └─ import_real_examples.py
└─ lab/
   ├─ harness.py
   ├─ run_lab.py
   ├─ corpus.py
   ├─ corpus.json
   ├─ ATTRIBUTION.md
   ├─ sections/
   │  ├─ s01.py … s16.py
   │  └─ s17_gaps.py
   └─ cases/
      └─ s01/001 … s16/015  (240 ejemplos)"""

CLI = [
    "python debug/bootstrap.py",
    "python debug/lab/run_lab.py --all",
    "python debug/lab/run_lab.py s07",
    "python debug/lab/run_lab.py --list",
    "python debug/tools/import_real_examples.py --check",
]


def load_gaps() -> list[str]:
    """Derive the documented capability gaps from the real s17 section."""
    path = LAB / "sections" / "s17_gaps.py"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    return re.findall(r'@case\(\s*17\s*,\s*"[^"]*"\s*,\s*\'([^\']*)\'\s*\)', text)


def main() -> int:
    corpus = json.loads(CORPUS.read_text()) if CORPUS.exists() else {"cases": []}
    # Merge every available section report so partial runs do not erase the
    # results of previously run sections.
    report_files = sorted((DEBUG / "reports" / "lab").glob("section-*.json"))
    if REPORT.exists():
        report_files.append(REPORT)
    merged_cases = {}
    generated_at = None
    label = None
    for rf in report_files:
        try:
            payload = json.loads(rf.read_text())
        except Exception:
            continue
        for c in payload.get("cases", []):
            merged_cases[c["id"]] = c
        ga = payload.get("generated_at")
        if ga and (generated_at is None or ga > generated_at):
            generated_at = ga
            label = "merged" if len(report_files) > 1 else payload.get("label", rf.stem)
    report = {"cases": list(merged_cases.values()),
              "generated_at": generated_at, "label": label} if merged_cases else {}
    by_id = {c["id"]: c for c in report.get("cases", [])}

    sections = []
    for sec in sorted({c["section"] for c in corpus.get("cases", [])}):
        sections.append([f"s{sec:02d}", PREFIX.get(sec, f"s{sec:02d}")])

    cases = []
    for c in corpus.get("cases", []):
        r = by_id.get(c["id"], {})
        status = r.get("status") or "unrun"
        cases.append({
            "id": c["id"],
            "sid": f"s{c['section']:02d}",
            "name": PREFIX.get(c["section"], f"s{c['section']:02d}"),
            "repo": c["source"]["repo"],
            "commit": c["source"]["commit"][:7],
            "path": c["source"]["path"],
            "facts": len(c["facts"].get("ids", [])) + len(c["facts"].get("classes", [])),
            "ms": r.get("duration_ms", 0),
            "status": status,
        })

    data = {
        "sections": sections,
        "repos": sorted({c["source"]["repo"] for c in corpus.get("cases", [])}),
        "gaps": load_gaps(),
        "tree": TREE,
        "cli": CLI,
        "cases": cases,
        "report": {
            "available": bool(report),
            "generated_at": report.get("generated_at"),
            "label": report.get("label"),
        },
    }
    OUT.write_text("window.DASHBOARD_DATA = " + json.dumps(data, ensure_ascii=False) + ";\n")
    print(f"wrote {OUT} ({len(cases)} cases, report={'yes' if report else 'no'})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

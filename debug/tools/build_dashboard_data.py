#!/usr/bin/env python3
"""Generate debug/dashboard_data.js from the real corpus and latest report."""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEBUG = ROOT / "debug"
LAB = DEBUG / "lab"
DASHBOARD = DEBUG / "dashboard"
CORPUS = LAB / "corpus.json"
REPORT = DEBUG / "reports" / "lab" / "latest.json"
VISUAL_REPORT = DEBUG / "reports" / "visual" / "latest.json"
OUT = DASHBOARD / "dashboard_data.js"

PREFIX = {
    1: "html", 2: "css", 3: "box", 4: "typo", 5: "color", 6: "anim",
    7: "resp", 8: "flex", 9: "pos", 10: "jsdom", 11: "events", 12: "forms",
    13: "a11y", 14: "media", 15: "perf", 16: "integ", 17: "gaps",
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
    for sec in sorted({c["section"] for c in corpus.get("cases", [])} | {17}):
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

    visual = {}
    if VISUAL_REPORT.exists():
        try:
            visual = json.loads(VISUAL_REPORT.read_text())
        except Exception:
            visual = {}

    # Everything the dashboard needs also works when the HTML is opened
    # directly in a browser (no pywebview bridge).
    latest = {}
    if REPORT.exists():
        try:
            latest = json.loads(REPORT.read_text())
        except Exception:
            latest = {}
    report_summary = latest.get("summary") or {}
    report_sections = []
    for p in sorted((DEBUG / "reports" / "lab").glob("section-*.json")):
        try:
            payload = json.loads(p.read_text())
        except Exception:
            continue
        report_sections.append({"file": p.name, "label": payload.get("label", p.stem),
                                "summary": payload.get("summary", {})})

    history = []
    index = DEBUG / "history" / "index.json"
    if index.exists():
        try:
            history = json.loads(index.read_text())
        except Exception:
            history = []

    artifacts = []
    image_roots = [DEBUG / "artifacts", DEBUG / "tests" / "goldens"]
    for root in image_roots:
        if not root.exists():
            continue
        for p in sorted(root.rglob("*")):
            if not p.is_file() or p.suffix.lower() not in {".png", ".jpg", ".jpeg"}:
                continue
            try:
                rel = os.path.relpath(p, DASHBOARD).replace(os.sep, "/")
                artifacts.append({"path": str(p.relative_to(DEBUG)),
                                  "size": p.stat().st_size, "url": rel})
            except OSError:
                continue

    visual_thresholds = {
        "tolerance": 4,
        "max_changed_percent": 2.0,
        "warn_changed_percent": 8.0,
        "max_mae": 6.0,
        "min_ssim": 0.9,
    }
    if isinstance(visual, dict) and isinstance(visual.get("thresholds"), dict):
        visual_thresholds.update(visual["thresholds"])

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
            "summary": report_summary,
        },
        "report_sections": report_sections,
        "history": history,
        "artifacts": artifacts[:600],
        "visual": visual,
        "standards": {
            "lab": {
                "pass": "la aserción del caso se cumple",
                "fail": "la aserción no se cumple (regresión real)",
                "blocked": "capacidad no implementada, documentada en s17",
                "error": "excepción inesperada del harness (nunca cuenta como pass)",
                "responsive": "todo caso responsive debe caber en el viewport; "
                              "el desbordamiento horizontal es un fail",
                "gate": "el quality gate no admite SKIP como PASS",
            },
            "visual": {
                "thresholds": visual_thresholds,
                "rules": [
                    "size_mismatch = fail",
                    "pass: changed% <= max_changed_percent AND "
                    "mae <= max_mae AND ssim >= min_ssim",
                    "warn: changed% <= warn_changed_percent (no es pass)",
                    "fail: changed% > warn_changed_percent",
                ],
            },
        },
    }
    OUT.write_text("window.DASHBOARD_DATA = " + json.dumps(data, ensure_ascii=False) + ";\n")
    print(f"wrote {OUT} ({len(cases)} cases, report={'yes' if report else 'no'})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

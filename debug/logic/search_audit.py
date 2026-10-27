#!/usr/bin/env python3
"""Accuracy audit of the report search (`catalog.search`).

Builds a fixed, deterministic corpus of report refs, runs a query set whose
expected results are known by construction, and writes precision and recall
per query class to debug/datasets/search/audit.json.

    python3 debug/logic/search_audit.py [out.json]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import catalog  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "debug" / "datasets" / "search" / "audit.json"

AREAS = {"visual_comparison": "visual", "performance": "perf", "memory": "leaks", "security": "security",
         "compatibility": "conformance", "bug_detection": "audit"}
COMMITS = ["f760cec", "97d0f19", "d93509a", "70a605a"]


def corpus() -> list[catalog.ReportRef]:
    refs = []
    for i in range(240):
        rtype = list(AREAS)[i % len(AREAS)]
        area = AREAS[rtype]
        day = 10 + i % 17
        rid = f"{area.upper()}-202610{day:02d}T{i % 24:02d}0000Z-{COMMITS[i % 4]}-{i:03d}"
        health = ("ok", "warn", "error")[i % 3]
        refs.append(catalog.ReportRef(
            type=rtype, area=area, id=rid, path=f"debug/artifacts/runs/{area}/{rid}", layout="run-manifest/1.1",
            created_at=f"2026-10-{day:02d}T{i % 24:02d}:00:00+00:00", status="complete", health=health,
            commit=COMMITS[i % 4], engine=("QuickJS-ng" if i % 2 else "V8"),
            summary=f"{area} run {i}", errors=(["schema: missing field total"] if health == "error" else [])))
    return refs


def queries(refs):
    """(class, query, expected ids) — expected computed from the fields the
    query names, independently of catalog.search."""
    def ids(pred):
        return {r.id for r in refs if pred(r)}
    one = refs[37]
    return [
        ("exact id", one.id, {one.id}),
        ("exact id, other case", one.id.lower(), {one.id}),
        ("id prefix", one.id[:14], ids(lambda r: r.id.startswith(one.id[:14]))),
        ("run number", "-037", ids(lambda r: r.id.endswith("-037"))),
        ("area", "leaks", ids(lambda r: r.area == "leaks")),
        ("type", "visual_comparison", ids(lambda r: r.type == "visual_comparison")),
        ("commit", "97d0f19", ids(lambda r: r.commit == "97d0f19")),
        ("commit + area (AND)", "f760cec leaks", ids(lambda r: r.commit == "f760cec" and r.area == "leaks")),
        ("engine", "v8", ids(lambda r: r.engine == "V8")),
        ("error text", "missing field", ids(lambda r: r.health == "error")),
        ("path", "artifacts/runs/security", ids(lambda r: r.area == "security")),
        ("typo (1 char)", "lekas", ids(lambda r: r.area == "leaks")),
        ("typo in commit", "97d0f91", ids(lambda r: r.commit == "97d0f19")),
        ("no match", "zzzz-not-there", set()),
        ("empty query", "", {r.id for r in refs}),
    ]


def audit() -> dict:
    refs = corpus()
    rows = []
    for cls, query, expected in queries(refs):
        got = {r.id for r in catalog.search(refs, query)}
        tp = len(got & expected)
        rows.append({
            "class": cls, "query": query, "expected": len(expected), "returned": len(got), "tp": tp,
            "precision": (tp / len(got)) if got else (1.0 if not expected else 0.0),
            "recall": (tp / len(expected)) if expected else (1.0 if not got else 0.0),
        })
    counts = catalog.counts_by_type(refs)
    counts_ok = all(sum(v for k, v in c.items() if k != "total") == c["total"] for c in counts.values()) and \
        sum(c["total"] for c in counts.values()) == len(refs)
    exact = [r for r in rows if not r["class"].startswith("typo")]
    return {
        "schema": "nativax.search_audit/1",
        "corpus": len(refs),
        "queries": len(rows),
        "mean_precision_non_typo": sum(r["precision"] for r in exact) / len(exact),
        "mean_recall_non_typo": sum(r["recall"] for r in exact) / len(exact),
        "typo_recall": [r["recall"] for r in rows if r["class"].startswith("typo")],
        "counts_by_type_consistent": counts_ok,
        "rows": rows,
    }


def main(argv=None) -> int:
    out = Path((argv or sys.argv[1:] or [str(OUT)])[0])
    data = audit()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    for r in data["rows"]:
        print(f"{r['class']:<22} P={r['precision']:.2f} R={r['recall']:.2f} ({r['tp']}/{r['expected']}, returned {r['returned']})")
    print(f"non-typo mean P={data['mean_precision_non_typo']:.3f} R={data['mean_recall_non_typo']:.3f}; "
          f"typo recall {data['typo_recall']} -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

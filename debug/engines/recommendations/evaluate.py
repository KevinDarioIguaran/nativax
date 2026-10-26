#!/usr/bin/env python3
"""Scores the recommendation engine against the committed dataset.

For every case in debug/datasets/recommendations/cases the engine runs on
`input` and its rule ids are compared with `expected` (complete set) and
`must_not` (invalid or harmful ids). The report gives per-rule precision and
recall, missed and must-not ids, priority mismatches, engine errors, and the
duplicates and contradictions `recommend.audit()` finds. Deterministic: same
dataset and engine, same report.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import recommend  # noqa: E402

DATASET = recommend.ROOT / "debug" / "datasets" / "recommendations" / "cases"


def load_cases(folder: Path = DATASET) -> list[dict[str, Any]]:
    cases = []
    for path in sorted(folder.glob("*.json")):
        case = json.loads(path.read_text())
        case.setdefault("id", path.stem)
        cases.append(case)
    return cases


def _ratio(num: int, den: int) -> float | None:
    return round(num / den, 4) if den else None


def evaluate(
    cases: list[dict[str, Any]],
    engine: Callable[[dict[str, Any]], list[Any]] = recommend.build_recommendations,
) -> dict[str, Any]:
    rule_ids = set(recommend.RULES)
    for case in cases:
        rule_ids.update(case.get("expected", []))
    counts = {rule: {"tp": 0, "fp": 0, "fn": 0, "must_not_hits": 0} for rule in rule_ids}
    results = []
    for case in cases:
        expected = set(case.get("expected", []))
        must_not = set(case.get("must_not", []))
        error = None
        try:
            recs = engine(case.get("input") or {})
        except Exception as exc:  # the report must show crashes, not stop
            recs = []
            error = f"{type(exc).__name__}: {exc}"
        fired = [rec.id for rec in recs]
        fired_set = set(fired)
        for rule in fired_set:
            counts.setdefault(rule, {"tp": 0, "fp": 0, "fn": 0, "must_not_hits": 0})
        tp = fired_set & expected
        fp = fired_set - expected
        fn = expected - fired_set
        harmful = fired_set & must_not
        for rule in tp:
            counts[rule]["tp"] += 1
        for rule in fp:
            counts[rule]["fp"] += 1
        for rule in fn:
            counts[rule]["fn"] += 1
        for rule in harmful:
            counts[rule]["must_not_hits"] += 1
        priorities = {rec.id: rec.priority for rec in recs}
        priority_mismatches = [
            {"id": rule, "expected": want, "actual": priorities[rule]}
            for rule, want in sorted((case.get("expected_priorities") or {}).items())
            if rule in priorities and priorities[rule] != want
        ]
        report = recommend.audit(recs)
        results.append({
            "id": case["id"],
            "fired": fired,
            "missed": sorted(fn),
            "unexpected": sorted(fp),
            "must_not_hits": sorted(harmful),
            "priority_mismatches": priority_mismatches,
            "duplicates": report["duplicates"],
            "contradictions": report["contradictions"],
            "error": error,
            "pass": not (fn or fp or harmful or priority_mismatches or error
                         or report["duplicates"] or report["contradictions"]),
        })
    per_rule = {}
    for rule in sorted(counts):
        c = counts[rule]
        per_rule[rule] = dict(
            c,
            precision=_ratio(c["tp"], c["tp"] + c["fp"]),
            recall=_ratio(c["tp"], c["tp"] + c["fn"]),
        )
    tp = sum(c["tp"] for c in counts.values())
    fp = sum(c["fp"] for c in counts.values())
    fn = sum(c["fn"] for c in counts.values())
    summary = {
        "cases": len(cases),
        "cases_passed": sum(1 for r in results if r["pass"]),
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "precision": _ratio(tp, tp + fp),
        "recall": _ratio(tp, tp + fn),
        "must_not_hits": sum(len(r["must_not_hits"]) for r in results),
        "priority_mismatches": sum(len(r["priority_mismatches"]) for r in results),
        "duplicates": sum(len(r["duplicates"]) for r in results),
        "contradictions": sum(len(r["contradictions"]) for r in results),
        "errors": sum(1 for r in results if r["error"]),
    }
    return {"summary": summary, "per_rule": per_rule, "cases": results}


def _fmt(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.3f}"


def markdown(report: dict[str, Any]) -> str:
    s = report["summary"]
    lines = [
        "# Recommendation engine evaluation",
        "",
        f"- Cases: {s['cases']} ({s['cases_passed']} fully correct)",
        f"- Micro precision: {_fmt(s['precision'])} · micro recall: {_fmt(s['recall'])} "
        f"(TP {s['tp']}, FP {s['fp']}, FN {s['fn']})",
        f"- Must-not hits: {s['must_not_hits']} · priority mismatches: "
        f"{s['priority_mismatches']} · errors: {s['errors']}",
        f"- Duplicates: {s['duplicates']} · contradictions: {s['contradictions']}",
        "",
        "## Per rule",
        "",
        "| Rule | TP | FP | FN | Must-not | Precision | Recall |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for rule, c in report["per_rule"].items():
        lines.append(
            f"| `{rule}` | {c['tp']} | {c['fp']} | {c['fn']} | {c['must_not_hits']} | "
            f"{_fmt(c['precision'])} | {_fmt(c['recall'])} |"
        )
    failing = [r for r in report["cases"] if not r["pass"]]
    lines.extend(["", "## Cases with findings", ""])
    if not failing:
        lines.append("None.")
    for r in failing:
        parts = []
        if r["error"]:
            parts.append(f"error {r['error']}")
        if r["missed"]:
            parts.append("missed " + ", ".join(r["missed"]))
        if r["must_not_hits"]:
            parts.append("must-not " + ", ".join(r["must_not_hits"]))
        extra = sorted(set(r["unexpected"]) - set(r["must_not_hits"]))
        if extra:
            parts.append("unexpected " + ", ".join(extra))
        for m in r["priority_mismatches"]:
            parts.append(f"priority {m['id']} {m['actual']} (expected {m['expected']})")
        for d in r["duplicates"]:
            parts.append(f"duplicate {d['kind']} {' + '.join(d['ids'])}")
        for c in r["contradictions"]:
            parts.append(f"contradiction {c['kind']} {' vs '.join(c['ids'])}")
        lines.append(f"- `{r['id']}`: " + "; ".join(parts))
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=Path, default=DATASET)
    parser.add_argument("--json", action="store_true", help="print the JSON report")
    parser.add_argument("--out", type=Path, help="also write the markdown report here")
    args = parser.parse_args()
    report = evaluate(load_cases(args.cases))
    text = json.dumps(report, indent=2) if args.json else markdown(report)
    print(text)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(markdown(report))
    s = report["summary"]
    clean = s["cases_passed"] == s["cases"]
    return 0 if clean else 1


if __name__ == "__main__":
    raise SystemExit(main())

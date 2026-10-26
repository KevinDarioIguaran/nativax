#!/usr/bin/env python3
"""Scores the quality gate on the constructed pairs in
debug/datasets/quality_gate/pairs.json.

    python3 debug/engines/quality_gate/evaluate_gate.py            # Markdown table
    python3 debug/engines/quality_gate/evaluate_gate.py --json     # machine-readable

Two scores per gate:

* verdict accuracy: pairs whose overall verdict matches the expectation;
* metric accuracy: metric judgments (every metric of every pair) whose
  status matches. A metric that is not listed in the expectation is expected
  ``unchanged``, or the ``area_default`` of its area.

The legacy gate (single tolerances, no comparability check) is scored on the
same pairs for reference. It has no ``inconclusive`` or ``not_comparable``
status and skips missing metrics, so those count as wrong.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DATASET = ROOT / "debug" / "datasets" / "quality_gate"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(DATASET))

import gate_compare  # noqa: E402
import legacy_compare  # noqa: E402

LEGACY_VERDICT = {"EQUAL": "unchanged", "BETTER": "improved", "WORSE": "regressed",
                  "MIXED": "regressed", "BASELINE": "no_baseline"}
LEGACY_STATUS = {"equal": "unchanged", "better": "improved", "worse": "regressed"}


def load_pairs(path=DATASET / "pairs.json"):
    return json.loads(Path(path).read_text())["pairs"]


def sides(pair):
    baseline = pair.get("baseline")
    if "baseline_runs" in pair:
        baseline = gate_compare.aggregate(pair["baseline_runs"])
    current = pair.get("current")
    if "current_runs" in pair:
        current = gate_compare.aggregate(pair["current_runs"])
    return baseline, current


def expected_status(pair, metric_id):
    expected = pair["expected"]
    if metric_id in expected["metrics"]:
        return expected["metrics"][metric_id]
    return expected["area_default"].get(gate_compare.area_of(metric_id), "unchanged")


def metric_ids(baseline, current):
    ids = set(gate_compare.flatten(current))
    if baseline:
        ids |= set(gate_compare.flatten(baseline))
    return sorted(ids)


def run_new(baseline, current):
    result = gate_compare.compare(current, baseline)
    return result["verdict"], {c["id"]: c["status"] for c in result["changes"]}


def _legacy_id(change):
    area, metric = change["area"], change["metric"]
    if area == "compatibility":
        return f"compatibility/{metric}/passRate"
    return f"{area}/{metric}"


def run_legacy(baseline, current):
    result = legacy_compare.compare(current, baseline)
    statuses = {_legacy_id(c): LEGACY_STATUS[c["status"]] for c in result["changes"]}
    return LEGACY_VERDICT[result["verdict"]], statuses


def evaluate(pairs, gate):
    rows = []
    for pair in pairs:
        baseline, current = sides(pair)
        verdict, statuses = gate(baseline, current)
        ids = metric_ids(baseline, current) if baseline else []
        metrics = [(m, expected_status(pair, m), statuses.get(m)) for m in ids]
        rows.append({"name": pair["name"], "expected": pair["expected"]["verdict"],
                     "verdict": verdict, "metrics": metrics})
    verdict_ok = sum(1 for r in rows if r["verdict"] == r["expected"])
    judgments = [m for r in rows for m in r["metrics"]]
    metric_ok = sum(1 for _, want, got in judgments if want == got)
    # Judgments where the gate produced any status for the metric at all.
    judged = [(want, got) for _, want, got in judgments if got is not None]
    per_status = {}
    for _, want, got in judgments:
        bucket = per_status.setdefault(want, [0, 0])
        bucket[1] += 1
        bucket[0] += want == got
    per_verdict = {}
    for r in rows:
        bucket = per_verdict.setdefault(r["expected"], [0, 0])
        bucket[1] += 1
        bucket[0] += r["verdict"] == r["expected"]
    return {
        "pairs": len(rows),
        "verdict_correct": verdict_ok,
        "verdict_accuracy": 100 * verdict_ok / len(rows) if rows else 0,
        "metric_judgments": len(judgments),
        "metric_correct": metric_ok,
        "metric_accuracy": 100 * metric_ok / len(judgments) if judgments else 0,
        "metrics_judged": len(judged),
        "judged_accuracy": 100 * sum(1 for w, g in judged if w == g) / len(judged) if judged else 0,
        "per_expected_status": per_status,
        "per_expected_verdict": per_verdict,
        "wrong_verdicts": [{"name": r["name"], "expected": r["expected"], "got": r["verdict"]}
                           for r in rows if r["verdict"] != r["expected"]],
    }


def markdown(new, legacy):
    lines = [
        "| Gate | Pairs | Verdicts correct | Verdict accuracy | Metric judgments | "
        "Metrics correct | Metric accuracy | Metrics it judged | Accuracy on those |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for name, r in (("per-metric (new)", new), ("single tolerance (legacy)", legacy)):
        lines.append(f"| {name} | {r['pairs']} | {r['verdict_correct']} | "
                     f"{r['verdict_accuracy']:.1f} % | {r['metric_judgments']} | "
                     f"{r['metric_correct']} | {r['metric_accuracy']:.1f} % | "
                     f"{r['metrics_judged']} | {r['judged_accuracy']:.1f} % |")
    lines += ["", "| Expected verdict | Pairs | New correct | Legacy correct |", "|---|---:|---:|---:|"]
    for status in sorted(new["per_expected_verdict"]):
        n_ok, n = new["per_expected_verdict"][status]
        l_ok, _ = legacy["per_expected_verdict"].get(status, [0, n])
        lines.append(f"| {status} | {n} | {n_ok} | {l_ok} |")
    lines += ["", "| Expected metric status | Judgments | New correct | Legacy correct |",
              "|---|---:|---:|---:|"]
    for status in sorted(new["per_expected_status"]):
        n_ok, n = new["per_expected_status"][status]
        l_ok, _ = legacy["per_expected_status"].get(status, [0, n])
        lines.append(f"| {status} | {n} | {n_ok} | {l_ok} |")
    if new["wrong_verdicts"]:
        lines += ["", "Wrong verdicts (new gate):"]
        lines += [f"- {w['name']}: expected {w['expected']}, got {w['got']}" for w in new["wrong_verdicts"]]
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    pairs = load_pairs()
    new = evaluate(pairs, run_new)
    legacy = evaluate(pairs, run_legacy)
    if args.json:
        print(json.dumps({"new": new, "legacy": legacy}, indent=2))
    else:
        print(markdown(new, legacy), end="")
    return 0 if new["verdict_correct"] == new["pairs"] and new["metric_correct"] == new["metric_judgments"] else 1


if __name__ == "__main__":
    sys.exit(main())

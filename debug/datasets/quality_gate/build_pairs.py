#!/usr/bin/env python3
"""Builds pairs.json: constructed baseline/current snapshot pairs for the
quality gate, each with the verdict it should get.

Every pair starts from one synthetic baseline and applies a known change.
The expectation is written from the construction (what was changed, by how
much, and whether the two runs are comparable), never by running the gate.

    python3 debug/datasets/quality_gate/build_pairs.py   # rewrites pairs.json
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent

BASE = {
    "generated_at": "2026-10-26T00:00:00+00:00",
    "context": {
        "global": {"environment_class": "Linux-x86_64-16cpu-Example CPU"},
        "visual": {"catalog_size": 40, "catalog_digest": "aaaaaaaaaaaaaaaa", "tool_version": "0.1.0",
                   "reference": "Chrome 141", "viewport": {"width": 1280, "height": 800},
                   "scheme": "light", "suites": ["50projects50days"]},
        "performance": {"catalog_size": 3, "catalog_digest": "bbbbbbbbbbbbbbbb", "tool_version": "0.1.0",
                        "engine": ["nativax-v8"], "reference": "Chrome 141",
                        "viewport": {"width": 1280, "height": 800}, "targets": {}, "command": "perf run"},
    },
    "visual": {
        "pages": 40,
        "verdicts": {"PASS": 30, "WARN": 0, "FAIL": 10, "INVALID": 0},
        "categories": {"overall": 80.0, "position": 85.0, "layout": 78.0, "color": 90.0, "design": 70.0},
        "mismatched_pct": 12.0,
        "mean_ink_pct": 5.0,
    },
    "perf": {
        "scenarios": 3,
        "verdicts": {"PASS": 2, "WARN": 0, "FAIL": 1, "INVALID": 0},
        "work": {"s1-scroll": 100.0, "s2-dom": 20.0, "s3-style": 5.0},
        "idle": {"rss_mb": 150.0, "cpu_pct": 1.0},
    },
    "compat": {
        "test262": {"suite": "test262", "passRate": 90.0,
                    "counts": {"PASS": 900, "FAIL": 100, "SKIP": 50, "ERROR": 0},
                    "suiteCommit": "d53ebc8b", "runnerVersion": "0.2.0",
                    "command": "run_test262 test/language/expressions"},
        "url": {"suite": "wpt-url", "passRate": 80.0,
                "counts": {"PASS": 400, "FAIL": 100, "SKIP": 0, "ERROR": 0},
                "suiteCommit": "e7d77cd1", "runnerVersion": "0.2.0", "command": "run_url"},
    },
}

PAIRS = []


def pair(name, description, verdict, change=None, metrics=None, area_default=None,
         baseline_change=None, baseline_runs=None, current_runs=None, no_baseline=False):
    baseline = copy.deepcopy(BASE)
    if baseline_change:
        baseline_change(baseline)
    current = copy.deepcopy(BASE)
    if change:
        change(current)
    entry = {"name": name, "description": description,
             "expected": {"verdict": verdict, "metrics": metrics or {},
                          "area_default": area_default or {}}}
    if no_baseline:
        entry["baseline"] = None
    elif baseline_runs:
        entry["baseline_runs"] = [_with(baseline, f) for f in baseline_runs]
    else:
        entry["baseline"] = baseline
    if current_runs:
        entry["current_runs"] = [_with(current, f) for f in current_runs]
    else:
        entry["current"] = current
    PAIRS.append(entry)


def _with(snapshot, mutate):
    out = copy.deepcopy(snapshot)
    mutate(out)
    return out


def setter(*path_and_value):
    *path, value = path_and_value

    def apply(snapshot):
        node = snapshot
        for key in path[:-1]:
            node = node[key]
        node[path[-1]] = value
    return apply


def chain(*fns):
    def apply(snapshot):
        for f in fns:
            f(snapshot)
    return apply


def work(value, scenario="s1-scroll"):
    return setter("perf", "work", scenario, value)


ALL = "not_comparable"

pair("identical", "Same snapshot twice.", "unchanged")
pair("visual-real-gain", "Mean fidelity +2 pp; the visual judge is deterministic.", "improved",
     setter("visual", "categories", "overall", 82.0), {"visual/overall": "improved"})
pair("visual-below-tolerance", "Mean fidelity -0.3 pp, below the 0.5 pp practical tolerance.",
     "unchanged", setter("visual", "categories", "overall", 79.7))
pair("visual-color-loss", "Color score -1.5 pp.", "regressed",
     setter("visual", "categories", "color", 88.5), {"visual/color": "regressed"})
pair("visual-fail-page", "One page moves from PASS to FAIL (FAIL count is lower-is-better).", "regressed",
     chain(setter("visual", "verdicts", "PASS", 29), setter("visual", "verdicts", "FAIL", 11)),
     {"visual/PASS pages": "regressed", "visual/FAIL pages": "regressed"})
pair("visual-ink-small", "Ink mismatch +0.8 pp, below its 1 pp tolerance.", "unchanged",
     setter("visual", "mean_ink_pct", 5.8))
pair("visual-mismatch-gain", "Mismatched pixels -0.4 pp (tolerance 0.1 pp).", "improved",
     setter("visual", "mismatched_pct", 11.6), {"visual/mismatched %": "improved"})
pair("perf-large-regression-single-run", "Scenario work 100 -> 140 ms in one run each: far beyond the "
     "assumed noise (5 % sd per run, threshold about 26 ms).", "regressed", work(140.0),
     {"performance/s1-scroll": "regressed"})
pair("perf-within-assumed-noise", "Scenario work 100 -> 115 ms in one run each: above the 10 % "
     "practical tolerance but inside the assumed single-run noise (threshold about 23 ms).", "inconclusive",
     work(115.0), {"performance/s1-scroll": "inconclusive"})
pair("perf-small-gain-detected", "Scenario work 20 -> 12 ms: 40 % faster; legacy 10 ms tolerance "
     "hid it.", "improved", work(12.0, "s2-dom"), {"performance/s2-dom": "improved"})
pair("perf-tiny-change", "Scenario work 5.0 -> 5.8 ms, below the 1 ms floor.", "unchanged",
     work(5.8, "s3-style"))
pair("perf-measured-quiet-regression", "Three runs each, sd 1 ms: 100 -> 115 ms is a real "
     "regression once the noise is measured.", "regressed",
     baseline_runs=[work(99.0), work(100.0), work(101.0)],
     current_runs=[work(114.0), work(115.0), work(116.0)],
     metrics={"performance/s1-scroll": "regressed"})
pair("perf-measured-noisy", "Three runs each, sd 30 ms: a 15 ms shift of the mean is inside the "
     "measured noise.", "inconclusive",
     baseline_runs=[work(70.0), work(100.0), work(130.0)],
     current_runs=[work(85.0), work(115.0), work(145.0)],
     metrics={"performance/s1-scroll": "inconclusive"})
pair("perf-measured-quiet-gain", "Three runs each, sd 0.5 ms: 20 -> 17 ms is a real gain.", "improved",
     baseline_runs=[work(19.5, "s2-dom"), work(20.0, "s2-dom"), work(20.5, "s2-dom")],
     current_runs=[work(16.5, "s2-dom"), work(17.0, "s2-dom"), work(17.5, "s2-dom")],
     metrics={"performance/s2-dom": "improved"})
pair("perf-scenario-fail", "One more FAIL scenario.", "regressed",
     chain(setter("perf", "verdicts", "PASS", 1), setter("perf", "verdicts", "FAIL", 2)),
     {"performance/PASS scenarios": "regressed", "performance/FAIL scenarios": "regressed"})
pair("idle-rss-small", "Idle RSS +4 MB, below the 5 MB tolerance.", "unchanged",
     setter("perf", "idle", "rss_mb", 154.0))
pair("idle-rss-within-noise", "Idle RSS +7 MB: above tolerance, inside the assumed noise "
     "(2 MB sd, threshold 8.5 MB).", "inconclusive",
     setter("perf", "idle", "rss_mb", 157.0), {"idle/RSS MB": "inconclusive"})
pair("idle-rss-regression", "Idle RSS +12 MB.", "regressed",
     setter("perf", "idle", "rss_mb", 162.0), {"idle/RSS MB": "regressed"})
pair("idle-cpu-gain", "Idle CPU 1.0 -> 0.1 %.", "improved",
     setter("perf", "idle", "cpu_pct", 0.1), {"idle/CPU %": "improved"})
pair("compat-one-more-pass", "One Test262 test moves from FAIL to PASS (+0.1 pp); legacy 0.5 pp "
     "tolerance hid it.", "improved",
     chain(setter("compat", "test262", "counts", {"PASS": 901, "FAIL": 99, "SKIP": 50, "ERROR": 0}),
           setter("compat", "test262", "passRate", 90.1)),
     {"compatibility/test262/passRate": "improved", "compatibility/test262/PASS tests": "improved"})
pair("compat-one-regression", "One URL case moves from PASS to FAIL.", "regressed",
     chain(setter("compat", "url", "counts", {"PASS": 399, "FAIL": 101, "SKIP": 0, "ERROR": 0}),
           setter("compat", "url", "passRate", 79.8)),
     {"compatibility/url/passRate": "regressed", "compatibility/url/PASS tests": "regressed"})
pair("compat-suite-revision", "Test262 checkout moved to another commit; the higher rate is not "
     "comparable.", "not_comparable",
     chain(setter("compat", "test262", "suiteCommit", "0123abcd"), setter("compat", "test262", "passRate", 92.0)),
     area_default={"compatibility/test262": ALL})
pair("compat-catalog-size", "Test262 ran with a --limit: fewer tests, higher rate.", "not_comparable",
     chain(setter("compat", "test262", "counts", {"PASS": 450, "FAIL": 30, "SKIP": 20, "ERROR": 0}),
           setter("compat", "test262", "passRate", 93.75)),
     area_default={"compatibility/test262": ALL})
pair("compat-runner-version", "URL runner version changed; verdicts may differ for runner reasons.",
     "not_comparable", setter("compat", "url", "runnerVersion", "0.3.0"),
     area_default={"compatibility/url": ALL})
pair("compat-command", "WPT-style command changed (different directories).", "not_comparable",
     setter("compat", "url", "command", "run_url --limit 100"),
     area_default={"compatibility/url": ALL})
pair("visual-catalog-changed", "Five pages added to the visual catalog; the mean moves for that "
     "reason alone.", "not_comparable",
     chain(setter("context", "visual", "catalog_size", 45), setter("context", "visual", "catalog_digest", "cccccccccccccccc"),
           setter("visual", "categories", "overall", 83.0)),
     area_default={"visual": ALL})
pair("visual-reference-changed", "Chrome reference upgraded.", "not_comparable",
     setter("context", "visual", "reference", "Chrome 142"), area_default={"visual": ALL})
pair("environment-changed", "Different machine class: every area is not comparable.", "not_comparable",
     chain(setter("context", "global", "environment_class", "Linux-aarch64-8cpu-Other CPU"), work(80.0)),
     area_default={"visual": ALL, "performance": ALL, "idle": ALL,
                   "compatibility/test262": ALL, "compatibility/url": ALL})
pair("engine-changed", "Performance measured with QuickJS instead of V8; visual unchanged.",
     "not_comparable", chain(setter("context", "performance", "engine", ["nativax-quickjs"]), work(160.0)),
     area_default={"performance": ALL})
pair("config-viewport-changed", "Performance viewport changed.", "not_comparable",
     setter("context", "performance", "viewport", {"width": 800, "height": 600}),
     area_default={"performance": ALL})
pair("old-baseline-without-context", "The baseline predates context recording; the current run "
     "records it, so nothing can be verified.", "not_comparable",
     baseline_change=lambda s: s.pop("context"),
     area_default={"visual": ALL, "performance": ALL, "idle": ALL,
                   "compatibility/test262": ALL, "compatibility/url": ALL})
pair("metric-missing", "The current run lost the mismatched-pixel metric.", "not_comparable",
     lambda s: s["visual"].pop("mismatched_pct"), {"visual/mismatched %": "not_comparable"})
pair("mixed", "Visual improves, performance regresses: a regression is reported.", "regressed",
     chain(setter("visual", "categories", "overall", 83.0), work(150.0)),
     {"visual/overall": "improved", "performance/s1-scroll": "regressed"})
pair("regression-with-noncomparable-area", "A real performance regression while Test262 is not "
     "comparable: the regression wins.", "regressed",
     chain(work(150.0), setter("compat", "test262", "suiteCommit", "0123abcd")),
     {"performance/s1-scroll": "regressed"}, area_default={"compatibility/test262": ALL})
pair("gain-with-noncomparable-area", "A real visual gain while Test262 is not comparable: no gain "
     "is claimed.", "not_comparable",
     chain(setter("visual", "categories", "overall", 83.0), setter("compat", "test262", "suiteCommit", "0123abcd")),
     {"visual/overall": "improved"}, area_default={"compatibility/test262": ALL})
pair("gain-and-noise", "A real visual gain plus a perf change inside the noise.", "improved",
     chain(setter("visual", "categories", "overall", 83.0), work(115.0)),
     {"visual/overall": "improved", "performance/s1-scroll": "inconclusive"})
pair("no-baseline", "No baseline exists.", "no_baseline", no_baseline=True)


def main():
    out = HERE / "pairs.json"
    out.write_text(json.dumps({
        "description": "Constructed quality-gate snapshot pairs with expected verdicts. "
                       "Generated by build_pairs.py; edit that file, not this one.",
        "pairs": PAIRS,
    }, indent=1) + "\n")
    print(f"{len(PAIRS)} pairs -> {out}")


if __name__ == "__main__":
    main()

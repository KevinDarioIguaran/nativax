#!/usr/bin/env python3
"""Tests for the quality gate: per-metric judgment, comparability,
aggregation of repeated runs, outputs, and the constructed dataset.

    python3 debug/engines/quality_gate/test_quality_gate.py
"""
from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import evaluate_gate  # noqa: E402
import gate_compare as g  # noqa: E402
import quality_gate  # noqa: E402


def base():
    return copy.deepcopy(evaluate_gate.load_pairs()[0]["baseline"])


class JudgeTest(unittest.TestCase):
    def test_below_min_effect_is_unchanged(self):
        self.assertEqual(g.judge(g.VISUAL_SCORE, 80.0, 80.4)[0], "unchanged")

    def test_direction_lower_is_better(self):
        self.assertEqual(g.judge(g.PERF_WORK, 100.0, 50.0)[0], "improved")
        self.assertEqual(g.judge(g.PERF_WORK, 100.0, 200.0)[0], "regressed")

    def test_relative_tolerance_scales_with_value(self):
        # 10 % of 1000 ms is 100 ms: a 60 ms change is unchanged.
        self.assertEqual(g.judge(g.PERF_WORK, 1000.0, 1060.0)[0], "unchanged")

    def test_within_noise_is_inconclusive(self):
        status, numbers = g.judge(g.PERF_WORK, 100.0, 115.0, (10.0, 1), (10.0, 1))
        self.assertEqual(status, "inconclusive")
        self.assertAlmostEqual(numbers["noise_threshold"], 3 * (200 ** 0.5))

    def test_more_runs_shrink_the_noise_term(self):
        self.assertEqual(g.judge(g.PERF_WORK, 100.0, 115.0, (10.0, 25), (10.0, 25))[0], "regressed")


class ComparabilityTest(unittest.TestCase):
    def test_same_context_is_comparable(self):
        ok, reasons, _ = g.comparability(base(), base(), "visual")
        self.assertTrue(ok, reasons)

    def test_key_on_one_side_only_is_not_comparable(self):
        current = base()
        current["context"]["visual"]["extra"] = 1
        ok, reasons, _ = g.comparability(base(), current, "visual")
        self.assertFalse(ok)
        self.assertIn("extra: not recorded in the baseline", reasons)

    def test_compat_total_comes_from_counts(self):
        current = base()
        current["compat"]["url"]["counts"]["SKIP"] = 5
        self.assertFalse(g.comparability(base(), current, "compatibility/url")[0])
        self.assertTrue(g.comparability(base(), current, "compatibility/test262")[0])

    def test_unrecorded_keys_are_reported_as_unverified(self):
        old = base()
        old.pop("context")
        ok, _, unverified = g.comparability(old, copy.deepcopy(old), "visual")
        self.assertTrue(ok)
        self.assertIn("catalog_digest", unverified)


class AggregateTest(unittest.TestCase):
    def test_mean_and_sample_sd(self):
        runs = []
        for value in (90.0, 100.0, 110.0):
            snapshot = base()
            snapshot["perf"]["work"]["s1-scroll"] = value
            runs.append(snapshot)
        merged = g.aggregate(runs)
        self.assertEqual(merged["perf"]["work"]["s1-scroll"], 100.0)
        self.assertEqual(merged["noise"]["performance/s1-scroll"], {"sd": 10.0, "n": 3})
        self.assertEqual(merged["repeats"], 3)

    def test_different_contexts_are_refused(self):
        other = base()
        other["context"]["global"]["environment_class"] = "elsewhere"
        with self.assertRaises(ValueError):
            g.aggregate([base(), other])


class VerdictTest(unittest.TestCase):
    def test_precedence(self):
        self.assertEqual(g.overall({"regressed": 1, "not_comparable": 3}), "regressed")
        self.assertEqual(g.overall({"improved": 2, "not_comparable": 1}), "not_comparable")
        self.assertEqual(g.overall({"improved": 1, "inconclusive": 4}), "improved")
        self.assertEqual(g.overall({"inconclusive": 1}), "inconclusive")
        self.assertEqual(g.overall({}), "unchanged")

    def test_every_status_is_reachable_in_the_dataset(self):
        seen = {p["expected"]["verdict"] for p in evaluate_gate.load_pairs()}
        self.assertTrue(set(g.STATUSES) <= seen, seen)


class DatasetTest(unittest.TestCase):
    def test_pairs_json_is_up_to_date(self):
        sys.path.insert(0, str(evaluate_gate.DATASET))
        import build_pairs  # noqa: E402
        on_disk = json.loads((evaluate_gate.DATASET / "pairs.json").read_text())["pairs"]
        self.assertEqual(json.loads(json.dumps(build_pairs.PAIRS)), on_disk)

    def test_new_gate_matches_every_expectation(self):
        result = evaluate_gate.evaluate(evaluate_gate.load_pairs(), evaluate_gate.run_new)
        self.assertEqual(result["wrong_verdicts"], [])
        self.assertEqual(result["metric_correct"], result["metric_judgments"])

    def test_legacy_gate_is_worse_on_the_same_pairs(self):
        pairs = evaluate_gate.load_pairs()
        new = evaluate_gate.evaluate(pairs, evaluate_gate.run_new)
        legacy = evaluate_gate.evaluate(pairs, evaluate_gate.run_legacy)
        self.assertLess(legacy["verdict_accuracy"], new["verdict_accuracy"])


class OutputTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        pair = evaluate_gate.load_pairs()[1]  # visual-real-gain
        self.baseline = self.tmp / "baseline.json"
        self.current = self.tmp / "current.json"
        self.baseline.write_text(json.dumps(pair["baseline"]))
        self.current.write_text(json.dumps(pair["current"]))
        self.legacy = [quality_gate.LEGACY_JSON, quality_gate.LEGACY_MD, quality_gate.BASELINE_DEFAULT]
        self.before = {p: (p.stat().st_mtime_ns if p.exists() else None) for p in self.legacy}

    def tearDown(self):
        after = {p: (p.stat().st_mtime_ns if p.exists() else None) for p in self.legacy}
        self.assertEqual(self.before, after, "a tracked report was modified")

    def gate(self, *extra):
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return quality_gate.main(["--baseline", str(self.baseline),
                                      "--current", str(self.current), *extra])

    def test_default_writes_nothing(self):
        self.assertEqual(self.gate(), 0)
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()), ["baseline.json", "current.json"])

    def test_out_dir(self):
        out = self.tmp / "report"
        self.assertEqual(self.gate("--out", str(out)), 0)
        result = json.loads((out / "gate.json").read_text())
        self.assertEqual(result["comparison"]["verdict"], "improved")
        self.assertTrue((out / "gate.md").read_text().startswith("# Quality gate"))
        self.assertTrue((out / "snapshot.json").exists())

    def test_write_baseline_is_explicit(self):
        target = self.tmp / "new-baseline.json"
        self.gate("--write-baseline", str(target))
        self.assertEqual(json.loads(target.read_text())["visual"]["categories"]["overall"], 82.0)

    def test_exit_codes(self):
        data = json.loads(self.current.read_text())
        data["context"]["global"]["environment_class"] = "elsewhere"
        self.current.write_text(json.dumps(data))
        self.assertEqual(self.gate(), 4)
        data = json.loads(self.baseline.read_text())
        data["visual"]["categories"]["overall"] = 90.0
        self.baseline.write_text(json.dumps(data))
        self.current.write_text(json.dumps(data | {"visual": dict(data["visual"], categories=dict(
            data["visual"]["categories"], overall=85.0))}))
        self.assertEqual(self.gate(), 2)

    def test_save_baseline_needs_legacy_flag(self):
        import contextlib
        import io
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            quality_gate.main(["--save-baseline"])


if __name__ == "__main__":
    unittest.main()

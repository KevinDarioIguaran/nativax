#!/usr/bin/env python3
"""Tests for area_trends (history verdicts of conformance, memory, security).

    python3 debug/logic/history/test_area_trends.py
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import area_trends as T  # noqa: E402


def write(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data if isinstance(data, str) else json.dumps(data))


class ConformanceTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="nx-trend-"))
        self.addCleanup(shutil.rmtree, self.dir, True)

    def run_(self, suite, stamp, statuses):
        name = f"{suite}-{stamp}"
        write(self.dir / f"{name}.jsonl", "\n".join(json.dumps({"id": i, "status": s}) for i, s in statuses.items()))
        passed = sum(1 for s in statuses.values() if s == "PASS")
        write(self.dir / f"{name}.summary.json", {
            "suite": suite, "startedAt": stamp, "counts": {"PASS": passed, "FAIL": len(statuses) - passed},
            "total": len(statuses), "passRate": 100 * passed / len(statuses), "resultsFile": f"{name}.jsonl"})

    def test_improved_regressed_mixed_and_not_comparable(self):
        self.run_("url", "2026-10-01T000000", {"a": "PASS", "b": "FAIL", "c": "FAIL"})
        self.run_("url", "2026-10-02T000000", {"a": "PASS", "b": "PASS", "c": "FAIL"})
        self.run_("dom", "2026-10-01T000000", {"a": "PASS", "b": "PASS"})
        self.run_("dom", "2026-10-02T000000", {"a": "PASS", "b": "FAIL"})
        self.run_("css", "2026-10-01T000000", {"a": "PASS", "b": "FAIL"})
        self.run_("css", "2026-10-02T000000", {"a": "FAIL", "b": "PASS"})
        self.run_("tree", "2026-10-01T000000", {"a": "PASS"})
        self.run_("tree", "2026-10-02T000000", {"a": "PASS", "b": "PASS"})     # other size: not compared
        st = T.conformance_status(T.conformance_series(self.dir))
        by = {s["suite"]: s for s in st["suites"]}
        self.assertEqual(by["url"]["verdict"], T.IMPROVED)
        self.assertEqual(by["url"]["fixed"], ["b"])
        self.assertEqual(by["dom"]["verdict"], T.REGRESSED)
        self.assertEqual(by["dom"]["broken"], ["b"])
        self.assertEqual(by["css"]["verdict"], T.MIXED)
        self.assertEqual(by["tree"]["verdict"], T.NOT_ENOUGH)
        self.assertEqual(by["tree"]["skipped"], 1)
        self.assertEqual(st["verdict"], T.REGRESSED)

    def test_same_and_empty(self):
        self.assertEqual(T.conformance_status(T.conformance_series(self.dir / "missing"))["verdict"], T.NOT_ENOUGH)
        self.run_("url", "2026-10-01T000000", {"a": "PASS", "b": "FAIL"})
        self.run_("url", "2026-10-02T000000", {"a": "PASS", "b": "FAIL"})
        st = T.conformance_status(T.conformance_series(self.dir))
        self.assertEqual(st["verdict"], T.SAME)
        self.assertEqual(st["suites"][0]["trend"], [("2026-10-01T000000", 50.0), ("2026-10-02T000000", 50.0)])


class BenchTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="nx-bench-"))
        self.addCleanup(shutil.rmtree, self.dir, True)

    def run_(self, name, statuses):
        write(self.dir / name / "leaks-x.json", {"metadata": {"timestamp": name},
              "results": [{"id": i, "status": s} for i, s in statuses.items()]})

    def test_only_runs_are_ignored_and_flips_decide(self):
        self.run_("20261001T000000Z", {"a": "pass", "b": "fail", "c": "skip"})
        self.run_("20261002T000000Z", {"a": "pass", "b": "pass", "c": "skip"})
        self.run_("20261003T000000Z", {"a": "fail"})                        # --only run
        st = T.bench_status(T.bench_series(self.dir, "leaks"))
        self.assertEqual(st["verdict"], T.IMPROVED)
        self.assertEqual(st["fixed"], ["b"])
        self.assertEqual(st["rate"], 100.0)                                  # SKIP left out
        self.assertEqual(st["run"], "20261002T000000Z")
        self.assertEqual(st["skipped"], 1)

    def test_any_broken_case_is_a_regression(self):
        self.run_("20261001T000000Z", {"a": "pass", "b": "pass"})
        self.run_("20261002T000000Z", {"a": "pass", "b": "error"})
        st = T.bench_status(T.bench_series(self.dir, "leaks"))
        self.assertEqual(st["verdict"], T.REGRESSED)
        self.assertEqual(st["fail"], ["b"])

    def test_single_run_is_not_enough(self):
        self.run_("20261001T000000Z", {"a": "pass"})
        self.assertEqual(T.bench_status(T.bench_series(self.dir, "leaks"))["verdict"], T.NOT_ENOUGH)
        self.assertEqual(T.bench_status([])["verdict"], T.NOT_ENOUGH)


if __name__ == "__main__":
    unittest.main(verbosity=1)

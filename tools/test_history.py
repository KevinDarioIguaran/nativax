import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import history


class HistoryTest(unittest.TestCase):
    def test_record_and_list(self):
        source = ROOT / ".perf" / "live-smoke" / "results.json"
        if not source.exists():
            self.skipTest("no perf smoke result")
        out = ROOT / ".perf" / "history-test"
        try:
            path = history.record("perf", source, out)
            self.assertTrue(path.exists())
            runs = history.list_runs("perf", out)
            self.assertEqual(len(runs), 1)
            self.assertIn("scenarios", runs[0]["summary"])
        finally:
            if out.exists():
                import shutil
                shutil.rmtree(out)

    def test_compare_detects_delta(self):
        old = {"rows": [{"page": "a", "overall": 50, "position": 40,
                         "layout": 50, "color": 60, "design": 90,
                         "mismatched_pct": 20, "ink_mismatch_pct": 50,
                         "mean_delta_e": 2}]}
        new = {"rows": [{"page": "a", "overall": 60, "position": 50,
                         "layout": 60, "color": 70, "design": 95,
                         "mismatched_pct": 10, "ink_mismatch_pct": 40,
                         "mean_delta_e": 1.5},
                        {"page": "b", "overall": 80, "position": 70,
                         "layout": 80, "color": 85, "design": 95,
                         "mismatched_pct": 5, "ink_mismatch_pct": 10,
                         "mean_delta_e": 1}]}
        deltas = history._visual_delta(old, new)
        self.assertEqual(len(deltas), 1)
        self.assertEqual(deltas[0]["id"], "a")
        self.assertEqual(deltas[0]["overall"], 10)

    def test_delta_none_for_non_numeric(self):
        self.assertIsNone(history._delta("x", 1))

    def test_perf_delta(self):
        old = {"results": [{
            "scenario": "s", "verdict": "FAIL",
            "nativax": {"status": "ok", "scenario_ms": 100, "render_ms": 0,
                        "frame_ms": {"p95": 40}, "rss_peak_mb": 10},
            "chromium": {"status": "ok", "scenario_ms": 10, "render_ms": 0,
                         "frame_ms": {"p95": 1}, "rss_peak_mb": 5},
        }]}
        new = {"results": [{
            "scenario": "s", "verdict": "WARN",
            "nativax": {"status": "ok", "scenario_ms": 80, "render_ms": 0,
                        "frame_ms": {"p95": 30}, "rss_peak_mb": 9},
            "chromium": {"status": "ok", "scenario_ms": 10, "render_ms": 0,
                         "frame_ms": {"p95": 1}, "rss_peak_mb": 5},
        }]}
        deltas = history._perf_delta(old, new)
        self.assertEqual(len(deltas), 1)
        self.assertAlmostEqual(deltas[0]["work_ratio"], -2.0, places=3)


if __name__ == "__main__":
    unittest.main()

"""Tests for the headless quality gate: verdicts and report output."""
import contextlib
import hashlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import quality_gate

ROOT = quality_gate.ROOT
TRACKED = (
    ROOT / "progress" / "reports" / "quality-gate-latest.json",
    ROOT / "progress" / "reports" / "quality-gate-latest.md",
)


def snapshot(overall=80.0, rss=200.0, pass_pages=40, fail_pages=5, pass_rate=75.0):
    return {
        "generated_at": "2026-10-25T12:00:00+00:00",
        "visual": {
            "source": "x",
            "pages": pass_pages + fail_pages,
            "verdicts": {"PASS": pass_pages, "WARN": 0, "FAIL": fail_pages,
                         "INVALID": 0},
            "categories": {"overall": overall, "position": overall,
                           "layout": overall, "color": overall,
                           "design": overall},
            "pixels": 1000,
            "mismatched_pixels": 100,
            "mismatched_pct": 10.0,
            "mean_delta_e": 2.0,
            "mean_ink_pct": 10.0,
            "images": 90,
            "worst": [],
        },
        "perf": {
            "scenarios": 10,
            "verdicts": {"PASS": 7, "WARN": 1, "FAIL": 2, "INVALID": 0},
            "work": {"list.1000": 100.0},
            "ratios": {"list.1000": 1.5},
            "idle": {"rss_mb": rss, "cpu_pct": 0.5, "gpu_pct": None,
                     "status": "ok"},
        },
        "compat": {"test262": {"suite": "test262", "passRate": 70.0,
                               "counts": {}, "command": None,
                               "startedAt": None, "path": "x"}},
        "baseline_path": "x",
    }


def file_hashes():
    out = {}
    for path in TRACKED:
        try:
            out[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError:
            out[str(path)] = None
    return out


class CompareTest(unittest.TestCase):
    def test_no_baseline_is_baseline(self):
        result = quality_gate.compare(snapshot(), None)
        self.assertEqual(result["verdict"], "BASELINE")

    def test_identical_snapshot_is_equal(self):
        snap = snapshot()
        baseline = dict(snap)
        result = quality_gate.compare(snap, baseline)
        self.assertEqual(result["verdict"], "EQUAL")
        self.assertEqual(result["regressions"], [])

    def test_only_improvement_is_better(self):
        baseline = snapshot(overall=70.0, rss=240.0, pass_pages=30,
                            fail_pages=15, pass_rate=60.0)
        result = quality_gate.compare(snapshot(overall=80.0, rss=200.0,
                                                pass_pages=40, fail_pages=5,
                                                pass_rate=75.0), baseline)
        self.assertEqual(result["verdict"], "BETTER")
        self.assertTrue(result["improvements"])
        self.assertEqual(result["regressions"], [])

    def test_only_regression_is_worse(self):
        baseline = snapshot(overall=80.0, rss=200.0, pass_pages=40,
                            fail_pages=5, pass_rate=75.0)
        result = quality_gate.compare(snapshot(overall=70.0, rss=240.0,
                                                pass_pages=30, fail_pages=15,
                                                pass_rate=60.0), baseline)
        self.assertEqual(result["verdict"], "WORSE")

    def test_mixed_changes_are_mixed(self):
        baseline = snapshot(overall=80.0, rss=200.0, pass_pages=40,
                            fail_pages=5, pass_rate=75.0)
        # Better visual, worse idle.
        current = snapshot(overall=85.0, rss=240.0, pass_pages=45,
                           fail_pages=0, pass_rate=80.0)
        result = quality_gate.compare(current, baseline)
        self.assertEqual(result["verdict"], "MIXED")
        self.assertTrue(result["regressions"])
        self.assertTrue(result["improvements"])

    def test_non_comparable_metrics_are_skipped_not_guessed(self):
        baseline = snapshot()
        baseline["visual"] = None
        result = quality_gate.compare(snapshot(), baseline)
        # No visual numbers on either side: nothing is invented.
        self.assertTrue(all(c["area"] != "visual" for c in result["changes"]))


class ReportOutputTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nativax-gate-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_write_reports_targets_the_given_directory(self):
        snap = snapshot()
        comparison = quality_gate.compare(snap, None)
        json_path, md_path = quality_gate.write_reports(self.tmp / "out", snap,
                                                        comparison)
        self.assertEqual(json_path.parent, self.tmp / "out")
        self.assertTrue(json_path.exists())
        self.assertTrue(md_path.exists())
        data = json.loads(json_path.read_text())
        self.assertEqual(data["comparison"]["verdict"], "BASELINE")
        self.assertIn("BASELINE", md_path.read_text())

    def test_main_writes_only_to_out_dir_and_keeps_tracked_reports(self):
        before = file_hashes()
        snap = snapshot()

        def fake_visual():
            return snap["visual"]

        def fake_perf():
            return snap["perf"]

        def fake_compat():
            return snap["compat"]

        originals = (quality_gate.visual_snapshot, quality_gate.perf_snapshot,
                     quality_gate.compat_snapshot)
        quality_gate.visual_snapshot = fake_visual
        quality_gate.perf_snapshot = fake_perf
        quality_gate.compat_snapshot = fake_compat
        try:
            out_dir = self.tmp / "runs" / "gate"
            baseline = self.tmp / "baseline.json"
            with contextlib.redirect_stdout(io.StringIO()):
                code = quality_gate.main([
                    "--json", "--compat", "none",
                    "--baseline", str(baseline),
                    "--out-dir", str(out_dir),
                ])
            self.assertEqual(code, 0)
            self.assertTrue((out_dir / "quality-gate-latest.json").exists())
            self.assertTrue((out_dir / "quality-gate-latest.md").exists())
            self.assertTrue(baseline.exists())

            # Worse run against that baseline: exit 2 and reports in out_dir.
            worse = snapshot(overall=60.0, rss=240.0, pass_pages=20,
                             fail_pages=25, pass_rate=50.0)

            quality_gate.visual_snapshot = lambda: worse["visual"]
            quality_gate.perf_snapshot = lambda: worse["perf"]
            quality_gate.compat_snapshot = lambda: worse["compat"]
            with contextlib.redirect_stdout(io.StringIO()):
                code = quality_gate.main([
                    "--json", "--compat", "none",
                    "--baseline", str(baseline),
                    "--out-dir", str(out_dir),
                ])
            self.assertEqual(code, 2)
            data = json.loads((out_dir / "quality-gate-latest.json").read_text())
            self.assertEqual(data["comparison"]["verdict"], "WORSE")
        finally:
            (quality_gate.visual_snapshot, quality_gate.perf_snapshot,
             quality_gate.compat_snapshot) = originals
        self.assertEqual(file_hashes(), before,
                         "the gate must not rewrite tracked progress/reports")


if __name__ == "__main__":
    unittest.main()

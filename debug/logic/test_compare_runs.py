"""Tests for the run comparison algorithm (debug/logic/compare_runs.py)."""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compare_runs  # noqa: E402
import storage  # noqa: E402


class CompareRunsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nativax-compare-"))
        self.addCleanup(lambda: (storage._thaw(self.tmp), shutil.rmtree(self.tmp, True)))
        self.root = self.tmp / "runs"

    def visual_run(self, scores, argv=("visual_check.dart", "--suite", "a")):
        src = self.tmp / f"src-{len(list(self.tmp.iterdir()))}"
        src.mkdir()
        rows = [{"page": p, "overall": s} for p, s in scores.items()]
        (src / "results.json").write_text(json.dumps({"rows": rows}))
        return storage.archive("visual", src, engine="visual_check.dart", argv=list(argv),
                               runs_root=self.root)

    def perf_run(self, works):
        src = self.tmp / f"src-{len(list(self.tmp.iterdir()))}"
        src.mkdir()
        results = [{"scenario": s, "nativax": {"status": "ok", "scenario_ms": n, "render_ms": 0},
                    "chromium": {"status": "ok", "scenario_ms": c, "render_ms": 0}}
                   for s, (n, c) in works.items()]
        (src / "results.json").write_text(json.dumps({"results": results}))
        return storage.archive("perf", src, engine="perf.dart", argv=["perf.dart", "run"],
                               runs_root=self.root)

    def test_improved_regressed_unchanged(self):
        a = self.visual_run({"p1": 80.0, "p2": 90.0, "p3": 70.0})
        b = self.visual_run({"p1": 85.0, "p2": 90.3, "p3": 70.0})
        r = compare_runs.compare("visual", a, b)
        self.assertEqual(r["status"], "improved")
        by = {i["id"]: i["status"] for i in r["items"]}
        self.assertEqual(by, {"p1": "improved", "p2": "unchanged", "p3": "unchanged"})
        c = self.visual_run({"p1": 85.0, "p2": 80.0, "p3": 99.0})
        self.assertEqual(compare_runs.compare("visual", b, c)["status"], "regressed")

    def test_dropped_items_are_not_an_improvement(self):
        a = self.visual_run({"p1": 50.0, "p2": 60.0})
        b = self.visual_run({"p1": 50.0})
        r = compare_runs.compare("visual", a, b)
        self.assertEqual(r["status"], "unchanged")
        self.assertEqual(r["counts"]["removed"], 1)
        d = self.visual_run({"other": 99.0})
        self.assertEqual(compare_runs.compare("visual", a, d)["status"], "inconclusive")

    def test_different_configuration_is_not_comparable(self):
        a = self.visual_run({"p1": 50.0})
        b = self.visual_run({"p1": 99.0}, argv=("visual_check.dart", "--suite", "b"))
        r = compare_runs.compare("visual", a, b)
        self.assertEqual(r["status"], "not_comparable")
        self.assertEqual(r["items"], [])

    def test_legacy_manifest_is_inconclusive(self):
        a = self.visual_run({"p1": 50.0})
        legacy = self.root / "visual" / "20260101T000000Z-abcdef1"
        legacy.mkdir()
        (legacy / "manifest.json").write_text(json.dumps({
            "schema_version": "1.0", "run_id": legacy.name, "area": "visual", "engine": None,
            "status": "completed", "archived_at": "2026-01-01T00:00:00Z"}))
        r = compare_runs.compare("visual", legacy, a)
        self.assertEqual(r["status"], "inconclusive")
        self.assertIn("lineage unknown", r["reason"])

    def test_perf_lower_ratio_is_better_with_relative_noise(self):
        a = self.perf_run({"s1": (100, 50), "s2": (100, 50)})
        b = self.perf_run({"s1": (60, 50), "s2": (110, 50)})   # 2.0 -> 1.2 ; 2.0 -> 2.2 (+10 %)
        r = compare_runs.compare("perf", a, b)
        by = {i["id"]: i["status"] for i in r["items"]}
        self.assertEqual(by, {"s1": "improved", "s2": "unchanged"})
        self.assertEqual(r["noise"], {"kind": "relative", "value": 0.15, "source": "default"})
        self.assertEqual(compare_runs.compare("perf", a, b, noise=0.05)["status"], "regressed")

    def test_record_appends_history_to_newer_run_only(self):
        a = self.visual_run({"p1": 50.0})
        b = self.visual_run({"p1": 60.0})
        r = compare_runs.compare("visual", a, b)
        compare_runs.record("visual", a, b, r)
        kinds_b = [h["kind"] for h in storage.history(b)]
        self.assertIn("comparison", kinds_b)
        self.assertNotIn("comparison", [h["kind"] for h in storage.history(a)])
        self.assertEqual(storage.verify(b), [])   # evidence untouched


if __name__ == "__main__":
    unittest.main(verbosity=1)

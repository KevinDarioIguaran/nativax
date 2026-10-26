"""Tests for the compact context/index tool (debug/logic/context.py)."""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import context


def write_manifest(root: Path, area: str, run_id: str, **extra) -> Path:
    run = root / "debug" / "benchmarks" / area / run_id
    run.mkdir(parents=True)
    manifest = {
        "schema_version": "1.0",
        "run_id": run_id,
        "area": area,
        "engine": "nativa_test",
        "status": "completed",
        "archived_at": "2026-10-25T12:00:00+00:00",
        "git_revision": "abc1234",
        "argv": ["test"],
        "source": str(run),
        "evidence": {"files": 2, "bytes": 123},
        "reports": [],
        "notes": None,
    }
    manifest.update(extra)
    (run / "manifest.json").write_text(json.dumps(manifest))
    return run


def write_summary(directory: Path, name: str, suite: str, started: str,
                  counts: dict, pass_rate: float, **extra) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    data = {
        "suite": suite,
        "startedAt": started,
        "durationMs": 10,
        "counts": counts,
        "passRate": pass_rate,
        **extra,
    }
    path = directory / name
    path.write_text(json.dumps(data))
    return path


class ContextTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nativax-context-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_inventory_reports_files_bytes_and_missing_paths(self):
        (self.tmp / "docs").mkdir()
        (self.tmp / "docs" / "a.md").write_text("hello\n")
        (self.tmp / "main.dart").write_text("void main() {}\n")
        result = context.inventory(self.tmp)
        self.assertEqual(result["schema"], context.INVENTORY_SCHEMA)
        self.assertEqual(result["files"], 2)
        self.assertGreater(result["bytes"], 0)
        names = {row["name"] for row in result["byTop"]}
        self.assertEqual(names, {"docs", "(root)"})
        self.assertEqual(result["missing"], 0)

    def test_scan_runs_accepts_valid_manifests_and_skips_invalid(self):
        write_manifest(self.tmp, "microbench", "20261025T120000Z-abc1234")
        bad = self.tmp / "debug" / "benchmarks" / "leaks" / "20261025T130000Z"
        bad.mkdir(parents=True)
        (bad / "manifest.json").write_text('{"not": "a manifest"}')
        records = context.scan_runs(self.tmp)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["schema"], context.RUN_SCHEMA)
        self.assertEqual(records[0]["runId"], "20261025T120000Z-abc1234")
        self.assertEqual(records[0]["kind"], "benchmark")

    def test_conformance_index_keeps_results_out_of_metadata(self):
        results = self.tmp / "debug" / "artifacts" / "conformance" / "results"
        write_summary(
            results, "wpt-20261025T100000.summary.json", "wpt",
            "2026-10-25T10:00:00", {"PASS": 3, "FAIL": 1, "SKIP": 0, "ERROR": 0},
            75,
        )
        write_summary(
            results, "wpt-20261025T110000.summary.json", "wpt",
            "2026-10-25T11:00:00", {"PASS": 4, "FAIL": 0, "SKIP": 0, "ERROR": 0},
            100,
            resultsFile="wpt-20261025T110000.jsonl",
        )
        records = context.scan_conformance(results, self.tmp)
        self.assertEqual(len(records), 2)
        self.assertNotIn("results", records[0])
        self.assertEqual(records[0]["total"], 4)
        latest = context.latest_by_suite(records)
        self.assertEqual(len(latest), 1)
        self.assertEqual(latest[0]["passRate"], 100)
        self.assertEqual(latest[0]["path"],
                         "debug/artifacts/conformance/results/wpt-20261025T110000.summary.json")

    def test_write_indexes_round_trips_and_docs_are_indexed(self):
        write_manifest(self.tmp, "security", "20261025T120000Z")
        (self.tmp / "docs").mkdir()
        (self.tmp / "docs" / "guide.md").write_text("# Guide\n\n## Limits\n")
        written = context.write_indexes(self.tmp)
        self.assertIn("runs", written)
        runs = context._read_index("runs", self.tmp)
        self.assertEqual(runs[0]["area"], "security")
        docs = context._read_index("docs", self.tmp)
        guide = next(row for row in docs if row["path"] == "docs/guide.md")
        self.assertEqual(guide["title"], "Guide")
        self.assertEqual(guide["headings"], ["Limits"])

    def test_brief_fits_a_budget_and_reports_truncation(self):
        write_manifest(self.tmp, "microbench", "20261025T120000Z")
        (self.tmp / "docs").mkdir()
        for index in range(20):
            (self.tmp / "docs" / f"doc-{index:02d}.md").write_text(
                f"# Doc {index}\n\n## Section\n")
        payload = context.brief(self.tmp, budget=500)
        self.assertLessEqual(payload["estimatedTokens"], 500)
        self.assertEqual(payload["schema"], context.BRIEF_SCHEMA)
        self.assertIn("truncated", payload)
        self.assertTrue(payload["truncated"])

    def test_measure_reports_sizes_and_token_estimates(self):
        (self.tmp / "a.txt").write_text("1234\n")
        (self.tmp / "b.txt").write_text("x" * 40 + "\n")
        result = context.measure(["a.txt", "b.txt"], self.tmp)
        self.assertEqual(result["schema"], context.MEASURE_SCHEMA)
        self.assertEqual(result["totalBytes"], 46)
        self.assertEqual(len(result["files"]), 2)
        self.assertGreater(result["totalTokens"], 0)
        self.assertIsNotNone(result["tokenizer"])


if __name__ == "__main__":
    unittest.main()

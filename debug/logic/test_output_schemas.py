"""Schema checks for the compact output formats (no live artifacts required)."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from json_validate import validate  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SUMMARY_SCHEMA = (
    ROOT / "debug" / "engines" / "compatibility" / "schemas" / "run-summary.schema.json"
)
RUN_INDEX_SCHEMA = ROOT / "debug" / "logic" / "schemas" / "run-index.schema.json"
CONFORMANCE_INDEX_SCHEMA = (
    ROOT / "debug" / "logic" / "schemas" / "conformance-index.schema.json"
)


def summary(**overrides):
    data = {
        "suite": "wpt-url",
        "startedAt": "2026-10-25T22:10:27",
        "durationMs": 194,
        "counts": {"PASS": 665, "FAIL": 231, "SKIP": 0, "ERROR": 0},
        "total": 896,
        "passRate": 74.21875,
        "resultsFile": "wpt-url-20261025T221027.jsonl",
    }
    data.update(overrides)
    return data


class OutputSchemaTest(unittest.TestCase):
    def test_compact_summary_is_valid(self):
        schema = json.loads(SUMMARY_SCHEMA.read_text())
        self.assertEqual(validate(summary(), schema), [])

    def test_missing_counts_or_duplicate_results_shape_is_rejected(self):
        schema = json.loads(SUMMARY_SCHEMA.read_text())
        broken = summary()
        broken.pop("counts")
        self.assertTrue(validate(broken, schema))
        broken = summary(counts={"PASS": 1, "FAIL": 0, "SKIP": 0})
        self.assertTrue(validate(broken, schema))
        broken = summary(extra="not allowed")
        self.assertTrue(validate(broken, schema))

    def test_historical_results_array_is_read_but_not_current_output(self):
        schema = json.loads(SUMMARY_SCHEMA.read_text())
        legacy = summary()
        legacy.pop("resultsFile")
        legacy.pop("total")
        legacy["results"] = [{"id": "a", "status": "pass"}]
        # The current schema needs total; historical files are read, not
        # re-validated. Document that distinction instead of pretending the
        # legacy shape is current output.
        self.assertTrue(validate(legacy, schema))

    def test_derived_index_records_validate(self):
        run_schema = json.loads(RUN_INDEX_SCHEMA.read_text())
        run = {
            "schema": "nativax.run.v1",
            "runId": "20261025T120000Z-abc1234",
            "area": "microbench",
            "kind": "benchmark",
            "status": "completed",
            "engine": "nativa_benchmark",
            "revision": "abc1234",
            "archivedAt": "2026-10-25T12:00:00Z",
            "files": 2,
            "bytes": 123,
            "source": "debug/benchmarks/microbench/20261025T120000Z-abc1234",
            "path": "debug/benchmarks/microbench/20261025T120000Z-abc1234",
        }
        self.assertEqual(validate(run, run_schema), [])
        self.assertTrue(validate({**run, "kind": "unknown"}, run_schema))

        conformance_schema = json.loads(CONFORMANCE_INDEX_SCHEMA.read_text())
        conformance = {
            "schema": "nativax.conformance.run.v1",
            "suite": "wpt-url",
            "runKey": "wpt-url:run_url",
            "startedAt": "2026-10-25T22:10:27",
            "durationMs": 194,
            "counts": {"PASS": 665, "FAIL": 231, "SKIP": 0, "ERROR": 0},
            "total": 896,
            "passRate": 74.21875,
            "command": "run_url",
            "resultsFile": "wpt-url-20261025T221027.jsonl",
            "bytes": 289,
            "path": "debug/artifacts/conformance/results/wpt-url-20261025T221027.summary.json",
        }
        self.assertEqual(validate(conformance, conformance_schema), [])
        self.assertTrue(validate({**conformance, "total": -1}, conformance_schema))


if __name__ == "__main__":
    unittest.main()

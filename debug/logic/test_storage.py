"""Tests for the immutable per-run storage layer (phase 4: storage/schemas)."""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storage

OFFSET_TS = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([+-]\d{2}:\d{2}|Z)$"
)


def make_source(root: Path, name: str = "latest") -> Path:
    src = root / name
    (src / "pages").mkdir(parents=True)
    (src / "results.json").write_text('{"rows": []}\n')
    (src / "pages" / "index.png").write_bytes(b"\x89PNG-fake")
    return src


class StorageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nativax-storage-"))
        self.addCleanup(self._cleanup)
        self.runs_root = self.tmp / ".runs"

    def _cleanup(self):
        if self.tmp.exists():
            storage._thaw(self.tmp)
        shutil.rmtree(self.tmp, True)

    # ------------------------------------------------------------ schema
    def test_schema_is_versioned_and_declares_required_fields(self):
        schema = storage.load_schema()
        self.assertEqual(schema["properties"]["schema_version"]["enum"], ["1.0", "1.1"])
        self.assertEqual(
            sorted(schema["required"]),
            sorted(["schema_version", "run_id", "area", "engine", "status",
                    "archived_at"]),
        )
        self.assertEqual(storage.SCHEMA_VERSION, "1.1")
        self.assertTrue(storage.SCHEMA_PATH.exists())

    def test_check_manifest_accepts_a_real_manifest_and_rejects_mutations(self):
        src = make_source(self.tmp)
        run_dir = storage.archive("visual", src, engine="visual_check.dart",
                                  argv=["dart", "run", "visual_check.dart"],
                                  runs_root=self.runs_root)
        manifest = json.loads((run_dir / "manifest.json").read_text())
        self.assertEqual(storage.check_manifest(manifest), [])

        broken = dict(manifest)
        broken.pop("area")
        self.assertTrue(storage.check_manifest(broken))

        broken = dict(manifest)
        broken["status"] = "running"
        self.assertTrue(storage.check_manifest(broken))

        broken = dict(manifest)
        broken["archived_at"] = "25-10-2026 21:00:00"
        self.assertTrue(storage.check_manifest(broken))

        broken = dict(manifest)
        broken["extra_field"] = 1
        self.assertTrue(storage.check_manifest(broken))

        broken = dict(manifest)
        broken["run_id"] = "not-a-run-id"
        self.assertTrue(storage.check_manifest(broken))

    # ------------------------------------------------------------ archive
    def test_archive_copies_evidence_and_keeps_the_source(self):
        src = make_source(self.tmp)
        run_dir = storage.archive(
            "visual", src, engine="visual_check.dart",
            argv=["dart", "run", "check", "--out", str(src)],
            runs_root=self.runs_root,
        )
        self.assertTrue((run_dir / "evidence" / "results.json").exists())
        self.assertEqual(
            (run_dir / "evidence" / "pages" / "index.png").read_bytes(),
            b"\x89PNG-fake",
        )
        self.assertTrue((src / "results.json").exists(),
                        "the live directory must survive archiving")
        manifest = storage.load_manifest(run_dir)
        self.assertIsNotNone(manifest)
        self.assertEqual(manifest["status"], "completed")
        self.assertEqual(manifest["engine"], "visual_check.dart")
        self.assertEqual(manifest["evidence"]["files"], 2)
        self.assertGreater(manifest["evidence"]["bytes"], 0)
        self.assertEqual(manifest["argv"][0], "dart")
        self.assertTrue(OFFSET_TS.match(manifest["archived_at"]),
                        f"archived_at must carry an offset: {manifest['archived_at']}")

    def test_run_ids_are_unique_and_sort_newest_first(self):
        src = make_source(self.tmp)
        first = storage.archive("perf", src, runs_root=self.runs_root)
        second = storage.archive("perf", src, runs_root=self.runs_root)
        self.assertNotEqual(first.name, second.name)
        listed = storage.runs("perf", self.runs_root)
        self.assertEqual(listed, [second, first])
        self.assertEqual(storage.latest_run("perf", self.runs_root), second)
        # The first run is untouched after the second one is archived.
        self.assertEqual(storage.load_manifest(first)["run_id"], first.name)

    def test_archive_rejects_unknown_status_without_leaving_a_run(self):
        src = make_source(self.tmp)
        with self.assertRaises(ValueError):
            storage.archive("perf", src, status="running",
                            runs_root=self.runs_root)
        self.assertEqual(storage.runs("perf", self.runs_root), [])

    def test_archive_missing_source_raises(self):
        with self.assertRaises(FileNotFoundError):
            storage.archive("perf", self.tmp / "does-not-exist",
                            runs_root=self.runs_root)
        self.assertEqual(storage.runs("perf", self.runs_root), [])

    # ------------------------------------------------------------ reports
    def test_reports_are_independent_per_run(self):
        visual_src = make_source(self.tmp, "visual-latest")
        perf_src = make_source(self.tmp, "perf-latest")
        visual_report = self.tmp / "report-visual.md"
        perf_report = self.tmp / "report-perf.md"
        visual_report.write_text("# visual\n")
        perf_report.write_text("# perf\n")

        vrun = storage.archive("visual", visual_src, reports=[visual_report],
                               runs_root=self.runs_root)
        prun = storage.archive("perf", perf_src, reports=[perf_report],
                               runs_root=self.runs_root)

        vfiles = sorted(p.name for p in (vrun / "reports").iterdir())
        pfiles = sorted(p.name for p in (prun / "reports").iterdir())
        self.assertEqual(vfiles, ["report-visual.md"])
        self.assertEqual(pfiles, ["report-perf.md"])
        self.assertEqual((vrun / "reports" / "report-visual.md").read_text(),
                         "# visual\n")
        # A missing report is skipped, not an error.
        run = storage.archive("games", visual_src, reports=[self.tmp / "nope.md"],
                              runs_root=self.runs_root)
        self.assertEqual(storage.load_manifest(run)["reports"], [])

    # ------------------------------------------------------------ manifests
    def test_load_manifest_rejects_corrupt_or_schema_invalid_files(self):
        src = make_source(self.tmp)
        run_dir = storage.archive("visual", src, runs_root=self.runs_root)
        os.chmod(run_dir / "manifest.json", 0o644)  # archived files are read-only
        (run_dir / "manifest.json").write_text("{ not json")
        self.assertIsNone(storage.load_manifest(run_dir))

        (run_dir / "manifest.json").write_text(json.dumps({"schema_version": "1.0"}))
        self.assertIsNone(storage.load_manifest(run_dir))

        self.assertIsNone(storage.load_manifest(self.tmp / "missing"))

    def test_manifest_lists_the_copied_report_path(self):
        src = make_source(self.tmp)
        report = self.tmp / "report-visual.md"
        report.write_text("hola\n")
        run_dir = storage.archive("visual", src, reports=[report],
                                  runs_root=self.runs_root)
        manifest = storage.load_manifest(run_dir)
        self.assertEqual(len(manifest["reports"]), 1)
        rel = manifest["reports"][0]
        self.assertTrue(rel.startswith("reports/"))
        self.assertTrue((run_dir / rel).exists())

    # ------------------------------------------------------------ retention
    def test_prune_keeps_the_newest_and_only_when_asked(self):
        src = make_source(self.tmp)
        kept = [storage.archive("perf", src, runs_root=self.runs_root)
                for _ in range(3)]
        self.assertEqual(len(storage.runs("perf", self.runs_root)), 3,
                         "archiving never deletes by itself")
        removed = storage.prune("perf", 1, self.runs_root)
        self.assertEqual(removed, [kept[1], kept[0]])
        self.assertEqual(storage.runs("perf", self.runs_root), [kept[2]])
        self.assertFalse(kept[0].exists())
        with self.assertRaises(ValueError):
            storage.prune("perf", -1, self.runs_root)

    def test_unknown_area_is_empty_not_an_error(self):
        self.assertEqual(storage.runs("nope", self.runs_root), [])
        self.assertIsNone(storage.latest_run("nope", self.runs_root))
        self.assertEqual(storage.prune("nope", 5, self.runs_root), [])

    # ------------------------------------------------------------ revision
    def test_git_revision_matches_the_repository(self):
        revision = storage.git_revision()
        try:
            out = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                                 cwd=str(storage.ROOT), capture_output=True,
                                 text=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            self.skipTest("git unavailable")
        if out.returncode != 0:
            self.assertIsNone(revision)
            return
        self.assertEqual(revision, out.stdout.strip())
        src = make_source(self.tmp)
        run_dir = storage.archive("visual", src, runs_root=self.runs_root)
        self.assertEqual(storage.load_manifest(run_dir)["git_revision"], revision)


class ImmutabilityHistoryLineageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nativax-storage-"))
        self.addCleanup(lambda: (storage._thaw(self.tmp), shutil.rmtree(self.tmp, True)))
        self.root = self.tmp / ".runs"
        self.src = make_source(self.tmp)

    def archive(self, argv=("dart", "run", "x.dart", "--suite", "a", "--out", "o1")):
        return storage.archive("visual", self.src, engine="visual_check.dart", argv=list(argv),
                               runs_root=self.root)

    def test_evidence_is_read_only_and_hashed(self):
        run = self.archive()
        self.assertEqual(storage.verify(run), [])
        evidence = run / "evidence" / "results.json"
        with self.assertRaises(PermissionError):
            evidence.write_text("tampered")
        manifest = storage.load_manifest(run)
        self.assertEqual(manifest["schema_version"], "1.1")
        self.assertEqual(manifest["integrity"]["files"], 2)

    def test_tampering_and_missing_files_are_reported(self):
        run = self.archive()
        target = run / "evidence" / "results.json"
        os.chmod(target, 0o644)
        target.write_text('{"rows": [1]}')
        os.chmod(run / "evidence" / "pages", 0o755)
        (run / "evidence" / "pages" / "index.png").unlink()
        problems = storage.verify(run)
        self.assertIn("changed after archiving: evidence/results.json", problems)
        self.assertIn("missing: evidence/pages/index.png", problems)

    def test_history_is_append_only_and_validated(self):
        run = self.archive()
        first = storage.append_history(run, "annotation", {"text": "checked by hand"}, author="tester")
        second = storage.append_history(run, "review", {"decision": "confirmed"}, author="tester")
        self.assertNotEqual(first, second)
        with self.assertRaises(PermissionError):
            first.write_text("{}")
        kinds = [h["kind"] for h in storage.history(run)]
        self.assertEqual(kinds, ["annotation", "review"])
        with self.assertRaises(ValueError):
            storage.append_history(run, "rewrite", {}, author="tester")
        (run / "history" / "zzz-broken.json").write_text("{")
        self.assertIn("error", storage.history(run)[-1])

    def test_lineage_links_only_same_configuration(self):
        a = self.archive()
        other = self.archive(argv=("dart", "run", "x.dart", "--suite", "b", "--out", "o2"))
        b = self.archive(argv=("dart", "run", "x.dart", "--suite", "a", "--out", "elsewhere"))
        ma, mo, mb = (storage.load_manifest(r) for r in (a, other, b))
        self.assertEqual(ma["lineage_key"], mb["lineage_key"])     # output path ignored
        self.assertNotEqual(ma["lineage_key"], mo["lineage_key"])  # different suite
        self.assertIsNone(ma["previous_run"])
        self.assertIsNone(mo["previous_run"])
        self.assertEqual(mb["previous_run"], a.name)
        nexts = [h for h in storage.history(a) if h["kind"] == "superseded_by"]
        self.assertEqual([h["data"]["next_run"] for h in nexts], [b.name])
        self.assertEqual(storage.history(other), [])

    def test_legacy_manifest_is_readable_but_unverifiable(self):
        run = self.root / "visual" / "20260101T000000Z-abcdef1"
        run.mkdir(parents=True)
        (run / "manifest.json").write_text(json.dumps({
            "schema_version": "1.0", "run_id": run.name, "area": "visual", "engine": None,
            "status": "completed", "archived_at": "2026-01-01T00:00:00Z"}))
        self.assertIsNotNone(storage.load_manifest(run))
        self.assertEqual(storage.verify(run),
                         ["schema 1.0 run: no integrity hashes recorded, evidence cannot be verified"])

    def test_prune_removes_frozen_runs(self):
        self.archive()
        self.archive()
        removed = storage.prune("visual", 1, runs_root=self.root)
        self.assertEqual(len(removed), 1)
        self.assertFalse(removed[0].exists())


if __name__ == "__main__":
    unittest.main()

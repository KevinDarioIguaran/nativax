"""Tests for the dashboard's run archiving and report wiring (no Tk needed)."""
import inspect
import json
import shutil
import sys
import tempfile
import types
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import perf_gui
import storage

ROOT = perf_gui.ROOT


class FakeDashboard:
    """Provides the attributes _archive_pending reads, without Tk."""

    def __init__(self, areas, exit_code=0, stopped=False, fail_writer=False):
        self.pending_areas = list(areas) if areas else None
        self._exit_code = exit_code
        self._stopped_by_user = stopped
        self._last_command = ["dart", "run",
                              "debug/engines/performance/bin/perf.dart", "run"]
        self.logs = []
        self.fail_writer = fail_writer

    def _append_log(self, text):
        self.logs.append(text)

    def _write_visual_report(self):
        if self.fail_writer:
            raise RuntimeError("no data")
        perf_gui.AREA_REPORTS["visual"].write_text("# visual\n")

    def _write_perf_report(self):
        perf_gui.AREA_REPORTS["perf"].write_text("# perf\n")

    def _write_games_report(self):
        perf_gui.AREA_REPORTS["games"].write_text("# games\n")


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nativax-gui-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.runs_root = self.tmp / ".runs"
        self._original_archives = perf_gui.AREA_ARCHIVES
        self._original_reports = perf_gui.AREA_REPORTS
        self._original_runs_root = storage.RUNS_ROOT
        self._original_storage = perf_gui.storage_engine

        def area_dir(name):
            src = self.tmp / f"{name}-latest"
            (src / "pages").mkdir(parents=True)
            (src / "results.json").write_text('{"rows": []}\n')
            return src

        perf_gui.AREA_ARCHIVES = {
            "visual": (area_dir("visual"), "_write_visual_report"),
            "perf": (area_dir("perf"), "_write_perf_report"),
            "games": (area_dir("games"), "_write_games_report"),
        }
        perf_gui.AREA_REPORTS = {
            "visual": self.tmp / "report-visual.md",
            "perf": self.tmp / "report-perf.md",
            "games": self.tmp / "report-games.md",
        }
        storage.RUNS_ROOT = self.runs_root
        perf_gui.storage_engine = storage
        self.addCleanup(self._restore)

    def _restore(self):
        perf_gui.AREA_ARCHIVES = self._original_archives
        perf_gui.AREA_REPORTS = self._original_reports
        storage.RUNS_ROOT = self._original_runs_root
        perf_gui.storage_engine = self._original_storage

    def test_finished_run_is_archived_with_manifest_evidence_and_report(self):
        fake = FakeDashboard(["visual"])
        perf_gui.Dashboard._archive_pending(fake)
        runs = storage.runs("visual", self.runs_root)
        self.assertEqual(len(runs), 1)
        run_dir = runs[0]
        manifest = storage.load_manifest(run_dir)
        self.assertIsNotNone(manifest, manifest)
        self.assertEqual(manifest["status"], "completed")
        self.assertEqual(manifest["engine"], "perf.dart")
        self.assertEqual(manifest["area"], "visual")
        self.assertEqual(manifest["argv"][0], "dart")
        self.assertTrue((run_dir / "evidence" / "results.json").exists())
        self.assertEqual((run_dir / "reports" / "report-visual.md").read_text(),
                         "# visual\n")
        # The live directory survives the archive.
        self.assertTrue(perf_gui.AREA_ARCHIVES["visual"][0].exists())
        self.assertTrue(any("[archivo] visual (completed)" in line
                            for line in fake.logs), fake.logs)

    def test_nonzero_exit_marks_failed_and_stop_marks_aborted(self):
        perf_gui.Dashboard._archive_pending(FakeDashboard(["perf"], exit_code=1))
        self.assertEqual(storage.load_manifest(
            storage.latest_run("perf", self.runs_root))["status"], "failed")

        perf_gui.Dashboard._archive_pending(
            FakeDashboard(["perf"], exit_code=-9, stopped=True))
        runs = storage.runs("perf", self.runs_root)
        self.assertEqual(len(runs), 2)
        self.assertEqual(storage.load_manifest(runs[0])["status"], "aborted")
        self.assertEqual(storage.load_manifest(runs[1])["status"], "failed")

    def test_each_area_gets_only_its_own_report(self):
        perf_gui.Dashboard._archive_pending(FakeDashboard(["visual", "perf"]))
        vrun = storage.latest_run("visual", self.runs_root)
        prun = storage.latest_run("perf", self.runs_root)
        self.assertEqual([p.name for p in (vrun / "reports").iterdir()],
                         ["report-visual.md"])
        self.assertEqual([p.name for p in (prun / "reports").iterdir()],
                         ["report-perf.md"])

    def test_broken_report_writer_still_archives_the_evidence(self):
        fake = FakeDashboard(["visual"], fail_writer=True)
        perf_gui.Dashboard._archive_pending(fake)
        runs = storage.runs("visual", self.runs_root)
        self.assertEqual(len(runs), 1)
        source = perf_gui.AREA_ARCHIVES["visual"][0]
        expected_files = sum(1 for p in source.rglob("*") if p.is_file())
        self.assertEqual(storage.load_manifest(runs[0])["evidence"]["files"],
                         expected_files)
        self.assertTrue(any("informe de visual" in line for line in fake.logs))

    def test_missing_source_is_reported_not_crashed(self):
        perf_gui.AREA_ARCHIVES["visual"] = (self.tmp / "absent",
                                            "_write_visual_report")
        fake = FakeDashboard(["visual"])
        perf_gui.Dashboard._archive_pending(fake)
        self.assertEqual(storage.runs("visual", self.runs_root), [])
        self.assertTrue(any("sin salida" in line for line in fake.logs))

    def test_noop_when_storage_is_unavailable_or_nothing_pending(self):
        perf_gui.storage_engine = None
        fake = FakeDashboard(["visual"])
        perf_gui.Dashboard._archive_pending(fake)
        self.assertEqual(storage.runs("visual", self.runs_root), [])

        perf_gui.storage_engine = storage
        fake = FakeDashboard(None)
        perf_gui.Dashboard._archive_pending(fake)
        self.assertEqual(storage.runs("visual", self.runs_root), [])

    def test_pending_areas_are_consumed_once(self):
        fake = FakeDashboard(["visual"])
        perf_gui.Dashboard._archive_pending(fake)
        self.assertIsNone(fake.pending_areas)
        perf_gui.Dashboard._archive_pending(fake)
        self.assertEqual(len(storage.runs("visual", self.runs_root)), 1)


class WiringTest(unittest.TestCase):
    def test_history_sources_point_at_the_real_results_tables(self):
        sources = perf_gui.history_sources()
        self.assertEqual(sources["visual"], ROOT / "debug" / "artifacts" / "visual" / "latest" / "results.json")
        self.assertEqual(sources["perf"], ROOT / "debug" / "artifacts" / "perf" / "latest" / "results.json")
        # Regression: the visual path used to repeat "latest", so the visual
        # history never recorded anything.
        for path in sources.values():
            self.assertEqual(len(path.relative_to(ROOT).parts), 5)

    def test_each_area_report_has_its_own_path(self):
        paths = [perf_gui.AREA_REPORTS[key]
                 for key in ("visual", "perf", "games")]
        self.assertEqual(len({str(p) for p in paths}), 3)

    def test_archive_areas_cover_the_run_buttons(self):
        self.assertEqual(sorted(perf_gui.AREA_ARCHIVES),
                         ["games", "games3d", "perf", "visual"])
        self.assertEqual(sorted(perf_gui.AREA_REPORTS),
                         ["games", "games3d", "perf", "visual"])
        for src, _writer in perf_gui.AREA_ARCHIVES.values():
            self.assertTrue(str(src).startswith(str(ROOT)))

    def test_start_accepts_areas_and_stop_flags_the_user(self):
        signature = inspect.signature(perf_gui.Dashboard._start)
        self.assertIn("areas", signature.parameters)
        self.assertIn("stop", dir(perf_gui.Dashboard))

    def test_reports_and_manifests_are_json_readable(self):
        schema = json.loads(
            (ROOT / "debug" / "logic" / "schemas" / "run-manifest.schema.json"
             ).read_text())
        self.assertEqual(schema["$id"],
                         "nativax/diagnostic-run-manifest@1.1")


class _Widget:
    def __init__(self):
        self.options = {}
        self.items = []

    def configure(self, **kw):
        self.options.update(kw)

    def cget(self, key):
        return self.options.get(key)

    def delete(self, *_):
        self.items = []

    def winfo_width(self):
        return 600

    def winfo_height(self):
        return 200

    def __getattr__(self, name):
        if name.startswith("create_"):
            return lambda *a, **k: self.items.append((name, k.get("text")))
        raise AttributeError(name)


class HistoryVerdictTest(unittest.TestCase):
    """The history page says improved / worse / same / not comparable from
    the recorded runs, comparing only runs that measured the same set."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nativax-history-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def runs(self, specs):
        out = []
        for i, (pages, overall, rows) in enumerate(specs):
            path = self.tmp / f"2026102{i}T1000{i:02d}.json"
            path.write_text(json.dumps({"rows": [{"page": p, "overall": v} for p, v in rows.items()]}))
            out.append({"file": str(path), "recorded_at": path.stem, "git_commit": f"c{i}",
                        "summary": {"pages": pages, "mean_overall": overall, "pass": 0, "fail": 0}})
        return out

    def verdict(self, runs):
        dash = types.SimpleNamespace(
            history_sections={"visual": {k: _Widget() for k in ("verdict", "detail", "trend", "changes")}},
            _short_date=perf_gui.Dashboard._short_date,
            HISTORY_VISUAL_POINTS=perf_gui.Dashboard.HISTORY_VISUAL_POINTS,
            HISTORY_PERF_RELATIVE=perf_gui.Dashboard.HISTORY_PERF_RELATIVE,
            _append_log=lambda _t: None)
        dash._draw_trend = lambda *a, **k: perf_gui.Dashboard._draw_trend(dash, *a, **k)
        dash._draw_changes = lambda *a, **k: perf_gui.Dashboard._draw_changes(dash, *a, **k)
        perf_gui.Dashboard._history_area(dash, "visual", runs, key="mean_overall", count_key="pages",
                                         higher_better=True, unit=" %", item_key="overall")
        sec = dash.history_sections["visual"]
        return sec["verdict"].cget("text"), sec["detail"].cget("text"), sec["changes"].items

    def test_improved_worse_same(self):
        better = self.runs([(2, 70.0, {"a": 60, "b": 80}), (2, 75.0, {"a": 70, "b": 80})])
        verdict, detail, changes = self.verdict(better)
        self.assertEqual(verdict, "MEJORÓ")
        self.assertIn("70.00 % → 75.00 %", detail)
        self.assertTrue(any(text == "+10.00 %" for _, text in changes))
        worse = self.runs([(2, 75.0, {"a": 70, "b": 80}), (2, 60.0, {"a": 40, "b": 80})])
        self.assertEqual(self.verdict(worse)[0], "EMPEORÓ")
        same = self.runs([(2, 75.0, {"a": 70, "b": 80}), (2, 75.3, {"a": 70.6, "b": 80})])
        self.assertEqual(self.verdict(same)[0], "IGUAL")

    def test_only_runs_of_the_same_set_are_compared(self):
        mixed = self.runs([(2, 70.0, {"a": 60, "b": 80}), (1, 99.0, {"a": 99}), (2, 75.0, {"a": 70, "b": 80})])
        verdict, detail, _ = self.verdict(mixed)
        self.assertEqual(verdict, "MEJORÓ")          # 70 -> 75, the 1-page run is skipped
        self.assertIn("1 corrida(s) de otro tamaño se omiten", detail)
        alone = self.runs([(2, 70.0, {"a": 60, "b": 80}), (1, 99.0, {"a": 99})])
        self.assertEqual(self.verdict(alone)[0], "SIN DATOS SUFICIENTES")


class PassFailHistoryTest(unittest.TestCase):
    """Conformance, memory and security boxes say in words what changed."""

    def dash(self):
        d = types.SimpleNamespace(
            history_sections={a: {k: _Widget() for k in ("verdict", "detail", "chart")}
                              for a in ("conformance", "memory", "security")},
            _short_date=perf_gui.Dashboard._short_date, _names=perf_gui.Dashboard._names,
            HISTORY_WORDS=perf_gui.Dashboard.HISTORY_WORDS)
        d._draw_trend = lambda *a, **k: perf_gui.Dashboard._draw_trend(d, *a, **k)
        d._draw_suites = lambda *a, **k: perf_gui.Dashboard._draw_suites(d, *a, **k)
        return d

    def test_conformance_box(self):
        d = self.dash()
        perf_gui.Dashboard._history_conformance(d, {"verdict": "regressed", "suites": [
            {"suite": "wpt-url", "verdict": "regressed", "before": 665, "after": 660, "total": 896,
             "delta": -5, "fixed": [], "broken": ["#1", "#2", "#3", "#4", "#5"]},
            {"suite": "test262", "verdict": "not_enough_data", "before": None, "after": 10, "total": 20,
             "delta": None, "fixed": [], "broken": []}]})
        sec = d.history_sections["conformance"]
        self.assertEqual(sec["verdict"].cget("text"), "EMPEORÓ")
        self.assertIn("665 → 660 de 896", sec["detail"].cget("text"))
        self.assertIn("5 dejan de pasar (#1, #2, #3 y 2 más)", sec["detail"].cget("text"))
        self.assertIn(("create_text", "73.7 % (-5)"), sec["chart"].items)

    def test_bench_box(self):
        d = self.dash()
        perf_gui.Dashboard._history_bench(d, "memory", {
            "verdict": "improved", "runs": 3, "cases": 18, "pass": 18, "run": "20261020T213058Z",
            "fixed": ["timers.cancel"], "broken": [], "fail": [], "skipped": 1,
            "trend": [("2026-10-20T21:30:25", 83.3), ("2026-10-20T21:30:58", 100.0)]})
        sec = d.history_sections["memory"]
        self.assertEqual(sec["verdict"].cget("text"), "MEJORÓ")
        self.assertIn("18 de 18 casos pasan", sec["detail"].cget("text"))
        self.assertIn("Ahora pasan: timers.cancel.", sec["detail"].cget("text"))
        self.assertIn(("create_text", "100.00 %"), sec["chart"].items)
        perf_gui.Dashboard._history_bench(d, "security", {"verdict": "not_enough_data", "runs": 0})
        self.assertEqual(d.history_sections["security"]["verdict"].cget("text"), "SIN DATOS SUFICIENTES")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""UI tests of the debug app (debug/app).

Fixture reports are written with the real storage layer into a temporary
folder, and the catalog is pointed at it, so the tests do not depend on the
local debug/artifacts contents.

    python3 debug/tests/ui/test_app.py
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
import tempfile
import time
import tkinter as tk
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "debug" / "logic"))

import catalog  # noqa: E402
import storage  # noqa: E402

HAS_DISPLAY = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
APP = ROOT / "debug" / "app"
PNG_1x1 = bytes.fromhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000"
                        "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082")


def snapshot(root: Path):
    return {str(p): (p.stat().st_size, p.stat().st_mtime_ns) for p in root.rglob("*") if p.is_file()}


def build_fixture(tmp: Path) -> dict:
    runs, bench = tmp / "runs", tmp / "benchmarks"

    def visual(score):
        src = tmp / f"vis-{score}"
        page = src / "pages" / "suite" / "page-a"
        page.mkdir(parents=True)
        for name in ("chrome", "nativax", "diff"):
            (page / f"{name}.png").write_bytes(PNG_1x1)
        (page / "elements.json").write_text(json.dumps({"columns": [], "rows": [
            {"path": "html:1>body:1>div:1", "tag": "div", "dx": 0, "dy": 2, "dw": 0, "dh": 0, "iou": 0.9,
             "position_match": False, "size_match": True}]}))
        (page / "pixels.json").write_text(json.dumps({"totals": {"pixels": 1, "mismatched": 0}}))
        (src / "results.json").write_text(json.dumps({"rows": [
            {"page": "suite/page-a", "suite": "suite", "verdict": "WARN", "overall": score}]}))
        return storage.archive("visual", src, engine="visual_check.dart",
                               argv=["visual_check.dart", "--suite", "suite"], runs_root=runs)

    v1, v2 = visual(80.0), visual(80.2)
    src = tmp / "perf"
    src.mkdir()
    (src / "results.json").write_text(json.dumps({"results": [
        {"scenario": "dom.rows", "kind": "dom", "verdict": "FAIL", "reasons": ["slow"],
         "nativax": {"status": "ok", "scenario_ms": 300, "render_ms": 20, "frame_ms": {"p95": 40}},
         "chromium": {"status": "ok", "scenario_ms": 70, "render_ms": 5}}]}))
    storage.archive("perf", src, engine="perf.dart", argv=["perf.dart", "run"], runs_root=runs)
    for area, prefix, results in (
            ("leaks", "leaks", [{"id": "control.release", "subsystem": "runtime", "status": "PASS",
                                 "samples": [{"batch": 0, "rssBytes": 10}, {"batch": 1, "rssBytes": 11}]}]),
            ("security", "security", [{"id": "bridge.escape", "category": "bridge", "severity": "high",
                                       "status": "FAIL", "expected": "blocked", "observed": "allowed"}]),
            ("microbench", "bench", [{"name": "js.loop", "category": "js", "medianMs": 1.5}])):
        src = tmp / f"src-{area}"
        src.mkdir()
        (src / f"{prefix}-2026.json").write_text(json.dumps({"metadata": {"profile": "quick"}, "results": results}))
        storage.archive(area, src, engine=f"{area}.dart", argv=[area], runs_root=bench)
    conf = tmp / "conformance"
    conf.mkdir()
    (conf / "wpt-url-2026-10-26T100000.jsonl").write_text(
        json.dumps({"suite": "wpt-url", "id": "#0", "status": "pass"}) + "\n" +
        json.dumps({"suite": "wpt-url", "id": "#1", "status": "fail"}) + "\n")
    (conf / "wpt-url-2026-10-26T100000.summary.json").write_text(json.dumps({
        "suite": "wpt-url", "startedAt": "2026-10-26T10:00:00-05:00", "counts": {"PASS": 1, "FAIL": 1},
        "passRate": 50.0, "resultsFile": "wpt-url-2026-10-26T100000.jsonl"}))
    audit = tmp / "audit" / "runs" / "r1"
    (audit / "issues").mkdir(parents=True)
    (audit / "summary.json").write_text(json.dumps({
        "run_id": "r1", "started_at": "2026-10-26T10:00:00-05:00", "metrics": {"executed": 1},
        "issues": [{"issue_id": "NX-0000ABCD", "severity": "high", "status": "failed"}]}))
    (audit / "results.jsonl").write_text(json.dumps({
        "scenario": {"scenario_id": "basic.x.1", "family": "basic", "category": "valid", "seed": 1,
                     "screen": {"type": "screen", "id": "screen_main"}},
        "comparison": {"status": "failed", "findings": []}, "timings": {"total_ms": 10}}) + "\n")
    (audit / "issues" / "NX-0000ABCD.json").write_text(json.dumps({
        "issue_id": "NX-0000ABCD", "severity": "high", "status": "failed", "novelty": "new",
        "fingerprint": "style|padding|ua", "classification": {"kind": "style", "subsystem": "css",
                                                              "component_types": ["button"]},
        "evidence": {"message": "computed padding differs"}, "location": {"json_path": "screen"},
        "reproduction": {"steps": ["load"], "reproducible": True}, "root_cause": {"status": "unconfirmed",
                                                                                 "hypotheses": []},
        "occurrences": {"count": 1, "scenarios": ["basic.x.1"]}}))
    return {"runs": runs, "bench": bench, "audit": tmp / "audit", "conformance": conf, "visual": (v1, v2)}


def point_catalog(fx):
    catalog.RUN_ROOTS = (fx["runs"], fx["bench"])
    catalog.AUDIT_ROOT = fx["audit"]
    catalog.CONFORMANCE_RESULTS = fx["conformance"]


class TokenRulesTest(unittest.TestCase):
    """Components and pages take colors and fonts only from debug/styles."""

    def test_no_literal_colors_or_fonts_in_ui_code(self):
        offenders = []
        for path in list((APP / "components").glob("*.py")) + list((APP / "pages").rglob("*.py")):
            text = path.read_text()
            for m in re.finditer(r"#[0-9a-fA-F]{6}\b|\"(Noto Sans|DejaVu Sans Mono)\"|font=\(\"", text):
                offenders.append(f"{path.relative_to(ROOT)}: {m.group(0)}")
        self.assertEqual(offenders, [])

    def test_every_status_maps_to_an_existing_token(self):
        from debug.styles.tokens import STATUS, THEMES
        for theme in THEMES.values():
            for status, token in STATUS.items():
                self.assertIn(token, theme.color, f"{status} -> {token} missing in {theme.name}")

    def test_ui_code_is_english(self):
        spanish = re.compile(r"\b(Ejecutar|Informe|Página|Rendimiento|Historial|mejoró|empeoró|sin datos)\b")
        hits = [str(p.relative_to(ROOT)) for p in APP.rglob("*.py") if spanish.search(p.read_text())]
        self.assertEqual(hits, [])


@unittest.skipUnless(HAS_DISPLAY, "needs a display for Tk")
class AppTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="nxdebug-ui-"))
        cls.fx = build_fixture(cls.tmp)
        os.environ["XDG_CONFIG_HOME"] = str(cls.tmp / "cfg")
        point_catalog(cls.fx)
        from debug.app import main, state
        state.PREFS = cls.tmp / "cfg" / "prefs.json"
        cls.main = main
        cls.root = tk.Tk()
        cls.root.withdraw()

    @classmethod
    def tearDownClass(cls):
        cls.root.destroy()
        storage._thaw(cls.tmp)
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_every_page_and_workspace_and_nothing_is_written(self):
        before = snapshot(self.tmp / "runs") | snapshot(self.tmp / "benchmarks") | snapshot(self.tmp / "audit")
        app = self.main.App(self.root)
        types = {r.type for r in app.state.refs}
        self.assertEqual(types, {"visual_comparison", "performance", "memory", "security", "microbenchmarks",
                                 "compatibility", "bug_detection"})
        for key, _ in self.main.NAV:
            app.show(key)
            self.root.update()
        for ref in app.state.refs:
            app.open_report(ref)
            self.root.update()
            tabs = [app.page("report").nb.tab(t, "text") for t in app.page("report").nb.tabs()]
            self.assertIn("Summary", tabs)
            self.assertIn("Raw evidence", tabs)
            self.assertIn("Files", tabs)
            for index in range(len(tabs)):
                app.page("report").nb.select(index)
                self.root.update()
        after = snapshot(self.tmp / "runs") | snapshot(self.tmp / "benchmarks") | snapshot(self.tmp / "audit")
        self.assertEqual(before, after, "the app wrote inside a report")

    def test_dedicated_workspace_tabs_per_type(self):
        app = self.main.App(self.root)
        expected = {"visual_comparison": "Page inspector", "performance": "Scenarios", "memory": "Leak cases",
                    "security": "Attack cases", "microbenchmarks": "Benchmarks", "compatibility": "Tests",
                    "bug_detection": "Issue detail"}
        for ref in app.state.refs:
            app.open_report(ref)
            self.root.update()
            tabs = [app.page("report").nb.tab(t, "text") for t in app.page("report").nb.tabs()]
            self.assertIn(expected[ref.type], tabs, ref.type)

    def test_compare_two_visual_runs_and_refuse_mixed_types(self):
        app = self.main.App(self.root)
        v1, v2 = self.fx["visual"]
        page = app.page("compare")
        page.pair = (str(v1), str(v2))
        app.show("compare")
        self.root.update()
        self.assertIn("UNCHANGED", page.banner.cget("text"))   # 80.0 -> 80.2 within 0.5 points
        perf = next(r for r in app.state.refs if r.type == "performance")
        page.pair = (str(v1), perf.path)
        page.refresh()
        self.assertIn("NOT COMPARABLE", page.banner.cget("text"))

    def test_explorer_filters_search_and_scale(self):
        app = self.main.App(self.root)
        explorer = app.page("explorer")
        explorer.set_filter(type="security")
        app.show("explorer")
        self.root.update()
        self.assertTrue(explorer.table.view_rows)
        self.assertTrue(all(r["type"] == "security" for r in explorer.table.view_rows))
        explorer.set_filter(type="(all)")
        explorer.refresh()
        explorer.set_query("wpt-url")
        self.assertEqual([r["type"] for r in explorer.table.view_rows], ["compatibility"])
        many = [catalog.ReportRef(type="visual_comparison", area="visual", id=f"R{i:05d}", path=f"/x/{i}",
                                  layout="run-manifest-1.1", health="ok") for i in range(5000)]
        app.state.refs = many
        explorer.set_query("")
        started = time.monotonic()
        explorer.refresh()
        self.root.update()
        self.assertLess(time.monotonic() - started, 5)
        self.assertEqual(len(explorer.table.all_rows), 5000)
        self.assertLessEqual(len(explorer.table.tree.get_children()), explorer.table.page_size)

    def test_empty_and_corrupt_states(self):
        empty = self.tmp / "empty"
        empty.mkdir(exist_ok=True)
        saved = (catalog.RUN_ROOTS, catalog.AUDIT_ROOT, catalog.CONFORMANCE_RESULTS)
        catalog.RUN_ROOTS, catalog.AUDIT_ROOT, catalog.CONFORMANCE_RESULTS = (empty,), empty, empty
        try:
            app = self.main.App(self.root)
            self.assertEqual(app.state.refs, [])
            for key, _ in self.main.NAV:
                app.show(key)
                self.root.update()
        finally:
            catalog.RUN_ROOTS, catalog.AUDIT_ROOT, catalog.CONFORMANCE_RESULTS = saved
        broken = self.fx["runs"] / "visual" / "20260101T000000Z-badbad1"
        broken.mkdir()
        (broken / "manifest.json").write_text("{ not json")
        try:
            refs = catalog.discover()
            ref = next(r for r in refs if r.id == broken.name)
            self.assertTrue(ref.errors)
            app = self.main.App(self.root)
            app.open_report(app.state.find(str(broken)))
            self.root.update()
        finally:
            shutil.rmtree(broken)


if __name__ == "__main__":
    unittest.main(verbosity=1)

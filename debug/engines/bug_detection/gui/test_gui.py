#!/usr/bin/env python3
"""Tests for the audit GUI (data layer, diff, widgets and every section).

Fixture reports are produced by the real engine (`Explorer`) with the
deterministic fake backends of `debug/engines/bug_detection/test_audit.py`, so the GUI is
tested against the engine's actual file formats.

  python3 debug/engines/bug_detection/gui/test_gui.py
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import time
import tkinter as tk
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import jsondiff  # noqa: E402
import store  # noqa: E402
from widgets import Table  # noqa: E402

import test_audit  # noqa: E402
from nxaudit.explore import Explorer  # noqa: E402

HAS_DISPLAY = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def make_home(tmp: Path) -> Path:
    """Three independent reports in nested folders, as the engine writes them."""
    home = tmp / "audit-home"
    for i, (sub, seed, backend) in enumerate((("runs", 3, test_audit.fake_faulty),
                                              ("runs", 4, test_audit.fake_backend),
                                              ("equipo/nightly/runs", 5, test_audit.fake_faulty))):
        h = home / sub.rsplit("/runs", 1)[0] if "/" in sub else home
        Explorer(budget=30, batch=15, seed=seed, log=test_audit.quiet, minimize_top=1,
                 runner_factory=test_audit.fake_runner(backend), home=h, publish=False,
                 run_id=f"run-{i}").run()
    return home


def snapshot(root: Path):
    return {str(p): (p.stat().st_size, p.stat().st_mtime_ns) for p in root.rglob("*") if p.is_file()}


class StoreTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.home = make_home(cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_discovery_in_nested_folders(self):
        units = store.discover(self.home)
        names = sorted(u.name for u in units)
        # three runs + two "latest" copies (one per engine home)
        self.assertEqual(names.count("run-0") + names.count("run-1") + names.count("run-2"), 3)
        self.assertIn("latest", names)
        self.assertTrue(any("equipo" in str(u) for u in units))
        latest = [store.unit_meta(u) for u in units if u.name == "latest"]
        self.assertTrue(all(m.alias_of for m in latest))

    def test_units_are_isolated(self):
        units = {u.name: store.Unit(u) for u in store.discover(self.home) if u.name.startswith("run-")}
        a, b = units["run-0"], units["run-1"]
        self.assertTrue(a.issue_rows())
        # clean engine: no defects; an assertion failing in both engines is an
        # oracle conflict, which the engine does not count as a defect
        self.assertEqual([r for r in b.issue_rows() if r["status"] == "failed"], [])
        self.assertEqual(b.meta.health, "ok")
        for r in a.rows():
            for iid in r["issues"]:
                self.assertTrue((a.path / "issues" / f"{iid}.json").exists())
        res = store.compare_units(a, b)
        self.assertEqual(res["a"], str(a.path))
        self.assertEqual(res["b"], str(b.path))
        self.assertEqual(res["issues_only_b"], [])
        self.assertTrue(res["issues_only_a"])
        self.assertIn("seed", {d["field"] for d in res["config_diff"]})
        self.assertFalse(res["comparable"])

    def test_metrics_match_artifacts(self):
        u = store.Unit(self.home / "runs" / "run-0")
        summary = json.loads((u.path / "summary.json").read_text())
        lines = (u.path / "results.jsonl").read_text().splitlines()
        self.assertEqual(len(u.rows()), len(lines))
        self.assertEqual(summary["metrics"]["executed"], len(u.rows()))
        self.assertEqual(sum(1 for r in u.rows() if r["status"] == "failed"), summary["metrics"]["failed"])
        defects = [r for r in u.issue_rows() if r["status"] == "failed"]
        self.assertEqual(len(defects), summary["metrics"]["unique_issues"])
        curve = u.discovery_curve()
        self.assertEqual(len(curve), len(lines))
        self.assertTrue(u.selection().value)        # new runs record the selection log

    def test_corrupt_and_incomplete_reports(self):
        bad = self.tmp / "bad"
        shutil.copytree(self.home / "runs" / "run-0", bad / "partial")
        with (bad / "partial" / "results.jsonl").open("a") as fh:
            fh.write('{"scenario": {"scenario_id": "cut-in-ha')   # interrupted write
        (bad / "partial" / "coverage.json").unlink()
        u = store.Unit(bad / "partial")
        self.assertEqual(u.raw_results().skipped_lines, 1)
        self.assertEqual(len(u.rows()), 30)
        self.assertFalse(u.coverage().ok)
        self.assertIn("no existe", u.coverage().error)
        (bad / "broken").mkdir()
        (bad / "broken" / "summary.json").write_text("{not json")
        m = store.unit_meta(bad / "broken")
        self.assertEqual(m.status, "corrupt")
        (bad / "running").mkdir()
        (bad / "running" / "state.json").write_text(json.dumps({"run_id": "x", "executed": 12, "budget": 40}))
        m = store.unit_meta(bad / "running")
        self.assertEqual((m.status, m.executed, m.health), ("incomplete", 12, "unknown"))
        self.assertEqual(store.Unit(bad / "running").rows(), [])
        (bad / "partial" / "issues" / "NX-DEADBEEF.json").write_text("[")
        rows = store.Unit(bad / "partial").issue_rows()
        self.assertTrue(any(r.get("error") for r in rows if r["issue_id"] == "NX-DEADBEEF"))

    def test_global_search_labels_origin(self):
        units = [store.Unit(p) for p in store.discover(self.home)]
        some = next(u for u in units if u.issue_rows())
        iid = some.issue_rows()[0]["issue_id"]
        hits = store.global_search(units, iid)
        self.assertTrue(hits)
        self.assertTrue(all(h["unit"] for h in hits))
        self.assertTrue(store.global_search(units, "screen_main"))   # inside the screen JSON

    def test_percentiles_keep_missing_as_none(self):
        self.assertEqual(store.percentiles([])["p50"], None)
        self.assertEqual(store.percentiles([None, None])["p95"], None)
        self.assertEqual(store.percentiles([1, 2, 3])["p50"], 2)


class DiffTest(unittest.TestCase):
    def test_structural_diff(self):
        a = {"screen": {"type": "screen", "id": "s", "children": [
            {"type": "text", "id": "a", "style": {"width": "10px"}}, {"type": "button", "id": "b"}]}}
        b = {"screen": {"id": "s", "type": "screen", "children": [
            {"type": "button", "id": "b", "text": "OK"}, {"type": "text", "id": "a", "style": {"width": 10}}]}}
        ops = {(c["path"], c["op"]) for c in jsondiff.diff(a, b)}
        self.assertIn(("$.screen.children[0]", "moved"), ops)
        self.assertIn(("$.screen.children[0].text", "added"), ops)
        self.assertIn(("$.screen.children[1].style.width", "type_changed"), ops)
        self.assertNotIn("$.screen.type", {p for p, _ in ops})   # key order is not a change
        self.assertEqual(jsondiff.diff(a, a), [])
        self.assertEqual(jsondiff.to_nx_path("$.screen.children[1].children[0].style.width"),
                         "screen.children[1].children[0]")


@unittest.skipUnless(HAS_DISPLAY, "needs a display for Tk")
class GuiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.home = make_home(cls.tmp)
        os.environ["XDG_CONFIG_HOME"] = str(cls.tmp / "cfg")
        import app
        cls.appmod = app
        app.PREFS = cls.tmp / "cfg" / "prefs.json"
        cls.root = tk.Tk()
        cls.root.withdraw()

    @classmethod
    def tearDownClass(cls):
        cls.root.destroy()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_every_section_and_navigation_is_read_only(self):
        before = snapshot(self.home)
        a = self.appmod.App(self.root, self.home)
        for key, _ in self.appmod.SECTIONS:      # without a report open
            a.show(key)
            self.root.update()
        run0 = self.home / "runs" / "run-0"
        a.open_unit(run0)
        for key, _ in self.appmod.SECTIONS:      # with a report open
            a.show(key)
            self.root.update()
        issue = next(r["issue_id"] for r in a.unit.issue_rows()
                     if (a.unit.issues()[r["issue_id"]].value["location"] or {}).get("json_path")
                     and r["kind"] != "crash")
        a.open_issue(issue)
        self.root.update()
        for i in range(len(a.issue_nb.tabs())):
            a.issue_nb.select(i)
            self.root.update()
        rep = a.unit.issues()[issue].value
        path = rep["location"]["json_path"]
        a.open_scenario(rep["scenario_id"], path=path)
        self.root.update()
        self.assertEqual(a.comp_tree.selection(), (path,))
        self.assertIn("$." + path, a.ins_json.path_label.cget("text"))
        # JSON click -> tree selection
        a.comp_tree.selection_set("screen")
        self.root.update()
        start = a.ins_json.spans["$." + path][0]
        a.ins_json.text.mark_set("insert", f"1.0 + {start + 2} chars")
        a._json_clicked()
        self.root.update()
        self.assertEqual(a.comp_tree.selection(), (path,))
        # filters open filtered views
        a.open_runs(status="failed")
        self.root.update()
        self.assertTrue(all(r["status"] == "failed" for r in a.runs_table.view_rows))
        a.open_issues(severity="high")
        self.root.update()
        self.assertTrue(all(r.get("severity") == "high" for r in a.iss_table.view_rows))
        # explicit comparison keeps both origins
        a.compare_pair = [str(run0), str(self.home / "runs" / "run-1")]
        a.show("compare")
        self.root.update()
        self.assertIn("run-0", a.cmp_banner.cget("text"))
        self.assertIn("run-1", a.cmp_banner.cget("text"))
        # folders: nested report is reachable, folder up stays inside the root
        a.folder = self.home / "equipo"
        a.show("reports")
        self.root.update()
        self.assertTrue(any("run-2" == r["name"] for r in a.reports_table.all_rows))
        a.folder_up()
        a.folder_up()
        self.assertEqual(a.folder, self.home)
        self.assertEqual(before, snapshot(self.home), "the GUI wrote inside a report folder")

    def test_missing_style_is_not_defaulted(self):
        a = self.appmod.App(self.root, self.home)
        a.open_unit(self.home / "runs" / "run-0")
        row = next(r for r in a.unit.rows())
        a.open_scenario(row["scenario_id"], path="screen")
        self.root.update()
        texts = [w.cget("text") for w in a.props_frame.winfo_children() if isinstance(w, tk.Label)]
        scen = a.unit.scenario(row["scenario_id"])["scenario"]
        if "style" not in scen["screen"]:
            self.assertTrue(any("ausente" in t for t in texts), texts)

    def test_table_searches_all_rows_and_paginates(self):
        t = Table(self.root, [("id", "id", 100, "w"), ("v", "v", 100, "e")], page_size=200)
        rows = [{"id": f"row-{i}", "v": i if i % 7 else None} for i in range(20000)]
        started = time.monotonic()
        t.set_rows(rows)
        self.assertEqual(len(t.tree.get_children()), 200)
        t._set_query("row-19999")
        self.assertEqual([r["id"] for r in t.view_rows], ["row-19999"])
        t._set_query("")
        t.sort_by("v")
        t.sort_by("v")   # descending: missing values stay last
        self.assertIsNone(t.view_rows[-1]["v"])
        self.assertEqual(t.view_rows[0]["v"], 19998)
        self.assertLess(time.monotonic() - started, 5)
        t.destroy()


if __name__ == "__main__":
    unittest.main(verbosity=1)

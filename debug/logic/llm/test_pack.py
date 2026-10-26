#!/usr/bin/env python3
"""Tests for the LLM debug pack (debug/logic/llm).

    python3 debug/logic/llm/test_pack.py
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from llm import areas, pack, patterns, sources  # noqa: E402
from llm.core import ROOT, tokens  # noqa: E402

FIXTURE = ROOT / "debug" / "engines" / "visual_comparison" / "fixtures" / "50projects50days" / "progress-steps"


def write(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))


def visual_run(tmp: Path, pages: int = 3) -> Path:
    rows = []
    for i in range(pages):
        page = f"suite/page-{i}"
        pdir = tmp / "vis" / "pages" / page
        write(pdir / "report.json", {"entry": str(FIXTURE / "index.html").replace(
            "/debug/engines/visual_comparison/", "/tools/visual/"),          # pre-move path, must be remapped
            "scores": {"overall": 80.0 + i}, "viewport": {"width": 800, "height": 900}, "reason": "below"})
        write(pdir / "elements.json", {"rows": [
            {"path": "html:1>body:1>div:1>div:1", "tag": "div", "chrome_x": 0, "chrome_y": 0, "chrome_w": 10,
             "chrome_h": 10, "nativa_x": 0, "nativa_y": 2, "nativa_w": 10, "nativa_h": 10, "dx": 0, "dy": 2,
             "dw": 0, "dh": 0, "position_delta": 2, "size_delta": 0, "iou": 0.8, "position_match": False,
             "size_match": True, "root_cause": True,
             "style_mismatches": [{"property": "border-top-left-radius", "chrome": "0px", "nativa": "2px"},
                                  {"property": "border-top-right-radius", "chrome": "0px", "nativa": "2px"}]}]})
        rows.append({"page": page, "suite": "suite", "verdict": "FAIL", "overall": 80.0 + i, "position": 70.0,
                     "layout": 90.0, "color": 95.0, "design": 99.0})
    rows.append({"page": "suite/ok", "suite": "suite", "verdict": "PASS", "overall": 100.0})
    write(tmp / "vis" / "results.json", {"rows": rows})
    return tmp / "vis" / "results.json"


def perf_run(tmp: Path) -> Path:
    def row(sid, kind, n_s, n_r, c_s, c_r, verdict="FAIL", load=50):
        ratio = (n_s + n_r) / (c_s + c_r) if (c_s + c_r) else None
        return {"scenario": sid, "kind": kind, "verdict": verdict, "reasons": [f"{sid} slow"],
                "nativax": {"status": "ok", "scenario_ms": n_s, "eval_ms": n_s, "load_ms": load, "render_ms": n_r},
                "chromium": {"status": "ok", "scenario_ms": c_s, "eval_ms": c_s, "load_ms": load, "render_ms": c_r},
                "comparison": {"work_ratio": 0.0 if n_s + n_r == 0 else ratio}}
    results = [row(f"dom.s{i}", "dom", 900, 50, 50, 10) for i in range(3)]
    results.append(row("dom.unmeasured", "dom", 0, 0, 50, 10, load=1200))
    results.append(row("idle.blank", "idle", 0, 0, 0, 0, verdict="WARN"))
    write(tmp / "perf" / "results.json", {"targets": {"work_ratio": 3.0}, "results": results})
    return tmp / "perf" / "results.json"


def audit_run(tmp: Path) -> Path:
    run = tmp / "audit"
    write(run / "summary.json", {"run_id": "r", "metrics": {"executed": 1, "unique_issues": 1}})
    write(run / "issues" / "NX-11112222.json", {
        "issue_id": "NX-11112222", "status": "failed", "severity": "medium",
        "classification": {"kind": "style", "subsystem": "css", "component_types": ["button"],
                           "property": "border-radius"},
        "expected": {"border-top-left-radius": "0px"}, "actual": {"border-top-left-radius": "2px"},
        "evidence": {"message": "computed border-radius differs"}, "occurrences": {"count": 9},
        "reproduction": {"command": "python3 debug/engines/bug_detection/audit.py replay x"}})
    return run


class PackTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="nx-llm-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.saved = (areas.BENCH, areas.ART)
        areas.BENCH = self.tmp / "bench"           # no memory/security runs in the fixture
        self.addCleanup(lambda: setattr(areas, "BENCH", self.saved[0]))
        self.out = self.tmp / "out"
        conf = self.tmp / "conf"
        conf.mkdir()
        (conf / "wpt-url-2026-10-26T100000.jsonl").write_text("\n".join(json.dumps(x) for x in [
            {"suite": "wpt-url", "id": "#1 \"a\"", "status": "fail", "reason": "pathname: expected a, got %20a"},
            {"suite": "wpt-url", "id": "#2 \"b\"", "status": "fail", "reason": "pathname: expected b, got %20b"},
            {"suite": "wpt-url", "id": "#3", "status": "pass"}]) + "\n")
        write(conf / "wpt-url-2026-10-26T100000.summary.json", {"suite": "wpt-url", "command": "run_url",
              "counts": {"PASS": 1, "FAIL": 2}, "passRate": 33.3,
              "resultsFile": "wpt-url-2026-10-26T100000.jsonl"})
        self.overrides = {"visual": str(visual_run(self.tmp)), "perf": str(perf_run(self.tmp)),
                          "audit": str(audit_run(self.tmp)), "conformance": str(conf)}

    def build(self, budget=2500):
        return pack.build(budget=budget, out=self.out, overrides=self.overrides)

    def index(self):
        return json.loads((self.out / "index.json").read_text())

    def item(self, iid):
        return json.loads((self.out / "items" / f"{iid}.json").read_text())

    def test_files_are_minified_and_within_budget(self):
        result = self.build(budget=1200)
        for path in [self.out / "index.json", self.out / "legend.json", *(self.out / "items").glob("*.json")]:
            text = path.read_text()
            self.assertNotIn("\n", text, path.name)
            self.assertNotIn('": ', text, path.name)
            self.assertNotIn('", "', text, path.name)
        self.assertLessEqual(result["index_tokens"], 1200)
        self.assertLessEqual(result["item_tokens_max"], pack.ITEM_MAX)

    def test_deterministic_apart_from_timestamp(self):
        self.build()
        first = self.index()
        files1 = {p.name: p.read_text() for p in (self.out / "items").glob("*.json")}
        self.build()
        second = self.index()
        files2 = {p.name: p.read_text() for p in (self.out / "items").glob("*.json")}
        first.pop("gen"), second.pop("gen")
        first.pop("changes"), second.pop("changes")
        self.assertEqual(first, second)
        self.assertEqual(files1, files2)
        self.assertEqual(self.index()["changes"], {"new": 0, "resolved": 0, "new_ids": [], "resolved_ids": []})

    def test_visual_detail_resolves_fixture_source_and_css(self):
        self.build()
        doc = self.item("VIS-page-0")
        self.assertTrue(doc["fx"].startswith("debug/engines/visual_comparison/fixtures/"))
        root = doc["root"][0]
        self.assertEqual(root[0], "div.progress-container")
        self.assertEqual(root[2], 11)                         # line in the fixture html
        self.assertTrue(any(rule[1] == ".progress-container" for rule in root[8]))
        self.assertEqual(root[7][0], ["border-top-left-radius", "0px", "2px"])
        self.assertNotIn("VIS-ok", {r[0] for r in self.index()["items"]})   # PASS pages are not problems

    def test_pattern_groups_longhands_across_pages_and_links_audit(self):
        self.build()
        rows = {r[0]: r for r in self.index()["items"]}
        pat = self.item("PAT-VIS-border-radius-0px-2px")
        self.assertEqual(len(pat["pages"]), 3)
        self.assertEqual(sorted(pat["props"]), ["border-top-left-radius", "border-top-right-radius"])
        self.assertEqual(pat["also"], ["NX-11112222"])
        self.assertEqual(rows["PAT-VIS-border-radius-0px-2px"][1], 1)       # confirmed by two engines
        self.assertEqual(self.index()["items"][0][2], "pattern")             # patterns are listed first
        self.assertEqual(self.item("VIS-page-1")["pat"], ["PAT-VIS-border-radius-0px-2px"])

    def test_perf_work_excludes_load_and_flags_unmeasured(self):
        self.build()
        s0 = self.item("PERF-dom.s0")
        self.assertEqual(s0["dom"][0], "script")
        self.assertAlmostEqual(s0["dom"][1], 900 / 950, places=3)
        bad = self.item("PERF-dom.unmeasured")
        self.assertIn("warn", bad)
        self.assertEqual(bad["p"], 1)
        self.assertNotIn("w", (bad.get("x") or {}))
        idle = self.item("PERF-idle.blank")
        self.assertNotIn("warn", idle)

    def test_conformance_groups_failures_by_normalized_reason(self):
        self.build()
        doc = self.item("COMP-wpt-url")
        self.assertEqual(len(doc["g"]), 1)
        self.assertEqual(doc["g"][0][2], 2)
        self.assertIn("‹", doc["g"][0][1])

    def test_every_source_path_exists(self):
        self.build()
        for path in (self.out / "items").glob("*.json"):
            for src in json.loads(path.read_text()).get("src") or []:
                p = Path(src) if Path(src).is_absolute() else ROOT / src
                self.assertTrue(p.exists(), f"{path.name}: {src}")

    def test_changes_report_new_and_resolved(self):
        self.build()
        self.overrides["perf"] = str(perf_run(self.tmp))
        data = json.loads(Path(self.overrides["perf"]).read_text())
        data["results"] = [r for r in data["results"] if r["scenario"] != "dom.s2"]
        Path(self.overrides["perf"]).write_text(json.dumps(data))
        self.build()
        ch = self.index()["changes"]
        self.assertIn("PERF-dom.s2", ch["resolved_ids"])


class PartialBuildTest(PackTest):
    def test_partial_build_keeps_other_areas(self):
        self.build()
        before = {p.name for p in (self.out / "items").glob("*.json")}
        pack.build(["conformance"], out=self.out, overrides=self.overrides)
        after = {p.name for p in (self.out / "items").glob("*.json")}
        self.assertEqual(before, after)
        self.assertIn("visual", self.index()["areas"])


class SourcesTest(unittest.TestCase):
    def test_nth_of_type_and_id_paths(self):
        html = str(FIXTURE / "index.html")
        self.assertEqual(sources.selector_label(sources.element(html, "html:1>body:1>div:1>div:1>div:2")),
                         "div.circle.active")
        self.assertEqual(sources.selector_label(sources.element(html, "#prev")), "button#prev.btn")
        self.assertIsNone(sources.element(html, "html:1>body:1>div:9"))


if __name__ == "__main__":
    unittest.main(verbosity=1)

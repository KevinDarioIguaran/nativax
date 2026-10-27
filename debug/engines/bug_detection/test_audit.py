#!/usr/bin/env python3
"""Tests of the audit engine itself. No Chromium and no Flutter: engines are
replaced by a deterministic fake that "renders" a scenario into a probe, and
deliberate faults are injected into its observations.

  python3 debug/engines/bug_detection/test_audit.py
"""
from __future__ import annotations

import copy
import json
import os
import re
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from nxaudit import execute, faults  # noqa: E402
from nxaudit import generate as gen  # noqa: E402
from nxaudit.compare import compare, normalize, same  # noqa: E402
from nxaudit.compile import compile_screen, find, walk  # noqa: E402
from nxaudit.diagnose import cluster, diagnose  # noqa: E402
from nxaudit.explore import ROOT, Explorer, Runner  # noqa: E402
from nxaudit.minimize import minimize  # noqa: E402
from nxaudit.report import build_issue_report, llm_brief, write_json  # noqa: E402
from nxaudit.schema import check_report, check_scenario, validate  # noqa: E402

SYSTEM = {"git_commit": "test", "git_dirty": False, "generator_version": gen.GENERATOR_VERSION,
          "engine": "fake"}


def fake_render(scenario: dict) -> dict:
    """Deterministic stand-in for an engine: one 20 px row per node, events
    and values derived from the actions. Identical input -> identical output."""
    def probe(state_values, events, focused):
        elements = []
        for i, (path, node) in enumerate(walk(scenario["screen"])):
            depth = path.count(".children[")
            el = {"id": node["id"], "nx": path, "type": node["type"], "tag": "div",
                  "rect": [depth * 4.0, i * 20.0, 200.0 - depth * 8, 20.0],
                  "client": [100, 20], "scroll": [100, 20],
                  "styles": {"color": "rgb(0, 0, 0)", "padding-left": "0px",
                             **{k: v for k, v in (node.get("style") or {}).items() if k == "color"}},
                  "text": node.get("text", "")}
            el.update(state_values.get(node["id"], {}))
            if node["type"] == "input":
                el.setdefault("value", "")
            if node["type"] == "checkbox":
                el.setdefault("checked", False)
            elements.append(el)
        return {"viewport": [360, 640], "document": [360, 640], "focused": focused,
                "events": list(events), "errors": [], "elements": elements}

    values, events, focused = {}, [], None
    states = [{"after": "initial", "probe": probe(values, events, focused)}]
    results = []
    for i, a in enumerate(scenario.get("actions") or []):
        if a["op"] in ("click", "type"):
            events.append(f"click:{a['target']}")
            focused = a["target"]
            if a["op"] == "type":
                values.setdefault(a["target"], {})["value"] = a.get("text", "")
                events.append(f"input:{a['target']}")
        states.append({"after": f"action:{i}:{a['op']}", "probe": probe(values, events, focused)})
        results.append({"index": i, "op": a["op"], "ok": True, "note": None})
    return {"status": "ok", "engine": "fake", "states": states, "action_results": results,
            "timings": {"total_ms": 10}, "rss_kb": {"before": 1000, "after": 1000},
            "flutter_errors": [], "script_errors": []}


def fake_backend(scenarios, work, log=print):
    return {s["scenario_id"]: fake_render(s) for s in scenarios}


def fake_faulty(scenarios, work, log=print):
    return {s["scenario_id"]: faults.inject(s, fake_render(s), faults.choose(s)) for s in scenarios}


def fake_runner(nativa=fake_backend):
    return lambda work, lg: Runner(work, lg, nativa_fn=nativa, chrome_fn=fake_backend)


def quiet(*_a, **_k):
    pass


def basic_of_type(kind, limit=10):
    out = []
    for i in range(gen.basic_size()):
        s = gen.basic(i)
        if s["screen"]["children"][0]["children"][0]["type"] == kind:
            out.append(s)
            if len(out) >= limit:
                break
    return out


def button_scenario():
    return basic_of_type("button", 1)[0]


class SchemaTest(unittest.TestCase):
    def test_generated_valid_scenarios_pass_schema(self):
        for family, fn in gen.FAMILIES.items():
            if family == "schema_invalid":
                continue
            for i in range(25):
                s = fn(i)
                self.assertEqual(check_scenario(s), [], f"{family}[{i}] {s['scenario_id']}")

    def test_every_deliberate_negative_is_rejected(self):
        for i in range(len(gen.SCHEMA_BREAKS) * 2):
            s = gen.schema_invalid(i)
            self.assertEqual(s["category"], "schema_invalid")
            self.assertTrue(check_scenario(s), f"{gen.SCHEMA_BREAKS[i % len(gen.SCHEMA_BREAKS)]} accepted")

    def test_invalid_content_is_valid_json_not_a_negative(self):
        s = gen.invalid_content(3)
        self.assertEqual(s["category"], "invalid_content")
        self.assertEqual(check_scenario(s), [])
        self.assertIn(";", s["environment"]["extra_css"])

    def test_validator_keywords(self):
        schema = {"type": "object", "required": ["a"], "additionalProperties": False,
                  "properties": {"a": {"type": "integer", "minimum": 1}, "b": {"enum": ["x"]}}}
        self.assertEqual(validate({"a": 2}, schema), [])
        self.assertTrue(validate({"a": 0}, schema))
        self.assertTrue(validate({"a": True}, schema))  # bool is not an integer
        self.assertTrue(validate({"a": 1, "c": 1}, schema))
        self.assertTrue(validate({"b": "x"}, schema))

    def test_schema_enums_match_catalog(self):
        from nxaudit.catalog import ACTIONS, COMPONENTS
        schema = json.loads((Path(__file__).parent / "schemas" / "scenario.schema.json").read_text())
        self.assertEqual(sorted(schema["$defs"]["node"]["properties"]["type"]["enum"]), sorted(COMPONENTS))
        action_ops = schema["properties"]["actions"]["items"]["properties"]["op"]["enum"]
        self.assertEqual(sorted(action_ops), sorted(ACTIONS))


class DeterminismTest(unittest.TestCase):
    def test_seeds_reproduce_byte_for_byte(self):
        for family in ("basic", "combinatorial", "random", "adversarial", "invalid", "interaction"):
            a = json.dumps(gen.regenerate(family, 42), sort_keys=True)
            b = json.dumps(gen.regenerate(family, 42), sort_keys=True)
            self.assertEqual(a, b, family)
        parent = gen.interaction(1)
        self.assertEqual(gen.mutate(parent, 9), gen.mutate(parent, 9))

    def test_ids_are_stable_and_unique(self):
        ids = [gen.random_screen(i)["scenario_id"] for i in range(200)]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(gen.random_screen(5)["scenario_id"], gen.random_screen(5)["scenario_id"])

    def test_pairwise_covers_every_pair(self):
        rows = gen.pairwise_rows(gen.PAIRWISE_FACTORS)
        names = list(gen.PAIRWISE_FACTORS)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                needed = {(x, y) for x in gen.PAIRWISE_FACTORS[a] for y in gen.PAIRWISE_FACTORS[b]}
                seen = {(r[a], r[b]) for r in rows}
                self.assertEqual(needed - seen, set(), f"{a} x {b}")
        exhaustive = 1
        for v in gen.PAIRWISE_FACTORS.values():
            exhaustive *= len(v)
        self.assertLess(len(rows), exhaustive / 1000)


class CompileTest(unittest.TestCase):
    def test_structural_paths_point_to_the_element(self):
        s = gen.random_screen(11)
        html = compile_screen(s)
        for path, node in walk(s["screen"]):
            m = re.search(rf'id="{re.escape(node["id"])}" data-nx="([^"]+)"', html)
            self.assertIsNotNone(m, node["id"])
            self.assertEqual(m.group(1), path)
            self.assertIs(find(s["screen"], path), node)

    def test_text_is_escaped(self):
        s = gen.adversarial(3)  # unicode/special text
        html = compile_screen(s)
        self.assertNotIn("<b>no html</b>", html)


class OracleTest(unittest.TestCase):
    def test_identical_engines_pass(self):
        for s in [gen.interaction(i) for i in range(10)] + [gen.random_screen(i) for i in range(10)]:
            r = compare(s, fake_render(s), fake_render(s), ROOT)
            self.assertEqual(r["status"], "passed", (s["scenario_id"], r["findings"][:2]))

    def test_known_defects_are_detected_and_localized(self):
        scenarios = [f(i) for f in (gen.basic, gen.interaction, gen.random_screen, gen.adversarial)
                     for i in range(60)]
        results = []
        for s in scenarios:
            fid = faults.choose(s)
            results.append({"scenario": s, "comparison": compare(
                s, faults.inject(s, fake_render(s), fid), fake_render(s), ROOT)})
        score = faults.score(results)
        self.assertGreater(score["injected"], 40)
        self.assertEqual(score["detection_rate"], 1.0, score["faults"])
        self.assertEqual(score["localization_rate"], 1.0, score["faults"])
        self.assertEqual(score["clean_scenarios_with_findings"], 0)

    def test_first_divergence_marks_consequences(self):
        s = button_scenario()
        ref = fake_render(s)
        mine = copy.deepcopy(ref)
        # Shift the frame container: its child must be a consequence.
        for el in mine["states"][0]["probe"]["elements"]:
            if el["nx"] == "screen.children[0]":
                el["rect"][2] += 10
        r = compare(s, mine, ref, ROOT)
        primary = [f for f in r["findings"] if f["primary"]]
        self.assertEqual([f["json_path"] for f in primary], ["screen.children[0]"])

    def test_assertion_failing_in_both_engines_is_not_a_defect(self):
        s = gen.interaction(0)  # counter: expects "1" after a click
        bad = copy.deepcopy(s)
        bad["assertions"][0]["expected"] = "99"
        r = compare(bad, fake_render(bad), fake_render(bad), ROOT)
        self.assertEqual({f["kind"] for f in r["findings"]}, {"oracle_conflict"})
        self.assertNotEqual(r["status"], "failed")

    def test_crash_with_repo_frame_is_located(self):
        s = gen.basic(1)
        n = fake_render(s)
        n["flutter_errors"] = [{"library": "rendering library", "summary": "RenderBox was not laid out",
                                "context": "during performLayout()",
                                "stack": ["#0      CssFlex.layout (package:nativa_render/src/layout/css_flex.dart:42:7)"]}]
        r = compare(s, n, fake_render(s), ROOT)
        crash = next(f for f in r["findings"] if f["kind"] == "crash")
        self.assertTrue(crash["primary"])
        n["flutter_errors"].append({"library": "rendering library", "summary": "RenderBox was not laid out: X#12345",
                                    "context": None, "stack": []})
        r2 = compare(s, n, fake_render(s), ROOT)
        crashes = [f for f in r2["findings"] if f["kind"] == "crash"]
        self.assertEqual([f["primary"] for f in crashes], [True, False])
        self.assertEqual(crash["stage"], "layout")
        self.assertEqual(crash["stack_locations"][0]["file"], "packages/nativa_render/lib/src/layout/css_flex.dart")
        self.assertEqual(crash["stack_locations"][0]["line"], 42)

    def test_crash_fingerprint_ignores_instance_ids(self):
        from nxaudit.diagnose import fingerprint
        base = {"kind": "crash", "stage": "layout", "stack_locations": []}
        a = fingerprint({**base, "message": "FlutterError (rendering library): RenderBox was not laid out: "
                                            "_RenderColoredBox#424ce relayoutBoundary=up3 NEEDS-PAINT"})
        b = fingerprint({**base, "message": "FlutterError (rendering library): RenderBox was not laid out: "
                                            "_RenderColoredBox#9a1f2 relayoutBoundary=up47"})
        c = fingerprint({**base, "message": "FlutterError (rendering library): RenderBox was not laid out: "
                                            "RenderCssBox#9a1f2 relayoutBoundary=up47"})
        self.assertEqual(a, b)
        self.assertNotEqual(a, c)

    def test_normalization(self):
        self.assertTrue(same("color", "rgb(0, 0, 0)", "rgba(0, 0, 0, 1)"))
        self.assertTrue(same("background-color", "transparent", "rgba(0, 0, 0, 0)"))
        self.assertTrue(same("font-weight", "bold", "700"))
        self.assertTrue(same("padding-left", "8px", "8.3px"))
        self.assertFalse(same("padding-left", "8px", "9px"))
        self.assertEqual(normalize("font-family", "'Liberation Sans', serif"), "liberation sans,serif")


class ClusterReportTest(unittest.TestCase):
    def _results(self):
        out = []
        for s in basic_of_type("button", 12):
            out.append({"scenario": s, "comparison": compare(
                s, faults.inject(s, fake_render(s), "F1_button_width"), fake_render(s), ROOT)})
        return out

    def test_repeated_defect_is_one_issue(self):
        results = self._results()
        self.assertGreater(len(results), 3)
        issues = cluster(results)
        geometry = [i for i in issues.values() if i["kind"] == "geometry"]
        self.assertEqual(len(geometry), 1, [i["fingerprint"] for i in issues.values()])
        self.assertEqual(len(geometry[0]["occurrences"]), len(results))

    def test_report_is_schema_valid_and_honest(self):
        results = self._results()
        issues = cluster(results)
        scenarios = {r["scenario"]["scenario_id"]: r["scenario"] for r in results}
        for issue in issues.values():
            diag = diagnose(issue, scenarios, None)
            report = build_issue_report(issue, diag, run_id="t", scenarios=scenarios, system=SYSTEM,
                                        minimization=None, novelty="new", reproducible=None)
            self.assertEqual(check_report(report), [])
            # no stack frame -> no confirmed cause, no invented location
            self.assertEqual(report["root_cause"]["status"], "unconfirmed")
            self.assertIsNone(report["location"]["source_file"])
            self.assertIsNone(report["location"]["line"])
            self.assertFalse(report["verification"]["fix_applied"])
            for f in report["investigation"]["files_to_inspect"]:
                self.assertTrue((ROOT / f["file"]).exists(), f["file"])
            first = issue["occurrences"][0]["finding"]
            node = find(scenarios[issue["occurrences"][0]["scenario_id"]]["screen"],
                        report["location"]["json_path"])
            self.assertEqual(node["id"], first["element_id"])
            self.assertIn(issue["issue_id"], llm_brief(report))

    def test_broken_report_is_rejected(self):
        self.assertTrue(check_report({"report_version": "1.0"}))


class MinimizeTest(unittest.TestCase):
    def test_minimization_keeps_the_defect(self):
        s = gen.random_screen(3)
        # Defect model: present iff a node with id ending in _1 exists and the
        # screen carries at least one 'padding' declaration somewhere.
        target = next(n for _, n in walk(s["screen"]) if n is not s["screen"])
        target.setdefault("style", {})["padding"] = "8px"

        def has_defect(sc):
            ids = {n["id"] for _, n in walk(sc["screen"])}
            pads = any("padding" in (n.get("style") or {}) for _, n in walk(sc["screen"]))
            return target["id"] in ids and pads

        def evaluate(cands):
            return {c["scenario_id"]: ({"FP"} if has_defect(c) else set()) for c in cands}

        result = minimize(s, "FP", evaluate, {target["id"]}, max_rounds=60, log=quiet)
        self.assertTrue(result["reproduced"])
        self.assertTrue(has_defect(result["scenario"]))
        self.assertLess(result["final_size"], result["start_size"])
        self.assertTrue(result["one_minimal"])
        self.assertTrue(any(c["unit"] == "style" for c in result["necessary_conditions"]))
        self.assertEqual(check_scenario({**result["scenario"], "family": "minimized"}), [])

    def test_non_reproducing_case_is_reported_not_minimized(self):
        s = gen.basic(2)
        result = minimize(s, "FP", lambda c: {x["scenario_id"]: set() for x in c}, set(), log=quiet)
        self.assertFalse(result["reproduced"])
        self.assertEqual(result["removed"], [])


class ExecutionSafetyTest(unittest.TestCase):
    def test_timeout_kills_the_process_group(self):
        t = time.monotonic()
        code, _, _, timed_out = execute._run(["bash", "-c", "sleep 30 & sleep 30"], ROOT, None, 0.5)
        self.assertTrue(timed_out)
        self.assertLess(time.monotonic() - t, 5)

    def test_hanging_scenario_is_isolated_and_batch_resumes(self):
        scenarios = [gen.basic(i) for i in range(3)]
        calls = []

        def fake_run(cmd, cwd, env, timeout):
            manifest = json.loads(Path(env["NATIVAX_AUDIT_MANIFEST"]).read_text())
            ids = [j["id"] for j in manifest["scenarios"]]
            calls.append(ids)
            with open(manifest["out"], "a") as fh:
                for sid in ids:
                    fh.write(json.dumps({"kind": "begin", "id": sid}) + "\n")
                    if sid == scenarios[1]["scenario_id"]:
                        return -9, "", "", True  # hangs: killed by timeout
                    fh.write(json.dumps({"kind": "result", "id": sid, "status": "ok", "states": []}) + "\n")
            return 0, "", "", False

        original = execute._run
        execute._run = fake_run
        try:
            with tempfile.TemporaryDirectory() as tmp:
                out = execute.run_nativa(scenarios, Path(tmp), log=quiet)
        finally:
            execute._run = original
        self.assertEqual(out[scenarios[0]["scenario_id"]]["status"], "ok")
        self.assertEqual(out[scenarios[1]["scenario_id"]]["status"], "timeout")
        self.assertEqual(out[scenarios[2]["scenario_id"]]["status"], "ok")
        self.assertEqual(calls[1], [scenarios[2]["scenario_id"]])

    def test_atomic_write_keeps_previous_file_on_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.json"
            write_json(path, {"ok": 1})
            with self.assertRaises(TypeError):
                write_json(path, {"bad": object()})
            self.assertEqual(json.loads(path.read_text()), {"ok": 1})


class EndToEndTest(unittest.TestCase):
    def test_fault_choice_follows_content_not_id(self):
        # The explorer caches observations by content; two scenarios with
        # equal content must get the same injected fault whatever their id.
        scen = next(s for s in (gen.random_screen(i) for i in range(60)) if faults.applicable(s))
        twin = dict(scen, scenario_id="mutation.other." + scen["scenario_id"])
        self.assertEqual(faults.choose(scen), faults.choose(twin))

    def test_full_pipeline_offline_with_injected_faults(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            ex = Explorer(budget=60, batch=20, seed=3, log=quiet, minimize_top=2,
                          runner_factory=fake_runner(fake_faulty), home=home, publish=False)
            summary = ex.run()
            m = summary["metrics"]
            self.assertEqual(m["executed"], 60)
            self.assertGreater(m["rejected_expected"], 0)
            self.assertEqual(m["validator_escapes"], 0)
            self.assertEqual(m["rejected_unexpected"], 0)
            self.assertGreater(m["unique_issues"], 0)
            self.assertEqual(m["reproducible"], m["unique_issues"])
            self.assertGreater(m["duplicates_grouped"], 0)
            # every family got budget (exploration floor), none above the cap
            executed = {f: s["executed"] for f, s in summary["strategies"].items()}
            for fam in ("basic", "combinatorial", "random", "adversarial", "invalid", "interaction"):
                self.assertGreater(executed.get(fam, 0), 0, executed)
            for issue_file in (home / "latest" / "issues").glob("*.json"):
                self.assertEqual(check_report(json.loads(issue_file.read_text())), [], issue_file.name)
            self.assertTrue((home / "latest" / "summary.md").exists())
            self.assertTrue((home / "ledger.json").exists())
            # results.jsonl: one complete JSON object per executed scenario
            lines = (home / "latest" / "results.jsonl").read_text().splitlines()
            self.assertEqual(len(lines), 60)
            for line in lines:
                json.loads(line)
            # A "fixed" engine: same scenarios, no faults -> no defects, and a
            # previously fixed fingerprint reappearing is labelled regression.
            ledger = json.loads((home / "ledger.json").read_text())
            first = next(iter(ledger))
            ledger[first]["status"] = "fixed"
            (home / "ledger.json").write_text(json.dumps(ledger))
            ex2 = Explorer(budget=60, batch=20, seed=3, log=quiet, minimize_top=0, reproduce=False,
                           runner_factory=fake_runner(fake_faulty), home=home, publish=False,
                           run_id="again")
            s2 = ex2.run()
            self.assertIn(first, {i["issue_id"] for i in s2["issues"] if i["novelty"] == "regression"})
            ex3 = Explorer(budget=60, batch=20, seed=3, log=quiet, minimize_top=0, reproduce=False,
                           runner_factory=fake_runner(fake_backend), home=home, publish=False,
                           run_id="fixed")
            s3 = ex3.run()
            self.assertEqual(s3["metrics"]["failed"], 0)
            self.assertEqual(s3["metrics"]["unique_issues"], 0)

    def test_reanalyze_matches_original_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            ex = Explorer(budget=30, batch=15, seed=5, log=quiet, minimize_top=0, reproduce=False,
                          runner_factory=fake_runner(fake_faulty), home=home, publish=False, run_id="r1")
            s1 = ex.run()
            re = Explorer(budget=0, seed=0, log=quiet, minimize_top=0, reproduce=False,
                          runner_factory=fake_runner(fake_faulty), home=home, publish=False, run_id="r2")
            s2 = re.reanalyze(home / "runs" / "r1")
            self.assertEqual({i["issue_id"] for i in s1["issues"]}, {i["issue_id"] for i in s2["issues"]})


if __name__ == "__main__":
    os.chdir(ROOT)
    unittest.main(verbosity=1)

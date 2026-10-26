"""Tests for the evidence-based report recommendation engine."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import recommend


def row(kind, scenario, nativa, chromium, verdict="FAIL", p95=None):
    return {
        "scenario": scenario,
        "kind": kind,
        "verdict": verdict,
        "nativax": {
            "status": "ok",
            "scenario_ms": nativa,
            "render_ms": 0,
            "frame_ms": {"p95": p95} if p95 is not None else {},
        },
        "chromium": {
            "status": "ok",
            "scenario_ms": chromium,
            "render_ms": 0,
            "frame_ms": {"p95": 1},
        },
    }


BASE = {
    "visual": {"rows": []},
    "visual_catalog": [],
    "perf": {"results": []},
    "perf_catalog": [],
    "app_idle": {"status": "ok", "rss_tail_mb": 105, "cpu_tail_pct": 0},
    "leaks": None,
    "security": None,
}


class RecommendationsTest(unittest.TestCase):
    def test_memory_over_budget_is_p0(self):
        data = dict(BASE)
        data["app_idle"] = {"status": "ok", "rss_tail_mb": 320, "cpu_tail_pct": 0}
        recs = recommend.build_recommendations(data)
        self.assertTrue(any(r.priority == "P0" and r.area == "memory" for r in recs))

    def test_idle_without_load_peak_is_p2(self):
        recs = recommend.build_recommendations(BASE)
        self.assertTrue(any(r.area == "memory" and r.priority == "P2" for r in recs))

    def test_coverage_is_reported(self):
        data = dict(BASE)
        data["visual"] = {"rows": [{"page": "a", "overall": 90, "position": 90,
                                    "layout": 90, "color": 90, "design": 90}]}
        data["visual_catalog"] = [{"id": "a"}, {"id": "b"}]
        data["perf_catalog"] = [{"id": "x"}, {"id": "y"}]
        recs = recommend.build_recommendations(data)
        self.assertTrue(any("visual coverage" in r.area for r in recs))
        self.assertTrue(any("performance coverage" in r.area for r in recs))

    def test_dom_and_layout_cross_signal(self):
        data = dict(BASE)
        data["perf"] = {"results": [row("dom", "dom.rows-create-1k", 100, 10)]}
        data["perf_catalog"] = [{"id": "dom.rows-create-1k"}]
        data["visual"] = {"rows": [{"page": "p", "overall": 30, "position": 20,
                                    "layout": 30, "color": 70, "design": 90,
                                    "ink_mismatch_pct": 20}]}
        data["visual_catalog"] = [{"id": "p"}]
        recs = recommend.build_recommendations(data)
        self.assertTrue(any(r.area == "renderer" and r.priority == "P0" for r in recs))
        self.assertTrue(any(r.area == "DOM / layout" for r in recs))

    def test_scroll_p95_rule(self):
        data = dict(BASE)
        data["perf"] = {"results": [row("scroll", "scroll.rows-10k", 0, 1, p95=40)]}
        data["perf_catalog"] = [{"id": "scroll.rows-10k"}]
        recs = recommend.build_recommendations(data)
        self.assertTrue(any(r.area == "scroll / frames" for r in recs))

    def test_security_failure_is_p0(self):
        data = dict(BASE)
        data["security"] = {"results": [{"id": "xss.bad", "status": "FAIL"}]}
        recs = recommend.build_recommendations(data)
        self.assertTrue(any(r.priority == "P0" and r.area == "security" for r in recs))

    def test_leak_failure_is_p0(self):
        data = dict(BASE)
        data["leaks"] = {"results": [{"id": "dom.leak", "status": "FAIL"}]}
        recs = recommend.build_recommendations(data)
        self.assertTrue(any(r.priority == "P0" and r.area == "leaks" for r in recs))

    def test_detailed_sections_include_games_and_video(self):
        data = dict(BASE)
        data["game"] = {"results": [row("dom", "game.quality-640x360-p100",
                                        100, 10, verdict="WARN")]}
        data["video"] = {
            "capability": {"playback": False, "decoder": "none",
                           "media_error": "MEDIA_ERR_SRC_NOT_SUPPORTED"},
            "last_run": {"status": "PASS", "date": "test"},
            "profiles": [{"id": "360p", "box": "640x360",
                          "attributes": "width=640", "contract": "placeholder",
                          "status": "CONTRATO"}],
        }
        text = recommend.build_markdown(data)
        self.assertIn("## Performance detail", text)
        self.assertIn("## Games detail", text)
        self.assertIn("## Video detail", text)
        self.assertIn("game.quality-640x360-p100", text)

    def test_markdown_mentions_limits_and_evidence(self):
        data = dict(BASE)
        data["security"] = {"results": [{"id": "xss.bad", "status": "FAIL"}]}
        text = recommend.build_markdown(data)
        self.assertIn("Automatic recommendations", text)
        self.assertIn("Acceptance criterion", text)
        self.assertIn("NativaX does not decode", text)

    def test_every_recommendation_has_a_registered_id_rule_and_impact(self):
        data = dict(BASE)
        data["app_idle"] = {"status": "ok", "rss_tail_mb": 320, "cpu_tail_pct": 0}
        data["security"] = {"results": [{"id": "xss.bad", "status": "FAIL"}]}
        data["capabilities"] = {"video": False, "game_player": False}
        recs = recommend.build_recommendations(data)
        self.assertTrue(recs)
        for rec in recs:
            self.assertIn(rec.id, recommend.RULES)
            self.assertTrue(rec.rule["conditions"])
            self.assertTrue(rec.expected_impact)
            self.assertIsNone(rec.measured_impact)
        idle = next(r for r in recs if r.id == "memory.idle.over_target")
        self.assertEqual(idle.rule["logic"], "any")
        self.assertEqual(idle.rule["conditions"][0], {
            "metric": "app_idle.rss_tail_mb", "op": ">",
            "threshold": 250.0, "observed": 320.0,
        })

    def test_id_is_stable_when_numbers_change(self):
        ids = []
        for missing in (1, 7):
            data = dict(BASE)
            data["visual_catalog"] = [{"id": str(i)} for i in range(missing)]
            recs = recommend.build_recommendations(data)
            ids.append({r.id for r in recs if r.area == "visual coverage"})
        self.assertEqual(ids[0], ids[1])
        self.assertEqual(ids[0], {"visual.coverage.missing_pages"})

    def test_measured_impact_compares_before_and_after(self):
        before = dict(BASE)
        before["app_idle"] = {"status": "ok", "rss_tail_mb": 400, "cpu_tail_pct": 0}
        after = dict(BASE)
        after["app_idle"] = {"status": "ok", "rss_tail_mb": 300, "cpu_tail_pct": 0}
        recs = recommend.build_recommendations(after, before=before)
        idle = next(r for r in recs if r.id == "memory.idle.over_target")
        rss = idle.measured_impact[0]
        self.assertEqual((rss["before"], rss["after"], rss["delta"]), (400.0, 300.0, -100.0))
        self.assertTrue(rss["moved_as_expected"])
        self.assertEqual(rss["status"], "improved")
        cpu = idle.measured_impact[1]
        self.assertEqual(cpu["status"], "unchanged")

    def test_measured_impact_is_inconclusive_without_before_metric(self):
        data = dict(BASE)
        data["visual"] = {"rows": [{"page": "p", "position": 10}]}
        recs = recommend.build_recommendations(data, before={})
        low = next(r for r in recs if r.id == "visual.position.low")
        self.assertEqual(low.measured_impact[0]["status"], "inconclusive")
        self.assertIsNone(low.measured_impact[0]["moved_as_expected"])

    def test_audit_reports_same_id_shared_subject_and_ordering(self):
        make = recommend.Recommendation
        recs = [
            make("P1", "a", "t", id="perf.dom.over_target",
                 rule={"conditions": [], "subjects": ["perf:x"]}),
            make("P1", "b", "t", id="perf.game.over_target",
                 rule={"conditions": [], "subjects": ["perf:x"]}),
            make("P1", "c", "t", id="visual.position.low", rule={"conditions": []}),
            make("P1", "d", "t", id="visual.color.low", rule={"conditions": []}),
            make("P1", "d", "t", id="visual.color.low", rule={"conditions": []}),
        ]
        report = recommend.audit(recs)
        kinds = sorted(d["kind"] for d in report["duplicates"])
        self.assertEqual(kinds, ["same_id", "shared_subjects"])
        self.assertEqual(
            [(c["kind"], c["ids"]) for c in report["contradictions"]],
            [("ordering", ["visual.color.low", "visual.position.low"])],
        )

    def test_audit_reports_exclusive_rules(self):
        make = recommend.Recommendation
        recs = [
            make("P0", "m", "t", id="memory.idle.over_target", rule={"conditions": []}),
            make("P2", "m", "t", id="memory.load_peak.unmeasured", rule={"conditions": []}),
        ]
        report = recommend.audit(recs)
        self.assertEqual(report["contradictions"][0]["kind"], "exclusive")

    def test_markdown_shows_rule_id_and_unmeasured_impact(self):
        text = recommend.build_markdown(BASE)
        self.assertIn("**Rule:** `memory.load_peak.unmeasured`", text)
        self.assertIn("not measured (no before/after runs)", text)
        self.assertIn("## Consistency", text)


if __name__ == "__main__":
    unittest.main()

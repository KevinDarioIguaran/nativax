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
        self.assertTrue(any(r.priority == "P0" and r.area == "memoria" for r in recs))

    def test_idle_without_load_peak_is_p2(self):
        recs = recommend.build_recommendations(BASE)
        self.assertTrue(any(r.area == "memoria" and r.priority == "P2" for r in recs))

    def test_coverage_is_reported(self):
        data = dict(BASE)
        data["visual"] = {"rows": [{"page": "a", "overall": 90, "position": 90,
                                    "layout": 90, "color": 90, "design": 90}]}
        data["visual_catalog"] = [{"id": "a"}, {"id": "b"}]
        data["perf_catalog"] = [{"id": "x"}, {"id": "y"}]
        recs = recommend.build_recommendations(data)
        self.assertTrue(any("cobertura visual" in r.area for r in recs))
        self.assertTrue(any("cobertura de rendimiento" in r.area for r in recs))

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
        self.assertTrue(any(r.priority == "P0" and r.area == "seguridad" for r in recs))

    def test_leak_failure_is_p0(self):
        data = dict(BASE)
        data["leaks"] = {"results": [{"id": "dom.leak", "status": "FAIL"}]}
        recs = recommend.build_recommendations(data)
        self.assertTrue(any(r.priority == "P0" and r.area == "fugas" for r in recs))

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
        self.assertIn("## Detalle de rendimiento", text)
        self.assertIn("## Detalle de juegos", text)
        self.assertIn("## Detalle de vídeo", text)
        self.assertIn("game.quality-640x360-p100", text)

    def test_markdown_mentions_limits_and_evidence(self):
        data = dict(BASE)
        data["security"] = {"results": [{"id": "xss.bad", "status": "FAIL"}]}
        text = recommend.build_markdown(data)
        self.assertIn("Recomendaciones automáticas", text)
        self.assertIn("Criterio de aceptación", text)
        self.assertIn("NativaX no decodifica", text)


if __name__ == "__main__":
    unittest.main()

"""Tests for the recommendation evaluator and the committed dataset."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import evaluate
import recommend


def fake_engine(fired_by_case):
    def engine(data):
        return [
            recommend.Recommendation("P1", "a", "t", id=rule, rule={"conditions": []})
            for rule in fired_by_case[data["case"]]
        ]
    return engine


class EvaluatorTest(unittest.TestCase):
    def test_precision_recall_missed_and_must_not(self):
        cases = [
            {"id": "one", "input": {"case": "one"},
             "expected": ["visual.position.low", "visual.color.low"],
             "must_not": ["visual.ink.missing"]},
            {"id": "two", "input": {"case": "two"},
             "expected": ["visual.position.low"], "must_not": []},
        ]
        engine = fake_engine({
            "one": ["visual.position.low", "visual.ink.missing"],
            "two": ["visual.position.low"],
        })
        report = evaluate.evaluate(cases, engine)
        position = report["per_rule"]["visual.position.low"]
        self.assertEqual((position["tp"], position["fp"], position["fn"]), (2, 0, 0))
        self.assertEqual(position["precision"], 1.0)
        color = report["per_rule"]["visual.color.low"]
        self.assertEqual(color["recall"], 0.0)
        self.assertIsNone(color["precision"])
        ink = report["per_rule"]["visual.ink.missing"]
        self.assertEqual((ink["fp"], ink["must_not_hits"]), (1, 1))
        one = report["cases"][0]
        self.assertEqual(one["missed"], ["visual.color.low"])
        self.assertEqual(one["must_not_hits"], ["visual.ink.missing"])
        self.assertFalse(one["pass"])
        self.assertTrue(report["cases"][1]["pass"])
        s = report["summary"]
        self.assertEqual((s["tp"], s["fp"], s["fn"]), (2, 1, 1))
        self.assertEqual((s["precision"], s["recall"]), (0.6667, 0.6667))

    def test_engine_crash_is_reported_not_raised(self):
        def broken(data):
            raise AttributeError("boom")
        cases = [{"id": "x", "input": {}, "expected": ["memory.idle.unmeasured"]}]
        report = evaluate.evaluate(cases, broken)
        self.assertEqual(report["summary"]["errors"], 1)
        self.assertEqual(report["cases"][0]["missed"], ["memory.idle.unmeasured"])

    def test_priority_mismatch_and_contradiction_fail_the_case(self):
        fired = ["memory.idle.over_target", "memory.load_peak.unmeasured"]
        cases = [{"id": "x", "input": {"case": "x"}, "expected": fired,
                  "expected_priorities": {"memory.idle.over_target": "P0"}}]
        report = evaluate.evaluate(cases, fake_engine({"x": fired}))
        case = report["cases"][0]
        self.assertEqual(case["priority_mismatches"][0]["actual"], "P1")
        self.assertEqual(case["contradictions"][0]["kind"], "exclusive")
        self.assertFalse(case["pass"])


class DatasetTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = evaluate.load_cases()

    def test_cases_are_well_formed(self):
        self.assertGreaterEqual(len(self.cases), 40)
        ids = [case["id"] for case in self.cases]
        self.assertEqual(len(ids), len(set(ids)))
        for case in self.cases:
            with self.subTest(case=case["id"]):
                self.assertTrue(case["description"])
                self.assertTrue(case["grounds"])
                self.assertIsInstance(case["input"], dict)
                expected = set(case["expected"])
                must_not = set(case["must_not"])
                self.assertFalse(expected & must_not)
                self.assertLessEqual(expected | must_not, set(recommend.RULES))
                self.assertLessEqual(set(case["expected_priorities"]), expected)

    def test_every_rule_has_a_positive_and_a_negative_case(self):
        for rule in recommend.RULES:
            with self.subTest(rule=rule):
                self.assertTrue(any(rule in c["expected"] for c in self.cases))
                self.assertTrue(any(rule in c["must_not"] for c in self.cases))


    def test_engine_is_clean_on_the_dataset(self):
        report = evaluate.evaluate(self.cases)
        findings = [case for case in report["cases"] if not case["pass"]]
        self.assertEqual(findings, [])
        summary = report["summary"]
        self.assertEqual((summary["precision"], summary["recall"]), (1.0, 1.0))


if __name__ == "__main__":
    unittest.main()

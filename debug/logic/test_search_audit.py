#!/usr/bin/env python3
"""Search accuracy regression test (debug/logic/search_audit.py).

    python3 debug/logic/test_search_audit.py
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import catalog  # noqa: E402
import search_audit  # noqa: E402


class SearchAuditTest(unittest.TestCase):
    def test_every_query_class_is_exact(self):
        data = search_audit.audit()
        for row in data["rows"]:
            self.assertEqual((row["precision"], row["recall"]), (1.0, 1.0), row["class"])
        self.assertTrue(data["counts_by_type_consistent"])

    def test_typo_fallback_only_when_nothing_matches(self):
        self.assertTrue(catalog._near("lekas", "leaks"))      # transposition
        self.assertTrue(catalog._near("leak", "leaks"))       # deletion
        self.assertTrue(catalog._near("laeks", "leaks"))
        self.assertFalse(catalog._near("lks", "leaks"))
        refs = search_audit.corpus()
        # "leak" matches exactly as a substring, so no fuzzy widening happens.
        self.assertEqual({r.area for r in catalog.search(refs, "leak")}, {"leaks"})
        self.assertEqual(catalog.search(refs, "zzzz-not-there"), [])


if __name__ == "__main__":
    unittest.main(verbosity=1)

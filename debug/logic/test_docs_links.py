"""Guard: maintained Markdown must not link to paths that do not exist.

Delegates to ``tools/check_docs.py`` so the docs test and the published audit
use the same exclusions and link parser. Archived Spanish evidence and
generated reports are excluded there explicitly.
"""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
import tools.check_docs as check_docs  # noqa: E402


class DocsLinksTest(unittest.TestCase):
    def test_local_links_resolve(self):
        issues = check_docs.local_link_issues(ROOT)
        broken = [
            f"{issue['path']}:{issue.get('line', '?')} -> {issue.get('target', '')}"
            for issue in issues
        ]
        self.assertEqual(broken, [], "\n".join(broken))


if __name__ == "__main__":
    unittest.main()

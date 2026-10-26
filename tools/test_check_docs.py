#!/usr/bin/env python3
"""Tests for the documentation audit contract."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import tools.check_docs as check_docs  # noqa: E402


class Fixture:
    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def write(self, rel: str, text: str) -> Path:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def close(self) -> None:
        self._tmp.cleanup()


class DocsAuditTest(unittest.TestCase):
    def test_local_links_and_references(self):
        fx = Fixture()
        try:
            fx.write("docs/guide.md", "# Guide\n")
            good = fx.write("README.md", "[guide](docs/guide.md)\n[ref]\n\n[ref]: docs/guide.md\n")
            self.assertEqual(check_docs.local_link_issues(fx.root, [good]), [])
            bad = fx.write("docs/bad.md", "[missing](../missing.md)\n")
            issues = check_docs.local_link_issues(fx.root, [bad])
            self.assertEqual([i["kind"] for i in issues], ["broken-link"])
        finally:
            fx.close()

    def test_language_check_ignores_code(self):
        fx = Fixture()
        try:
            spanish = fx.write(
                "docs/es.md",
                "# Página de prueba\n\n"
                "Esta página describe el motor, los datos y las pruebas para que "
                "pueda usarse como ejemplo. También incluye resultados y "
                "seguridad. El archivo se usa para medir el rendimiento de cada "
                "función cuando hay datos del usuario.\n",
            )
            issues = check_docs.language_issues([spanish], fx.root)
            self.assertEqual([i["kind"] for i in issues], ["language"])

            code_only = fx.write(
                "docs/code.md",
                "# English\n\nThis page is English.\n\n```text\n"
                "Esta página describe el motor y los datos para que pueda usarse.\n"
                "```\n",
            )
            self.assertEqual(check_docs.language_issues([code_only], fx.root), [])
        finally:
            fx.close()

    def test_source_paths_and_placeholders(self):
        fx = Fixture()
        try:
            fx.write("docs/guide.md", "# Guide\n")
            good = fx.write("README.md", "See `docs/guide.md` and `docs/guide.md:12`.\n")
            self.assertEqual(check_docs.source_reference_issues([good], fx.root), [])
            bad = fx.write("docs/bad.md", "See `docs/missing.md`.\n")
            issues = check_docs.source_reference_issues([bad], fx.root)
            self.assertEqual([i["kind"] for i in issues], ["source-path"])

            listed = fx.write(
                "docs/listed.md",
                "See `docs/guide.md`, `docs/missing.md`.\n",
            )
            issues = check_docs.source_reference_issues([listed], fx.root)
            self.assertEqual([i["kind"] for i in issues], ["source-path"])

            placeholder = fx.write(
                "docs/placeholder.md",
                "See `debug/artifacts/runs/<id>/report.json` and `docs/*.md`.\n",
            )
            self.assertEqual(check_docs.source_reference_issues([placeholder], fx.root), [])
        finally:
            fx.close()

    def test_shell_commands(self):
        fx = Fixture()
        try:
            fx.write("tools/exists.sh", "#!/bin/sh\n")
            good = fx.write(
                "README.md",
                "```bash\ncd tools\n./exists.sh\n```\n",
            )
            self.assertEqual(check_docs.command_path_issues([good], fx.root), [])
            bad = fx.write("docs/bad.md", "```bash\n./missing.sh\n```\n")
            issues = check_docs.command_path_issues([bad], fx.root)
            self.assertEqual([i["kind"] for i in issues], ["command-path"])

            external = fx.write("docs/external.md", "```bash\ncd /path/to/checkout\n```\n")
            self.assertEqual(check_docs.command_path_issues([external], fx.root), [])
        finally:
            fx.close()

    def test_public_api_coverage(self):
        fx = Fixture()
        try:
            fx.write(
                "packages/nativax/lib/nativax.dart",
                "export 'src/foo.dart';\n",
            )
            fx.write(
                "packages/nativax/lib/src/foo.dart",
                "class Foo {}\nconst bar = 1;\n",
            )
            api = fx.write("docs/reference/public-api.md", "# API\n")
            issues = check_docs.public_api_issues(fx.root)
            self.assertEqual(
                {i["target"] for i in issues},
                {"Foo", "bar"},
            )
            api.write_text("# API\n\n`Foo` and `bar`.\n", encoding="utf-8")
            self.assertEqual(check_docs.public_api_issues(fx.root), [])
        finally:
            fx.close()

    def test_repository_is_clean(self):
        report = check_docs.audit(ROOT)
        self.assertEqual(report["issues"], [], report["issues"])
        self.assertGreaterEqual(report["summary"]["maintainedFiles"], 90)
        self.assertEqual(report["status"], "pass")

    def test_report_render_contains_result_and_counts(self):
        report = {
            "schema": check_docs.SCHEMA,
            "generatedAt": "2026-01-01T00:00:00+00:00",
            "root": ".",
            "status": "fail",
            "summary": {
                "maintainedFiles": 1,
                "archivedFiles": 0,
                "issues": 1,
                "byKind": {"language": 1},
            },
            "excluded": {"archived": [], "thirdParty": {}, "generatedPrefixes": []},
            "files": ["README.md"],
            "issues": [{"kind": "language", "path": "README.md", "line": 1,
                        "message": "Spanish-like prose"}],
            "commands": {},
        }
        md = check_docs.render_markdown(report)
        self.assertIn("Result: **FAIL**", md)
        self.assertIn("language", md)
        self.assertIn("README.md:1", md)


if __name__ == "__main__":
    unittest.main(verbosity=2)

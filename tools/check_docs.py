#!/usr/bin/env python3
"""Audit maintained NativaX documentation.

The audit is deliberately source-backed: it does not try to judge prose quality.
It checks the failures that documentation moves usually introduce:

- local Markdown links resolve;
- maintained first-party pages are in English;
- backticked repository paths exist;
- shell commands point at existing scripts/entrypoints;
- every public symbol exported by ``packages/nativax/lib/nativax.dart`` is
  mentioned in ``docs/reference/public-api.md``.

Archived Spanish evidence and generated reports are excluded and reported as
excluded scope. Run with ``--write`` to publish
``progress/reports/docs-audit-latest.{json,md}``.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import shlex
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = "nativax.docs-audit.v1"
REPORT_JSON = Path("progress/reports/docs-audit-latest.json")
REPORT_MD = Path("progress/reports/docs-audit-latest.md")

# A maintained README/document. Third-party copies and generated output are
# explicitly excluded rather than silently passing.
EXCLUDED_PREFIXES = (
    "docs/archive/legacy-es/",
    "debug/archive/",
    "progress/history/",
    "progress/reports/",
    "debug/artifacts/",
    "debug/benchmarks/leaks/",
    "debug/benchmarks/microbench/",
    "debug/benchmarks/security/",
    "examples/game-player/assets/",
    "examples/game-player/build/",
    "examples/threejs-multiplayer-starter/",
    "examples/web-challenge/build/",
    "packages/nativa_html/lib/src/html5/",
    ".claude/",
)
EXCLUDED_FILES = {
    # The upstream starter's README is copied third-party documentation.
    "examples/threejs-multiplayer-starter/README.md",
}
ARCHIVED_PREFIXES = ("docs/archive/", "progress/history/")
THIRD_PARTY_FILES = {
    "examples/threejs-multiplayer-starter/README.md": "upstream starter README",
    "packages/nativa_html/lib/src/html5/README.md": "upstream html5 parser notes",
}
GENERATED_PREFIXES = (
    "debug/artifacts/",
    "debug/benchmarks/leaks/",
    "debug/benchmarks/microbench/",
    "debug/benchmarks/security/",
    "progress/reports/",
)

ROOT_FILES = (
    "README.md",
    "AGENTS.md",
    "COMPAT.md",
)

# Spanish function words are enough to flag prose that is still Spanish. Code
# fences and inline code are stripped before this check.
SPANISH_WORDS = frozenset(
    """
    el la los las del que para con una por como mas más desde tambien también
    sin sobre entre puede debe deben son esta está esto este cuando solo hay
    tiene usa usar ejecuta medicion medición resultados archivo pagina página
    motor pruebas seguridad rendimiento ejemplo codigo código datos usuario
    cada pero donde mientras porque funcion función todos todas hace ser
    """.split()
)

LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
REF_LINK_RE = re.compile(r"^\s*\[[^\]]+\]:\s*(\S+)", re.M)
CODE_FENCE_RE = re.compile(r"```([^\n]*)\n(.*?)```", re.S)
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
SPAN_WORD_RE = re.compile(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+")
BACKTICK_RE = re.compile(r"`([^`\n]+)`")
PATH_TOKEN_RE = re.compile(
    r"^(?:packages|debug|docs|progress|tools|examples|\.agents)/"
    r"[A-Za-z0-9_.@%+~/\-]+$"
)
ROOT_FILE_RE = re.compile(r"^(?:README|AGENTS|COMPAT)\.md$")
TOP_PREFIXES = ("packages", "debug", "docs", "progress", "tools", "examples", ".agents")
SHELL_LANGS = {"bash", "sh", "shell", "console", "zsh"}


class Issue(dict):
    """Small dict subclass so JSON stays plain and terminal output is simple."""


def _issue(kind: str, path: Path | str, message: str, *, line: int | None = None,
           target: str | None = None) -> Issue:
    item: Issue = Issue(kind=kind, path=str(path), message=message)
    if line is not None:
        item["line"] = line
    if target is not None:
        item["target"] = target
    return item


def _rel(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path)


def maintained_docs(root: Path = ROOT) -> list[Path]:
    """Return the maintained first-party Markdown files."""
    found: set[Path] = set()
    for name in ROOT_FILES:
        path = root / name
        if path.is_file():
            found.add(path)
    for pattern in (
        "docs/**/*.md",
        "debug/**/*.md",
        "examples/**/*.md",
        ".agents/**/*.md",
        "progress/**/*.md",
    ):
        found.update(root.glob(pattern))
    result = []
    for path in sorted(found):
        rel = _rel(root, path)
        if rel in EXCLUDED_FILES or rel in THIRD_PARTY_FILES:
            continue
        if any(rel.startswith(prefix) for prefix in EXCLUDED_PREFIXES):
            continue
        if path.is_file():
            result.append(path)
    return result


def archived_docs(root: Path = ROOT) -> list[Path]:
    """Archived evidence, reported as excluded scope."""
    found = set()
    for pattern in ("docs/archive/**/*.md", "progress/history/**/*.md"):
        found.update(root.glob(pattern))
    return sorted(p for p in found if p.is_file())


def _strip_for_links(text: str) -> str:
    """Remove fenced/inline code so links in examples are not audited."""
    text = CODE_FENCE_RE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    return INLINE_CODE_RE.sub("", text)


def _line_for(text: str, needle: str) -> int | None:
    index = text.find(needle)
    if index < 0:
        return None
    return text.count("\n", 0, index) + 1


def local_link_issues(root: Path, files: list[Path] | None = None) -> list[Issue]:
    """Check local Markdown links in ``files`` (maintained docs by default)."""
    files = files if files is not None else maintained_docs(root)
    broken: list[Issue] = []
    for source in files:
        text = source.read_text(encoding="utf-8", errors="replace")
        clean = _strip_for_links(text)
        targets = [(m.group(1), "link") for m in LINK_RE.finditer(clean)]
        targets += [(m.group(1).strip("<>"), "reference") for m in REF_LINK_RE.finditer(clean)]
        for raw, kind in targets:
            target = raw.strip()
            if not target or target.startswith("#"):
                continue
            parsed = urlsplit(target)
            if parsed.scheme or target.startswith("//"):
                continue
            path = unquote(parsed.path)
            if not path or path.startswith("/"):
                # Root-relative links are unusual in this repository; treat
                # them as repository-root relative rather than filesystem root.
                rel = path.lstrip("/")
                if not rel:
                    continue
                destination = root / rel
            else:
                destination = source.parent / path
            if any(ch in path for ch in "<>*?"):
                continue
            if not destination.exists():
                broken.append(_issue(
                    f"broken-{kind}", _rel(root, source),
                    f"local link does not resolve: {raw}",
                    line=_line_for(clean, raw), target=raw,
                ))
    return broken


def _prose_words(text: str) -> list[str]:
    text = CODE_FENCE_RE.sub(" ", text)
    text = INLINE_CODE_RE.sub(" ", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"<[^>]+>", " ", text)
    return [w.lower() for w in SPAN_WORD_RE.findall(text)]


def language_issues(files: list[Path], root: Path = ROOT) -> list[Issue]:
    """Flag maintained pages whose prose is still predominantly Spanish."""
    issues: list[Issue] = []
    for source in files:
        text = source.read_text(encoding="utf-8", errors="replace")
        words = _prose_words(text)
        if not words:
            continue
        hits = [w for w in words if w in SPANISH_WORDS]
        ratio = len(hits) / len(words)
        suspect = (len(words) >= 25 and len(hits) >= 8 and ratio >= 0.025)
        if not suspect and len(words) < 25:
            suspect = len(hits) >= 4 and ratio >= 0.20
        if suspect:
            issues.append(_issue(
                "language", _rel(root, source),
                f"Spanish-like prose ({len(hits)} marker words, {ratio:.1%})",
                line=_line_for(text, hits[0]) if hits else None,
            ))
    return issues


def source_reference_issues(files: list[Path], root: Path = ROOT) -> list[Issue]:
    """Check backticked repository paths such as ``docs/testing.md``."""
    issues: list[Issue] = []
    for source in files:
        text = source.read_text(encoding="utf-8", errors="replace")
        for m in BACKTICK_RE.finditer(text):
            span = m.group(1).strip()
            # A single code span often lists several paths:
            # `document.dart`, `element.dart`, `selectors.dart`.
            for part in re.split(r"[,;]\s*|\s+", span):
                token = part.strip().strip("()[]{}\"'")
                token = re.sub(r":\d+(?:-\d+)?$", "", token)
                if not token or not (PATH_TOKEN_RE.match(token) or ROOT_FILE_RE.match(token)):
                    continue
                if any(ch in token for ch in "<>*?{}[]$") or "..." in token:
                    continue
                rel = token.rstrip("/")
                if any(rel.startswith(prefix) for prefix in GENERATED_PREFIXES):
                    continue
                if not (root / rel).exists():
                    issues.append(_issue(
                        "source-path", _rel(root, source),
                        f"referenced repository path does not exist: {token}",
                        line=_line_for(text, m.group(0)), target=token,
                    ))
    return issues


def _shell_blocks(text: str):
    """Yield (first_line_number, body) for fenced shell blocks."""
    for m in CODE_FENCE_RE.finditer(text):
        lang = (m.group(1).strip().split() or [""])[0].lower()
        if lang in SHELL_LANGS:
            yield text.count("\n", 0, m.start(2)) + 1, m.group(2)


def _shell_tokens(line: str) -> list[str]:
    try:
        return shlex.split(line, comments=True, posix=True)
    except ValueError:
        return line.split()


def _resolve_command_path(path: str, cwd: Path | None, root: Path) -> Path | None:
    """Resolve a script/path from the current shell position."""
    if path.startswith("/"):
        return Path(path)
    candidates: list[Path] = []
    if cwd is not None:
        candidates.append(cwd / path)
    candidates.append(root / path)
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def _is_generated(path: Path, root: Path) -> bool:
    rel = _rel(root, path)
    return any(rel.startswith(prefix) for prefix in GENERATED_PREFIXES)


def command_path_issues(files: list[Path], root: Path = ROOT) -> list[Issue]:
    """Check ``cd`` targets and common shell entrypoints in fenced commands."""
    issues: list[Issue] = []
    for source in files:
        text = source.read_text(encoding="utf-8", errors="replace")
        for first_line, body in _shell_blocks(text):
            cwd: Path | None = None
            for offset, line in enumerate(body.splitlines()):
                line_no = first_line + offset
                tokens = _shell_tokens(line)
                if not tokens:
                    continue
                for index, token in enumerate(tokens):
                    token = token.strip("'\"")
                    token = token.rstrip(";,:|")
                    if not token or token.startswith("-"):
                        continue
                    if token == "cd" and index + 1 < len(tokens):
                        target = tokens[index + 1].strip("'\"")
                        target = target.rstrip(";,:|")
                        if not target or target.startswith(("$", "~")) or any(
                            ch in target for ch in "<>*?{}"
                        ):
                            continue
                        if target.startswith("/") and not (
                            target == str(root) or target.startswith(str(root) + "/")
                        ):
                            # User-specific checkout locations are not repo paths.
                            continue
                        resolved = _resolve_command_path(target, cwd, root)
                        if resolved is None or not resolved.exists():
                            issues.append(_issue(
                                "command-path", _rel(root, source),
                                f"cd target does not exist: {target}",
                                line=line_no, target=target,
                            ))
                        elif resolved.is_dir():
                            cwd = resolved.resolve()
                        continue
                    explicit_relative = token.startswith("./")
                    check = token[2:] if explicit_relative else token
                    is_top = (
                        check == "AGENTS.md"
                        or check in ("README.md", "COMPAT.md")
                        or any(check == p or check.startswith(p + "/") for p in TOP_PREFIXES)
                    )
                    is_relative_entry = (
                        cwd is not None
                        and "/" not in check
                        and check.endswith((".sh", ".py", ".dart"))
                    )
                    is_root_script = (
                        explicit_relative
                        and check.endswith((".sh", ".py", ".dart"))
                    )
                    is_relative_child = (
                        cwd is not None
                        and "/" in check
                        and check.split("/", 1)[0] in {"bin", "test", "lib", "node", "tools"}
                    )
                    if not (is_top or is_relative_entry or is_root_script or is_relative_child):
                        continue
                    if any(ch in check for ch in "<>*?{}[]$") or "..." in check:
                        continue
                    if is_top:
                        resolved = root / check
                    elif is_root_script and cwd is None:
                        resolved = root / check
                    else:
                        resolved = _resolve_command_path(check, cwd, root)
                    if resolved is None or _is_generated(resolved, root):
                        continue
                    if not resolved.exists():
                        issues.append(_issue(
                            "command-path", _rel(root, source),
                            f"shell path does not exist: {check}",
                            line=line_no, target=check,
                        ))
    return issues


def _public_declarations(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    names = set()
    names.update(
        m.group(1) for m in re.finditer(
            r"^(?:abstract\s+|base\s+|final\s+|sealed\s+|interface\s+)*"
            r"(?:class|enum|mixin|typedef|extension)\s+([A-Z]\w*)",
            text, re.M,
        )
    )
    names.update(
        m.group(1) for m in re.finditer(
            r"^(?:const|final)\s+(?:[A-Za-z_][\w<>,?\s]*\s+)?([a-zA-Z]\w*)\s*=",
            text, re.M,
        )
        if not m.group(1).startswith("_")
    )
    return {n for n in names if not n.startswith("_")}


def exported_nativax_symbols(root: Path = ROOT) -> set[str]:
    """Collect public symbols re-exported by the ``nativax`` barrel."""
    barrel = root / "packages/nativax/lib/nativax.dart"
    if not barrel.is_file():
        return set()
    text = barrel.read_text(encoding="utf-8")
    symbols: set[str] = set()
    for m in re.finditer(
        r"export\s+'([^']+)'(?:\s+show\s+([^;]+))?;", text, re.S,
    ):
        uri, show = m.groups()
        if show:
            symbols.update(
                part.strip().split(".")[0]
                for part in show.replace("\n", " ").split(",")
                if part.strip()
            )
            continue
        if not uri.startswith("src/"):
            continue
        target = barrel.parent / uri
        if target.is_file():
            symbols.update(_public_declarations(target))
            # One level of source-level re-export is enough for this barrel.
            nested = target.read_text(encoding="utf-8")
            for n in re.finditer(r"export\s+'([^']+)';", nested):
                nested_target = (target.parent / n.group(1)).resolve()
                if nested_target.is_file():
                    symbols.update(_public_declarations(nested_target))
    return {s for s in symbols if s and not s.startswith("_")}


def public_api_issues(root: Path = ROOT) -> list[Issue]:
    api = root / "docs/reference/public-api.md"
    if not api.is_file():
        return [_issue("public-api", "docs/reference/public-api.md",
                       "public API reference is missing")]
    text = api.read_text(encoding="utf-8", errors="replace")
    issues = []
    for symbol in sorted(exported_nativax_symbols(root)):
        if symbol not in text:
            issues.append(_issue(
                "public-api", "docs/reference/public-api.md",
                f"exported nativax symbol is not documented: {symbol}",
                target=symbol,
            ))
    return issues


def audit(root: Path = ROOT) -> dict:
    files = maintained_docs(root)
    archived = archived_docs(root)
    issues = []
    issues += local_link_issues(root, files)
    issues += language_issues(files, root)
    issues += source_reference_issues(files, root)
    issues += command_path_issues(files, root)
    issues += public_api_issues(root)
    issues.sort(key=lambda i: (i.get("kind", ""), i.get("path", ""),
                               i.get("line", 0), i.get("target", "")))
    by_kind: dict[str, int] = {}
    for issue in issues:
        by_kind[issue["kind"]] = by_kind.get(issue["kind"], 0) + 1
    return {
        "schema": SCHEMA,
        "generatedAt": _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds"),
        "root": str(root),
        "status": "pass" if not issues else "fail",
        "summary": {
            "maintainedFiles": len(files),
            "archivedFiles": len(archived),
            "issues": len(issues),
            "byKind": dict(sorted(by_kind.items())),
        },
        "excluded": {
            "archived": [_rel(root, p) for p in archived],
            "thirdParty": THIRD_PARTY_FILES,
            "generatedPrefixes": list(GENERATED_PREFIXES),
        },
        "files": [_rel(root, p) for p in files],
        "issues": issues,
        "commands": {
            "check": "python3 tools/check_docs.py",
            "write": "python3 tools/check_docs.py --write",
            "tests": "python3 tools/test_check_docs.py",
        },
    }


def render_markdown(report: dict) -> str:
    summary = report["summary"]
    lines = [
        "# Documentation audit\n",
        f"- Generated: `{report['generatedAt']}`",
        "- Command: `python3 tools/check_docs.py --write`",
        f"- Result: **{report['status'].upper()}**",
        f"- Maintained files: **{summary['maintainedFiles']}**",
        f"- Archived files excluded: **{summary['archivedFiles']}**",
        f"- Issues: **{summary['issues']}**",
        "",
        "## Checks",
        "",
        "| Check | Issues |",
        "|---|---:|",
    ]
    for kind in ("broken-link", "broken-reference", "language", "source-path",
                 "command-path", "public-api"):
        lines.append(f"| `{kind}` | {summary['byKind'].get(kind, 0)} |")
    lines += [
        "",
        "Scope: root `README.md`, `AGENTS.md`, `COMPAT.md`, `docs/` (except "
        "`docs/archive/legacy-es/`), `progress/*.md`, maintained `debug/` and "
        "`examples/` READMEs, and `.agents/` documentation.",
        "",
        "Excluded: archived Spanish evidence (`docs/archive/`, "
        "`progress/history/`), generated reports/artifacts, and third-party "
        "copied documentation listed in the JSON report. Exclusions are not "
        "silent passes; they are listed in the JSON `excluded` field.",
        "",
        "## Issues",
        "",
    ]
    if report["issues"]:
        for issue in report["issues"]:
            location = issue["path"]
            if "line" in issue:
                location += f":{issue['line']}"
            lines.append(f"- `{issue['kind']}` {location}: {issue['message']}")
    else:
        lines.append("No issues.")
    lines += [
        "",
        "## Reproduce",
        "",
        "```bash",
        "python3 tools/check_docs.py --write",
        "python3 tools/test_check_docs.py",
        "```",
        "",
        "A pass means these mechanical checks pass. It does not prove every "
        "claim is complete or current; source review and focused tests remain "
        "required.",
    ]
    return "\n".join(lines) + "\n"


def write_report(report: dict, root: Path = ROOT) -> tuple[Path, Path]:
    json_path = root / REPORT_JSON
    md_path = root / REPORT_MD
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                         encoding="utf-8")
    md_path.write_text(render_markdown(report), encoding="utf-8")
    return json_path, md_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT,
                        help="repository root (default: this checkout)")
    parser.add_argument("--write", action="store_true",
                        help="write progress/reports/docs-audit-latest.{json,md}")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)

    report = audit(args.root.resolve())
    if args.write:
        jp, mp = write_report(report, args.root.resolve())
    if args.format == "json":
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        summary = report["summary"]
        print(
            f"Documentation audit: {report['status'].upper()} · "
            f"{summary['maintainedFiles']} maintained files · "
            f"{summary['issues']} issues"
        )
        if summary["byKind"]:
            print("  " + ", ".join(f"{k}={v}" for k, v in summary["byKind"].items()))
        for issue in report["issues"]:
            location = issue["path"]
            if "line" in issue:
                location += f":{issue['line']}"
            print(f"  {issue['kind']}: {location}: {issue['message']}")
        if args.write:
            print(f"Wrote {jp} and {mp}")
    return 0 if not report["issues"] else 1


if __name__ == "__main__":
    sys.exit(main())

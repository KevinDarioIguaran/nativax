#!/usr/bin/env python3
"""Architecture guard: no embedded browser, and tooling that still resolves
the repository root after the moves into debug/.

The second check exists because moving a script without updating its ".."
chain breaks it silently: the script runs, computes the wrong root and then
fails on the first `$root/debug/...` reference. Every shell script under
tools/ and debug/ that derives a root from BASH_SOURCE, and every single-line
`ROOT = Path(__file__).resolve()...` assignment there, must resolve to ROOT.
Scripts using other idioms are not covered by this guard.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = re.compile(
    r"(webview_flutter|flutter_inappwebview|HtmlElementView|InAppWebView|"
    r"WebViewController|\bcef\b|\belectron\b|localhost:\d+|"
    r"http\.server|HttpServer)",
    re.I,
)
SKIP = {"tests", "test", "examples", "docs", "progress", "build",
        ".dart_tool", ".git", "assets", "static", "tools", "node_modules"}

bad = []
for path in ROOT.rglob("*"):
    if not path.is_file() or path.suffix not in {".dart", ".yaml", ".yml"}:
        continue
    rel = path.relative_to(ROOT)
    if any(part in SKIP for part in rel.parts):
        continue
    try:
        text = path.read_text(errors="ignore")
    except OSError:
        continue
    for match in FORBIDDEN.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        bad.append(f"{rel}:{line}: {match.group(0)}")

if bad:
    print("architecture guard FAILED")
    for item in bad[:50]:
        print(item)
    sys.exit(1)

# --- tooling must still resolve the repository root ------------------------
CHAIN = re.compile(r'BASH_SOURCE\[0\]\}"\)(/[.][^\s"&|)]*)')
ROOT_LINE = re.compile(r"^\s*ROOT\s*=\s*Path\(__file__\)\.resolve\(\)(.+)$")

TOOLING = ("tools", "debug")


def _resolved_root(file: Path, tail: str) -> Path | None:
    tail = tail.strip()
    if tail.startswith(".parents["):
        try:
            depth = int(tail[len(".parents["):tail.index("]")])
        except (ValueError, IndexError):
            return None
        return file.resolve().parents[depth]
    if tail.startswith(".parent"):
        resolved = file.resolve()
        for _ in range(tail.count(".parent")):
            resolved = resolved.parent
        return resolved
    return None


wrong = []
checked = 0
for name in TOOLING:
    for path in sorted((ROOT / name).rglob("*")):
        if not path.is_file() or "__pycache__" in path.parts:
            continue
        rel = path.relative_to(ROOT)
        if path.suffix == ".sh":
            try:
                text = path.read_text(errors="ignore")
            except OSError:
                continue
            for match in CHAIN.finditer(text):
                checked += 1
                chain = match.group(1)
                if (path.parent / chain.lstrip("/")).resolve() != ROOT:
                    wrong.append(f"{rel}: BASH_SOURCE chain {chain}")
        elif path.suffix == ".py":
            try:
                lines = path.read_text(errors="ignore").splitlines()
            except OSError:
                continue
            for line in lines:
                match = ROOT_LINE.match(line)
                if not match:
                    continue
                checked += 1
                if _resolved_root(path, match.group(1)) != ROOT:
                    wrong.append(f"{rel}: ROOT = ...{match.group(1).strip()}")

if wrong:
    print("repo-root guard FAILED (moved tooling resolves the wrong root)")
    for item in wrong[:50]:
        print(item)
    sys.exit(1)
if checked < 15:
    print(f"repo-root guard FAILED: only {checked} assignments checked")
    sys.exit(1)
print(f"architecture guard OK ({checked} tooling root assignments resolve to the repo root)")

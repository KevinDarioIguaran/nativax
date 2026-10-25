#!/usr/bin/env python3
"""Architecture guard: NativaX must not embed a browser or HTTP server."""
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
print("architecture guard OK")

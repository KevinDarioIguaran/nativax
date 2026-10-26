#!/usr/bin/env python3
"""Render a Markdown report to a readable HTML page (preview, not source).

    python3 debug/scripts/render_report.py progress/reports/nativa-quality-latest.md
    python3 debug/scripts/render_report.py --open progress/reports/perf-latest.md

The HTML is written to debug/artifacts/perf/preview/<name>.html and local images/links are
resolved to absolute file:// URLs so it works from any directory.
"""
from __future__ import annotations

import argparse
import html
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREVIEW_DIR = ROOT / "debug" / "artifacts" / "perf" / "preview"


def resolve_url(url: str, base: Path) -> str:
    if re.match(r"^(https?:|file:|data:|mailto:|#)", url):
        return url
    path = (base / url).resolve()
    return path.as_uri()


def inline(text: str, base: Path) -> str:
    # Escape first so user text cannot inject HTML, then apply Markdown.
    text = html.escape(text, quote=False)
    def image(match):
        alt, src = match.group(1), match.group(2)
        return f'<img alt="{alt}" src="{html.escape(resolve_url(src, base))}">'

    text = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", image, text)

    def link(match):
        label, href = match.group(1), match.group(2)
        return f'<a href="{html.escape(resolve_url(href, base))}">{label}</a>'

    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", text)
    return text


def render(markdown: str, base: Path, title: str) -> str:
    lines = markdown.splitlines()
    out: list[str] = []
    paragraph: list[str] = []
    in_code = False
    code: list[str] = []
    table: list[list[str]] = []

    def flush_paragraph():
        nonlocal paragraph
        if paragraph:
            out.append(f"<p>{inline(' '.join(paragraph), base)}</p>")
            paragraph = []

    def flush_table():
        nonlocal table
        if not table:
            return
        header, body = table[0], table[2:]
        out.append("<table><thead><tr>")
        out.extend(f"<th>{inline(cell, base)}</th>" for cell in header)
        out.append("</tr></thead><tbody>")
        for row in body:
            out.append("<tr>")
            out.extend(f"<td>{inline(cell, base)}</td>" for cell in row)
            out.append("</tr>")
        out.append("</tbody></table>")
        table = []

    for line in lines:
        stripped = line.strip()
        if in_code:
            if stripped.startswith("```"):
                out.append(f"<pre><code>{html.escape(chr(10).join(code))}</code></pre>")
                code = []
                in_code = False
            else:
                code.append(line)
            continue
        if stripped.startswith("```"):
            flush_paragraph()
            flush_table()
            in_code = True
            continue
        if stripped.startswith("|") and stripped.endswith("|"):
            flush_paragraph()
            table.append([cell.strip() for cell in stripped.strip("|").split("|")])
            continue
        flush_table()
        if not stripped:
            flush_paragraph()
            continue
        heading = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading:
            flush_paragraph()
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2), base)}</h{level}>")
            continue
        bullet = re.match(r"^[-*]\s+(.*)$", stripped)
        if bullet:
            flush_paragraph()
            out.append(f"<li>{inline(bullet.group(1), base)}</li>")
            continue
        numbered = re.match(r"^\d+\.\s+(.*)$", stripped)
        if numbered:
            flush_paragraph()
            out.append(f"<li>{inline(numbered.group(1), base)}</li>")
            continue
        if stripped.startswith(">"):
            flush_paragraph()
            out.append(f"<blockquote>{inline(stripped.lstrip('> '), base)}</blockquote>")
            continue
        if stripped.startswith("---"):
            flush_paragraph()
            out.append("<hr>")
            continue
        paragraph.append(stripped)
    flush_paragraph()
    flush_table()
    if in_code:
        out.append(f"<pre><code>{html.escape(chr(10).join(code))}</code></pre>")
    # Turn consecutive list items into lists (simple post-pass).
    merged = []
    in_list = False
    for block in out:
        if block.startswith("<li>"):
            if not in_list:
                merged.append("<ul>")
                in_list = True
            merged.append(block)
        else:
            if in_list:
                merged.append("</ul>")
                in_list = False
            merged.append(block)
    if in_list:
        merged.append("</ul>")

    body = "\n".join(merged)
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin: 0; background: #0b0f14; color: #e6edf3;
         font: 16px/1.6 -apple-system, "Segoe UI", "Noto Sans", sans-serif; }}
  main {{ max-width: 1180px; margin: 0 auto; padding: 36px 26px 80px; }}
  h1 {{ font-size: 2rem; margin: 0 0 18px; color: #fff; }}
  h2 {{ font-size: 1.4rem; margin: 34px 0 12px; color: #7aa2ff;
        border-bottom: 1px solid #212b36; padding-bottom: 6px; }}
  h3 {{ font-size: 1.1rem; margin: 24px 0 8px; color: #39c5cf; }}
  p, li {{ color: #d6dee8; }}
  a {{ color: #7aa2ff; }}
  code {{ background: #161d26; padding: 2px 6px; border-radius: 5px;
          font: 0.9em "DejaVu Sans Mono", ui-monospace, monospace; color: #ffd479; }}
  pre {{ background: #11161d; border: 1px solid #212b36; border-radius: 10px;
         padding: 14px 16px; overflow: auto; }}
  pre code {{ background: none; padding: 0; color: #d6dee8; }}
  table {{ border-collapse: collapse; width: 100%; margin: 14px 0 22px;
           font-size: 0.93rem; }}
  th, td {{ border: 1px solid #212b36; padding: 8px 10px; text-align: left;
            vertical-align: top; }}
  th {{ background: #161d26; color: #9fb3c8; position: sticky; top: 0; }}
  tr:nth-child(even) td {{ background: #0f151d; }}
  img {{ max-width: 100%; border: 1px solid #212b36; border-radius: 10px;
         margin: 12px 0; }}
  blockquote {{ margin: 14px 0; padding: 10px 16px; border-left: 3px solid #d29922;
                background: #11161d; color: #d6dee8; }}
  hr {{ border: none; border-top: 1px solid #212b36; margin: 28px 0; }}
  ul {{ padding-left: 24px; }}
</style></head><body><main>
{body}
</main></body></html>
"""


def main():
    parser = argparse.ArgumentParser(description="Render a NativaX Markdown report to HTML")
    parser.add_argument("input", nargs="?",
                        default="progress/reports/quality-gate-latest.md")
    parser.add_argument("--out")
    parser.add_argument("--open", action="store_true", dest="open_browser")
    parser.add_argument("--png", action="store_true", help="also render a full-page PNG for the UI")
    args = parser.parse_args()
    source = (ROOT / args.input).resolve() if not Path(args.input).is_absolute() else Path(args.input)
    if not source.exists():
        print(f"no existe: {source}", file=sys.stderr)
        return 2
    markdown = source.read_text()
    title = source.stem.replace("-", " ").replace("_", " ")
    html_text = render(markdown, source.parent, title)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    out = Path(args.out) if args.out else PREVIEW_DIR / f"{source.stem}.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html_text)
    print(out)
    if args.png:
        png = out.with_suffix(".png")
        chrome = os.environ.get("CHROME", "google-chrome")
        result = subprocess.run(
            [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
             "--force-device-scale-factor=1", "--window-size=1200,12000",
             "--virtual-time-budget=1500", f"--screenshot={png}", out.as_uri()],
            capture_output=True,
        )
        if result.returncode == 0 and png.exists():
            try:
                from PIL import Image
                image = Image.open(png).convert("RGB")
                background = image.getpixel((2, 2))
                width, height = image.size
                last = height - 1
                while last > 10:
                    row = [image.getpixel((x, last)) for x in range(0, width, 40)]
                    if any(pixel != background for pixel in row):
                        break
                    last -= 1
                if last < height - 1:
                    image.crop((0, 0, width, min(height, last + 30))).save(png, optimize=True)
            except Exception:
                pass
            print(png)
        else:
            print(f"no se pudo generar el PNG: {result.stderr[-300:]}", file=sys.stderr)
    if args.open_browser:
        subprocess.Popen(["xdg-open", str(out)])
    return 0


if __name__ == "__main__":
    sys.exit(main())

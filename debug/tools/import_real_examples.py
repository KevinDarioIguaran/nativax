#!/usr/bin/env python3
"""Import real, self-contained web examples into the debug laboratory.

The laboratory used to contain 1,801 generated clones of a single design
template. This tool replaces that filler with examples taken verbatim from
three public repositories. Every imported case keeps its own HTML, CSS, JS and
assets: nothing is regenerated, rewritten or wrapped in a shared shell.

Sources (pinned commits):

  zxuqian/html-css-examples            MIT
  keshavgbpecdelhi/Web-Development     Apache-2.0
  learning-zone/website-templates      license not declared upstream

The importer copies the original example directory, collects independent
facts with Python's ``html.parser`` (so expectations do not come from NativaX),
and writes ``debug/lab/corpus.json`` plus one ``case.json`` per case.

Usage::

    python3 debug/tools/import_real_examples.py --check
    python3 debug/tools/import_real_examples.py --force
    python3 debug/tools/import_real_examples.py \\
        --source zxuqian=/tmp/opencode/repos/zxuqian \\
        --source keshav=/tmp/opencode/repos/keshav \\
        --source learning=/tmp/opencode/repos/learning

The default source roots are ``/tmp/opencode/repos/{zxuqian,keshav,learning}``.
Use ``--clone`` to fetch them at the pinned commits with git.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

HERE = Path(__file__).resolve().parent
LAB = HERE.parent / "lab"
CASES = LAB / "cases"
MANIFEST = LAB / "corpus.json"
ATTRIBUTION = LAB / "ATTRIBUTION.md"

SOURCES = {
    "zxuqian": {
        "repo": "zxuqian/html-css-examples",
        "url": "https://github.com/zxuqian/html-css-examples.git",
        "commit": "2a9fc59f44aeda092cbac07472aaf0f1ead4e1a6",
        "license": "MIT",
        "default": Path("/tmp/opencode/repos/zxuqian"),
        "roots": ("",),
        "limit": 57,
        "max_bytes": 8_000_000,
    },
    "keshav": {
        "repo": "keshavgbpecdelhi/Web-Development",
        "url": "https://github.com/keshavgbpecdelhi/Web-Development.git",
        "commit": "c1613b1424c3226ecd09ca0f23cd39bc4e32709b",
        "license": "Apache-2.0",
        "default": Path("/tmp/opencode/repos/keshav"),
        "roots": ("projects",),
        "limit": 100,
        "max_bytes": 4_000_000,
    },
    "learning": {
        "repo": "learning-zone/website-templates",
        "url": "https://github.com/learning-zone/website-templates.git",
        "commit": "7bf31e9646a6b5f51c2e55b2557787310436989f",
        "license": "not declared upstream",
        "default": Path("/tmp/opencode/repos/learning"),
        "roots": ("",),
        "limit": 99,
        "max_bytes": 4_500_000,
    },
}

SECTION_PREFIX = {
    1: "html", 2: "css", 3: "box", 4: "typo", 5: "color", 6: "anim",
    7: "resp", 8: "flex", 9: "pos", 10: "jsdom", 11: "events", 12: "forms",
    13: "a11y", 14: "media", 15: "perf", 16: "integ",
}
PER_SECTION = 15

# Tags whose presence is meaningful for the generic DOM check. SVG internals
# are intentionally excluded: HTML parsers disagree about their tree shape.
HTML_TAGS = {
    "a", "abbr", "address", "article", "aside", "audio", "b", "blockquote",
    "body", "button", "canvas", "caption", "cite", "code", "col", "colgroup",
    "data", "datalist", "dd", "del", "details", "dfn", "dialog", "div", "dl",
    "dt", "em", "fieldset", "figcaption", "figure", "footer", "form", "h1",
    "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html",
    "i", "iframe", "img", "input", "ins", "kbd", "label", "legend", "li",
    "link", "main", "map", "mark", "menu", "meta", "meter", "nav", "noscript",
    "object", "ol", "optgroup", "option", "output", "p", "picture", "pre",
    "progress", "q", "rp", "rt", "ruby", "s", "samp", "script", "section",
    "select", "slot", "small", "source", "span", "strong", "style", "sub",
    "summary", "sup", "table", "tbody", "td", "template", "textarea", "tfoot",
    "th", "thead", "time", "title", "tr", "track", "u", "ul", "var", "video",
    "wbr",
}
VOID_TAGS = {
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
    "meta", "param", "source", "track", "wbr",
}
SAMPLE_ATTRS = (
    "id", "class", "role", "title", "alt", "href", "src", "type", "name",
    "placeholder", "value", "style", "width", "height", "for", "lang",
    "aria-label", "aria-hidden", "aria-expanded", "aria-controls", "data-id",
)
RAW_TEXT_TAGS = {"script", "style", "textarea", "template", "noscript"}


# ---------------------------------------------------------------------------
# reference discovery / self-containment
# ---------------------------------------------------------------------------

_CSS_URL = re.compile(r"url\(\s*['\"]?([^'\")]+)['\"]?\s*\)", re.I)
_CSS_IMPORT = re.compile(r"@import\s+(?:url\(\s*)?['\"]([^'\"]+)['\"]", re.I)
_JS_IMPORT = re.compile(
    r"(?:import\s+(?:[^'\"]+?\s+from\s+)?|import\s*\(|require\s*\()\s*['\"]([^'\"]+)['\"]")
_SRCSET = re.compile(r"\s*([^,\s]+)(?:\s+[^,]+)?\s*(?:,|$)")


def _local_ref(ref: str, base: Path, root: Path) -> tuple[str, Path | None, bool]:
    """Return (status, path, escapes). status: ok|missing|external|escape|root."""
    ref = (ref or "").strip()
    if not ref or ref.startswith("#") or ref.startswith("data:"):
        return "external", None, False
    parts = urlsplit(ref)
    if parts.scheme in ("http", "https", "mailto", "tel", "javascript", "blob",
                        "ftp", "ws", "wss") or ref.startswith("//"):
        return "external", None, False
    if ref.startswith("/"):
        return "root", None, False
    rel = unquote(parts.path)
    if not rel:
        return "external", None, False
    candidate = (base / rel).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return "escape", candidate, True
    if not candidate.is_file():
        return "missing", candidate, False
    return "ok", candidate, False


def _style_refs(text: str):
    yield from _CSS_URL.findall(text or "")
    yield from _CSS_IMPORT.findall(text or "")


def discover_refs(entry: Path):
    """Walk HTML/CSS/JS references. Returns (files, missing, escaped, has_base)."""
    root = entry.parent
    seen: set[Path] = set()
    missing: list[str] = []
    escaped: list[str] = []
    queue = [entry]
    has_base = False
    while queue:
        current = queue.pop(0)
        if current in seen or not current.is_file():
            continue
        seen.add(current)
        suffix = current.suffix.lower()
        try:
            text = current.read_text(errors="replace")
        except OSError:
            continue
        refs: list[str] = []
        if suffix in (".html", ".htm"):
            if re.search(r"<base\b", text, re.I):
                has_base = True
            refs.extend(_html_refs(text))
            for block in re.findall(r"<style\b[^>]*>(.*?)</style\s*>", text,
                                    re.I | re.S):
                refs.extend(_style_refs(block))
        elif suffix == ".css":
            refs.extend(_style_refs(text))
        elif suffix in (".js", ".mjs"):
            refs.extend(r for r in _JS_IMPORT.findall(text)
                        if r.startswith(".") or r.startswith("/"))
        for ref in refs:
            status, path, _ = _local_ref(ref, current.parent, root)
            if status == "ok" and path is not None:
                queue.append(path)
            elif status == "missing":
                missing.append(str(path.relative_to(root.resolve())))
            elif status == "escape":
                escaped.append(ref)
    return seen, sorted(set(missing)), sorted(set(escaped)), has_base


_TAG = re.compile(r"<(link|script|img|source|video|audio)\b([^>]*)>", re.I | re.S)
_ATTR = re.compile(r"\b([\w:-]+)\s*=\s*(['\"])(.*?)\2", re.I | re.S)


def _html_refs(text: str) -> list[str]:
    """Assets referenced by an entry document (not navigation links)."""
    refs: list[str] = []
    for match in _TAG.finditer(text):
        tag = match.group(1).lower()
        attrs = {k.lower(): v for k, _q, v in _ATTR.findall(match.group(2))}
        if tag == "link" and attrs.get("href"):
            refs.append(attrs["href"])
        if tag == "script" and attrs.get("src"):
            refs.append(attrs["src"])
        if tag in ("img", "source", "video", "audio"):
            for key in ("src", "poster", "data-src", "data-bg"):
                if attrs.get(key):
                    refs.append(attrs[key])
            if attrs.get("srcset"):
                refs.extend(m.group(1) for m in _SRCSET.finditer(attrs["srcset"]))
        if attrs.get("style"):
            refs.extend(_style_refs(attrs["style"]))
    return refs


# ---------------------------------------------------------------------------
# independent facts
# ---------------------------------------------------------------------------

class FactsParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.max_depth = 0
        self.tags: Counter[str] = Counter()
        self.ids: Counter[str] = Counter()
        self.classes: Counter[str] = Counter()
        self.text_nodes: list[str] = []
        self.title = ""
        self._in_title = False
        self.links: list[str] = []
        self.scripts: list[str] = []
        self.images: list[str] = []
        self.inline_styles: list[str] = []
        self.style_blocks: list[str] = []
        self.scripts_inline: list[str] = []
        self.attrs_by_id: dict[str, dict] = {}
        self.roles = Counter()
        self.aria = Counter()
        self.form_tags = Counter()
        self.media_tags = Counter()
        self._raw: str | None = None
        self._raw_buf: list[str] = []
        self.elements = 0

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        self.tags[tag] += 1
        self.elements += 1
        self.stack.append(tag)
        self.max_depth = max(self.max_depth, len(self.stack))
        a = {k.lower(): (v or "") for k, v in attrs}
        if a.get("id"):
            ident = a["id"]
            self.ids[ident] += 1
            if ident not in self.attrs_by_id:
                self.attrs_by_id[ident] = {
                    "tag": tag,
                    "class": a.get("class", ""),
                    "attrs": {k: a[k] for k in SAMPLE_ATTRS
                              if k in a and a[k] != ""},
                }
        for c in a.get("class", "").split():
            self.classes[c] += 1
        if a.get("style"):
            self.inline_styles.append(a["style"])
        if a.get("role"):
            self.roles[a["role"]] += 1
        for k in a:
            if k.startswith("aria-"):
                self.aria[k] += 1
        if tag == "title":
            self._in_title = True
        if tag == "link" and "stylesheet" in a.get("rel", "").lower() and a.get("href"):
            self.links.append(a["href"])
        if tag == "script" and a.get("src"):
            self.scripts.append(a["src"])
        if tag == "img" and a.get("src"):
            self.images.append(a["src"])
        if tag in ("source", "video", "audio") and a.get("src"):
            self.images.append(a["src"])
        if a.get("poster"):
            self.images.append(a["poster"])
        if tag in ("form", "input", "select", "textarea", "button", "label",
                   "fieldset", "legend", "option", "datalist", "output"):
            self.form_tags[tag] += 1
        if tag in ("img", "picture", "source", "video", "audio", "canvas",
                   "svg", "iframe", "object", "track", "map"):
            self.media_tags[tag] += 1
        if tag in RAW_TEXT_TAGS and tag not in VOID_TAGS:
            self._raw = tag
            self._raw_buf = []
        if tag in VOID_TAGS:
            self.stack.pop()

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag.lower() not in VOID_TAGS and self.stack and self.stack[-1] == tag.lower():
            self.stack.pop()

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag == "title":
            self._in_title = False
        if self._raw == tag:
            content = "".join(self._raw_buf)
            if tag == "style":
                self.style_blocks.append(content)
            elif tag == "script":
                self.scripts_inline.append(content)
            self._raw = None
            self._raw_buf = []
        if tag in self.stack:
            while self.stack:
                if self.stack.pop() == tag:
                    break

    def handle_data(self, data):
        if self._raw is not None:
            self._raw_buf.append(data)
            return
        if self._in_title:
            self.title += data
        if self.stack and self.stack[-1] in RAW_TEXT_TAGS:
            return
        if data.strip() and "body" in self.stack:
            self.text_nodes.append(data)


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "")).strip()


def _css_facts(css: str) -> dict:
    clean = re.sub(r"/\*.*?\*/", " ", css or "", flags=re.S)
    media = len(re.findall(r"@media\b", clean, re.I))
    keyframes = len(re.findall(r"@keyframes\b", clean, re.I))
    selectors: list[str] = []
    rules = 0
    for header in re.findall(r"([^{}]+)\{", clean):
        header = header.strip()
        if not header or header.startswith("@"):
            continue
        for part in header.split(","):
            part = _norm(part)
            if not part or part in ("from", "to") or re.fullmatch(r"[\d.]+%", part):
                continue
            if part.startswith("@"):
                continue
            if re.match(r"^[.#*:a-zA-Z\[]", part):
                rules += 1
                if len(part) <= 80 and part not in selectors:
                    selectors.append(part)
    props = Counter(m.group(1).lower() for m in re.finditer(
        r"(?:^|[;{\s])([a-zA-Z-]{2,32})\s*:", clean))
    prop_names = [p for p, _ in props.most_common() if p not in ("http", "https")]
    return {
        "rules": rules,
        "selectors": selectors[:60],
        "properties": prop_names[:80],
        "property_counts": dict(props.most_common(80)),
        "media": media,
        "keyframes": keyframes,
        "bytes": len((css or "").encode("utf-8", "replace")),
    }


def analyze_case(entry: Path) -> dict:
    text = entry.read_text(errors="replace")
    p = FactsParser()
    try:
        p.feed(text)
    except Exception:
        pass
    linked_css = [h for h in p.links if h and not h.startswith(("http:", "https:", "//", "data:"))]
    linked_js = [s for s in p.scripts if s and not s.startswith(("http:", "https:", "//", "data:"))]
    css_parts: list[str] = []
    for href in linked_css:
        path = (entry.parent / urlsplit(href).path).resolve()
        if path.is_file():
            css_parts.append(path.read_text(errors="replace"))
    css_parts.extend(p.style_blocks)
    css = "\n".join(css_parts)
    js_parts: list[str] = []
    for src in linked_js:
        path = (entry.parent / urlsplit(src).path).resolve()
        if path.is_file():
            js_parts.append(path.read_text(errors="replace"))
    js_parts.extend(p.scripts_inline)
    js = "\n".join(js_parts)
    blob = (text + "\n" + css + "\n" + js).lower()
    feats: list[str] = []

    def has(*needles):
        return any(n in blob for n in needles)

    if has("display:flex", "display: flex", "flex-direction", "flex-grow", "flex:"):
        feats.append("flex")
    if has("display:grid", "display: grid", "grid-template"):
        feats.append("grid")
    if has("position:absolute", "position: absolute", "position:fixed",
           "position: fixed", "position:sticky", "position: sticky", "float:"):
        feats.append("position")
    if has("transform", "@keyframes", "animation:", "transition:"):
        feats.append("anim")
    if has("@media"):
        feats.append("responsive")
    if p.form_tags:
        feats.append("forms")
    if p.roles or p.aria:
        feats.append("a11y")
    if p.media_tags:
        feats.append("media")
    if has("font-size", "font-family", "line-height", "text-align",
           "letter-spacing"):
        feats.append("typo")
    if has("background", "color:", "gradient"):
        feats.append("color")
    if has("padding", "margin", "border", "width:", "height:"):
        feats.append("box")
    if has("addeventlistener", "queryselector", "getelementbyid", "onclick"):
        feats.append("jsdom")
    if has("click", "pointer", "keydown", "submit"):
        feats.append("events")

    text_samples = []
    for raw in p.text_nodes:
        sample = _norm(raw)
        if len(sample) >= 12 and re.search(r"[A-Za-z0-9\u00c0-\u024f]", sample):
            if sample not in text_samples:
                text_samples.append(sample[:120])
        if len(text_samples) >= 8:
            break
    ids = [k for k in p.ids if re.fullmatch(r"[A-Za-z][\w-]{0,63}", k)]
    classes = [k for k in p.classes if re.fullmatch(r"[A-Za-z_][\w-]{0,63}", k)]
    return {
        "title": _norm(p.title)[:160],
        "elements": p.elements,
        "max_depth": p.max_depth,
        "tags": dict(p.tags),
        "html_tags": sorted(t for t in p.tags if t in HTML_TAGS),
        "ids": ids[:40],
        "id_counts": {k: p.ids[k] for k in ids[:40]},
        "classes": classes[:60],
        "class_counts": {k: p.classes[k] for k in classes[:60]},
        "text_samples": text_samples,
        "inline_styles": p.inline_styles[:12],
        "attr_samples": {k: v for k, v in list(p.attrs_by_id.items())[:40]
                         if re.fullmatch(r"[A-Za-z][\w-]{0,63}", k)},
        "roles": dict(p.roles),
        "aria": dict(p.aria),
        "forms": dict(p.form_tags),
        "media": dict(p.media_tags),
        "linked_css": linked_css[:32],
        "linked_js": linked_js[:32],
        "style_blocks": len(p.style_blocks),
        "inline_js": len(p.scripts_inline),
        "images": p.images[:40],
        "features": feats,
        "css": _css_facts(css),
        "js_bytes": len(js.encode("utf-8", "replace")),
        "html_bytes": len(text.encode("utf-8", "replace")),
    }


# ---------------------------------------------------------------------------
# selection / scoring
# ---------------------------------------------------------------------------

def section_score(facts: dict, section: int) -> float:
    f = set(facts["features"])
    css = facts["css"]
    if section == 1:
        return (len(facts["html_tags"]) * 2.0 + min(len(facts["ids"]), 12)
                + min(len(facts["classes"]), 30) * 0.3
                + min(facts["elements"], 300) / 25.0)
    if section == 2:
        return min(css["rules"], 120) / 2.0 + min(len(css["selectors"]), 40) / 4.0
    if section == 3:
        return (12 if "box" in f else 0) + min(facts["elements"], 200) / 20.0
    if section == 4:
        return 18 if "typo" in f else 0
    if section == 5:
        return 18 if "color" in f else 0
    if section == 6:
        return (18 if "anim" in f else 0) + min(css["keyframes"], 10)
    if section == 7:
        return (20 if "responsive" in f else 0) + css["media"] * 2.0
    if section == 8:
        return 22 if "flex" in f else 0
    if section == 9:
        return 18 if "position" in f else 0
    if section == 10:
        return (16 if "jsdom" in f else 0) + min(facts["js_bytes"], 30_000) / 10_000.0
    if section == 11:
        return (18 if "events" in f else 0) + min(facts["js_bytes"], 20_000) / 10_000.0
    if section == 12:
        return sum(facts["forms"].values()) * 2.0
    if section == 13:
        return (12 if "a11y" in f else 0) + (len(facts["roles"]) + len(facts["aria"])) * 3.0
    if section == 14:
        return (12 if "media" in f else 0) + sum(facts["media"].values()) * 2.0
    if section == 15:
        return (min(facts["elements"], 800) / 8.0
                + min(css["rules"], 400) / 10.0
                + min(facts["html_bytes"], 200_000) / 2_000.0)
    if section == 16:
        return len(f) * 3.0 + (8 if css["rules"] else 0) + (4 if facts["linked_js"] else 0)
    return 0.0


def quality(facts: dict) -> float:
    return (len(facts["features"]) * 3.0
            + (6 if facts["css"]["rules"] else 0)
            + (4 if facts["linked_css"] else 0)
            + (4 if facts["linked_js"] else 0)
            + min(facts["elements"], 300) / 20.0
            + min(facts["css"]["rules"], 200) / 20.0)


def _is_code_asset(path: str) -> bool:
    lower = path.lower()
    if lower.endswith((".css", ".js", ".mjs")):
        return True
    return "/js/" in lower or "/css/" in lower or "/scripts/" in lower


def candidate_entries(src: dict, root: Path) -> list[dict]:
    out = []
    roots = src["roots"]
    for wanted in roots:
        base = root / wanted if wanted else root
        if not base.exists():
            continue
        for entry in base.rglob("index.html"):
            rel = entry.parent.relative_to(root)
            if rel == Path("."):
                continue
            if any(part in (".git", "node_modules", "__pycache__", ".github")
                   for part in rel.parts):
                continue
            # Keep the corpus to examples, not vendored demos inside templates.
            if any(part in ("bower_components", "vendor", "documentation",
                            "docs", "node_modules", "examples", "demo")
                   for part in rel.parts):
                continue
            if src["repo"].startswith("learning-zone") and len(rel.parts) != 1:
                continue
            if src["repo"].startswith("zxuqian") and len(rel.parts) != 1:
                continue
            if src["repo"].startswith("keshav") and (
                    len(rel.parts) < 2 or len(rel.parts) > 3):
                continue
            if entry.stat().st_size > 1_500_000:
                continue
            size = 0
            for path in entry.parent.rglob("*"):
                if path.is_file() and not path.is_symlink():
                    size += path.stat().st_size
            if size > src["max_bytes"]:
                continue
            files, missing, escaped, has_base = discover_refs(entry)
            if escaped or has_base:
                continue
            # Upstream repositories sometimes omit decorative fonts/images.
            # Those are recorded, but a missing style sheet or script would
            # change behaviour, so such examples are rejected.
            code_missing = [m for m in missing if _is_code_asset(m)]
            if code_missing:
                continue
            try:
                facts = analyze_case(entry)
            except Exception:
                continue
            if facts["elements"] < 6 or facts["html_bytes"] < 200:
                continue
            facts["missing_assets"] = missing[:40]
            out.append({
                "source": src,
                "root": root,
                "src_dir": entry.parent,
                "rel": str(rel).replace(os_sep, "/"),
                "size": size,
                "files": len(files),
                "facts": facts,
            })
    # Deduplicate identical directories reached through overlapping roots.
    seen: set[Path] = set()
    unique = []
    for c in out:
        key = c["src_dir"].resolve()
        if key in seen:
            continue
        seen.add(key)
        unique.append(c)
    unique.sort(key=lambda c: (-quality(c["facts"]), c["rel"]))
    return unique


os_sep = "\\"


def choose_candidates(sources: dict[str, Path]) -> list[dict]:
    chosen: list[dict] = []
    for name, src in SOURCES.items():
        root = sources[name]
        rows = candidate_entries(src, root)
        limit = src["limit"]
        # Diversity pass: prefer a spread of primary features before filling.
        buckets: dict[str, list[dict]] = {}
        for row in rows:
            primary = _primary_feature(row["facts"])
            buckets.setdefault(primary, []).append(row)
        picked: list[dict] = []
        order = ["integ", "forms", "flex", "anim", "position", "responsive",
                 "jsdom", "events", "a11y", "media", "grid", "typo", "color",
                 "box", "plain"]
        while len(picked) < limit and any(buckets.get(k) for k in order):
            for key in order:
                if len(picked) >= limit:
                    break
                if buckets.get(key):
                    picked.append(buckets[key].pop(0))
        if len(picked) < limit:
            seen = {id(c) for c in picked}
            for row in rows:
                if id(row) not in seen:
                    picked.append(row)
                    if len(picked) >= limit:
                        break
        chosen.extend(picked[:limit])
    return chosen


def _primary_feature(facts: dict) -> str:
    f = set(facts["features"])
    for name in ("forms", "flex", "anim", "position", "responsive", "jsdom",
                 "events", "a11y", "media", "grid", "typo", "color", "box"):
        if name in f:
            return name
    return "plain"


def assign_sections(candidates: list[dict]) -> dict[int, list[dict]]:
    """Give every section its own examples, best fit first.

    Sections are filled in order so later feature-specific sections (a11y,
    media) are not starved by the broad integration bucket. Within a section
    the strongest examples for that capability win.
    """
    remaining = sorted(candidates, key=lambda c: c["rel"])
    by_section: dict[int, list[dict]] = {}
    fill_order = (15, 13, 14, 16, 1, 2, 10, 11, 8, 7, 6, 5, 4, 3, 9, 12)
    for section in fill_order:
        ranked = sorted(
            remaining,
            key=lambda c: (-section_score(c["facts"], section), c["rel"]))
        positive = [c for c in ranked if section_score(c["facts"], section) > 0]
        picked = positive[:PER_SECTION]
        if len(picked) < PER_SECTION:
            for cand in ranked:
                if cand not in picked:
                    picked.append(cand)
                if len(picked) >= PER_SECTION:
                    break
        by_section[section] = picked
        chosen = {id(c) for c in picked}
        remaining = [c for c in remaining if id(c) not in chosen]
    return by_section


# ---------------------------------------------------------------------------
# writing
# ---------------------------------------------------------------------------

def _ignore(_dir, names):
    return [n for n in names if n in (".git", "node_modules", "__pycache__",
                                      ".DS_Store")]


def _dir_digest(path: Path) -> str:
    h = hashlib.sha1()
    for p in sorted(path.rglob("*")):
        if p.is_file() and not p.is_symlink():
            h.update(str(p.relative_to(path)).encode())
            h.update(b"\0")
            h.update(p.read_bytes())
    return h.hexdigest()[:20]


def write_corpus(sources: dict[str, Path], *, force: bool = False,
                 check: bool = False) -> dict:
    candidates = choose_candidates(sources)
    by_section = assign_sections(candidates)
    total = sum(len(v) for v in by_section.values())
    if total < len(SECTION_PREFIX) * PER_SECTION:
        print(f"warning: only {total} self-contained examples available; "
              f"wanted {len(SECTION_PREFIX) * PER_SECTION}", file=sys.stderr)
    if check:
        print(f"candidates: {len(candidates)}; selected: {total}")
        for n in SECTION_PREFIX:
            rows = by_section[n]
            print(f"s{n:02d} {SECTION_PREFIX[n]:6s} {len(rows):2d}  " +
                  ", ".join(r["rel"] for r in rows[:4]))
        return {"candidates": len(candidates), "selected": total}

    manifest = {
        "version": 1,
        "generated_by": "debug/tools/import_real_examples.py",
        "sources": {
            name: {
                "repo": src["repo"],
                "commit": src["commit"],
                "license": src["license"],
            } for name, src in SOURCES.items()
        },
        "cases": [],
    }
    if CASES.exists():
        if not force:
            raise SystemExit(f"{CASES} already exists; pass --force to replace it")
        shutil.rmtree(CASES)
    CASES.mkdir(parents=True)

    attribution: list[str] = [
        "# Imported example attribution",
        "",
        "These examples are kept verbatim for laboratory debugging. They are",
        "not built, rewritten or wrapped by NativaX. Each case records its",
        "source repository, commit and original path in `case.json`.",
        "",
    ]
    for section in sorted(by_section):
        prefix = SECTION_PREFIX[section]
        section_dir = CASES / f"s{section:02d}"
        section_dir.mkdir(parents=True)
        for index, cand in enumerate(by_section[section], start=1):
            cid = f"{prefix}.{index:03d}"
            dest = section_dir / f"{index:03d}"
            shutil.copytree(cand["src_dir"], dest, ignore=_ignore,
                            symlinks=False)
            src = cand["source"]
            facts = dict(cand["facts"])
            case = {
                "id": cid,
                "section": section,
                "name": f"{src['repo']} · {cand['rel']}",
                "source": {
                    "repo": src["repo"],
                    "commit": src["commit"],
                    "license": src["license"],
                    "path": cand["rel"],
                    "url": f"https://github.com/{src['repo']}/tree/{src['commit']}/{cand['rel']}",
                },
                "entry": "index.html",
                "dir": f"cases/s{section:02d}/{index:03d}",
                "bytes": cand["size"],
                "files": cand["files"],
                "digest": _dir_digest(dest),
                "facts": facts,
            }
            (dest / "case.json").write_text(
                json.dumps(case, indent=1, ensure_ascii=False) + "\n")
            manifest["cases"].append(case)
            attribution.append(
                f"- `{cid}` — [{src['repo']}/{cand['rel']}]"
                f"(https://github.com/{src['repo']}/tree/{src['commit']}/{cand['rel']})"
                f" — {src['license']}")

    MANIFEST.write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    ATTRIBUTION.write_text("\n".join(attribution) + "\n")
    print(f"wrote {len(manifest['cases'])} cases to {CASES.relative_to(LAB.parent.parent)}")
    print(f"manifest: {MANIFEST.relative_to(LAB.parent.parent)}")
    return manifest


def clone_sources(sources: dict[str, Path]) -> dict[str, Path]:
    out = {}
    for name, src in SOURCES.items():
        root = sources.get(name, src["default"])
        if root.exists() and (root / ".git").exists():
            out[name] = root
            continue
        root.parent.mkdir(parents=True, exist_ok=True)
        print(f"cloning {src['repo']} at {src['commit'][:12]} ...", flush=True)
        subprocess.run(["git", "clone", "--quiet", src["url"], str(root)], check=True)
        subprocess.run(["git", "-C", str(root), "checkout", "--quiet",
                        src["commit"]], check=True)
        out[name] = root
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", action="append", default=[],
                    metavar="NAME=PATH", help="override a source checkout path")
    ap.add_argument("--clone", action="store_true",
                    help="clone missing sources at the pinned commits")
    ap.add_argument("--force", action="store_true", help="replace the case tree")
    ap.add_argument("--check", action="store_true", help="report selection only")
    args = ap.parse_args()
    overrides = {}
    for item in args.source:
        if "=" not in item:
            ap.error(f"--source expects NAME=PATH, got {item!r}")
        name, path = item.split("=", 1)
        if name not in SOURCES:
            ap.error(f"unknown source {name!r}; choose from {sorted(SOURCES)}")
        overrides[name] = Path(path).expanduser().resolve()
    sources = {name: overrides.get(name, src["default"]) for name, src in SOURCES.items()}
    missing = [name for name, path in sources.items() if not path.exists()]
    if missing and args.clone:
        sources = clone_sources(sources)
        missing = [name for name, path in sources.items() if not path.exists()]
    if missing:
        print("missing source checkouts:", ", ".join(missing), file=sys.stderr)
        print("pass --source NAME=PATH or --clone", file=sys.stderr)
        return 2
    write_corpus(sources, force=args.force, check=args.check)
    return 0


if __name__ == "__main__":
    sys.exit(main())

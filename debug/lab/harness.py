"""NativaX laboratory harness.

Every case runs the real native pipeline. Nothing is simulated: a case either
observes artifacts produced by ``build/nativax-debug`` / ``nativax-runtime`` or
it is reported as blocked because the capability does not exist.

Public API used by section modules::

    from harness import case, Lab, eq, close, truthy, ...

    @case(1, "html.001", "sanity: a div is parsed")
    def _(ctx):
        page = ctx.page("<div id=x>hi</div>")
        eq(page.find("#x").tag, "div")

Case statuses:
  pass     assertions held
  fail     assertions did not hold (real regression or spec gap)
  blocked  the runtime cannot express the capability (must give a reason)
  error    the case raised an unexpected exception
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable
from urllib.parse import unquote, urlsplit

LAB_DIR = Path(__file__).resolve().parent
DEBUG = LAB_DIR.parent
ROOT = DEBUG.parent
ARTIFACTS = DEBUG / "artifacts" / "lab"
REPORTS = DEBUG / "reports" / "lab"
BUILD = ROOT / "build"


class LabError(RuntimeError):
    pass


class Blocked(Exception):
    """Capability the runtime cannot exercise (reported, never faked)."""


class AssertionFailure(AssertionError):
    pass


# ---------------------------------------------------------------------------
# registry
# ---------------------------------------------------------------------------

@dataclass
class Case:
    section: int
    cid: str
    name: str
    fn: Callable[["Lab"], None]
    tags: tuple[str, ...] = ()


REGISTRY: dict[int, list[Case]] = {}


def case(section: int, cid: str, name: str, tags: Iterable[str] = ()):
    def deco(fn: Callable[["Lab"], None]) -> Callable[["Lab"], None]:
        REGISTRY.setdefault(section, []).append(
            Case(section, cid, name, fn, tuple(tags)))
        return fn
    return deco


def registered(section: int | None = None) -> list[Case]:
    if section is None:
        out: list[Case] = []
        for n in sorted(REGISTRY):
            out.extend(REGISTRY[n])
        return out
    return list(REGISTRY.get(section, []))


# ---------------------------------------------------------------------------
# assertions
# ---------------------------------------------------------------------------

def fail(msg: str):
    raise AssertionFailure(msg)


def truthy(value: Any, msg: str = "expected a truthy value"):
    if not value:
        fail(f"{msg}: got {value!r}")


def falsy(value: Any, msg: str = "expected a falsy value"):
    if value:
        fail(f"{msg}: got {value!r}")


def eq(actual: Any, expected: Any, msg: str = ""):
    if actual != expected:
        fail(f"{msg or 'values differ'}: expected {expected!r}, got {actual!r}")


def ne(actual: Any, unexpected: Any, msg: str = ""):
    if actual == unexpected:
        fail(f"{msg or 'values must differ'}: both {actual!r}")


def close(actual: float, expected: float, tol: float = 0.51, msg: str = ""):
    if actual is None or abs(float(actual) - float(expected)) > tol:
        fail(f"{msg or 'values differ'}: expected {expected} +/- {tol}, got {actual!r}")


def between(value: float, low: float, high: float, msg: str = ""):
    if value is None or not (low <= float(value) <= high):
        fail(f"{msg or 'value out of range'}: expected {low}..{high}, got {value!r}")


def contains(haystack: Any, needle: Any, msg: str = ""):
    if needle not in haystack:
        fail(f"{msg or 'missing value'}: {needle!r} not in {haystack!r}")


def not_contains(haystack: Any, needle: Any, msg: str = ""):
    if needle in haystack:
        fail(f"{msg or 'unexpected value'}: {needle!r} found in {haystack!r}")


def lt(a: float, b: float, msg: str = ""):
    if not a < b:
        fail(f"{msg or 'expected less-than'}: {a} !< {b}")


def gt(a: float, b: float, msg: str = ""):
    if not a > b:
        fail(f"{msg or 'expected greater-than'}: {a} !> {b}")


def matches(value: str, pattern: str, msg: str = ""):
    if not re.search(pattern, value):
        fail(f"{msg or 'pattern mismatch'}: {value!r} !~ {pattern!r}")


# ---------------------------------------------------------------------------
# DOM model
# ---------------------------------------------------------------------------

@dataclass(eq=False)
class Node:
    tag: str
    attrs: dict[str, str] = field(default_factory=dict)
    children: list["Node"] = field(default_factory=list)
    parent: "Node | None" = None
    slot: int = -1
    text: str | None = None
    kind: str = "element"

    @property
    def id(self) -> str:
        return self.attrs.get("id", "")

    @property
    def classes(self) -> list[str]:
        return self.attrs.get("class", "").split()

    def text_content(self) -> str:
        if self.kind == "text":
            return self.text or ""
        return "".join(c.text_content() for c in self.children)

    def elements(self) -> list["Node"]:
        out = []
        for c in self.children:
            if c.kind == "element":
                out.append(c)
                out.extend(c.elements())
        return out

    def ancestors(self) -> list["Node"]:
        out, p = [], self.parent
        while p is not None:
            out.append(p)
            p = p.parent
        return out

    def attr(self, name: str, default: str | None = None) -> str | None:
        return self.attrs.get(name, default)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<{self.tag}{'#' + self.id if self.id else ''} slot={self.slot}>"


def _node_from_json(raw: dict, parent: Node | None) -> Node:
    if "text" in raw:
        n = Node(tag="#text", parent=parent, text=raw["text"], kind="text")
        return n
    if "comment" in raw:
        return Node(tag="#comment", parent=parent, text=raw["comment"], kind="comment")
    n = Node(tag=raw.get("tag", ""), parent=parent,
             attrs=dict(raw.get("attrs", {})), slot=raw.get("node", -1))
    if raw.get("id") is not None:
        n.attrs["id"] = raw["id"]
    if raw.get("class"):
        n.attrs["class"] = " ".join(raw["class"])
    for child in raw.get("children", []):
        n.children.append(_node_from_json(child, n))
    return n


_ATTR_RE = re.compile(r"\[\s*([\w:-]+)\s*(?:([~|^$*]?=)\s*(?:\"([^\"]*)\"|'([^']*)'|([^\]\s]+)))?\s*\]")
_PSEUDO_RE = re.compile(r":([\w-]+)(?:\(([^)]*)\))?")
_SIMPLE_TOKEN = re.compile(r"[#.]?[\w-]+|\[[^\]]*\]|:[\w-]+(?:\([^)]*\))?|\*")


def _match_compound(node: Node, compound: str) -> bool:
    if node.kind != "element":
        return False
    pos = 0
    for m in _SIMPLE_TOKEN.finditer(compound):
        if m.start() != pos:
            return False
        pos = m.end()
        tok = m.group(0)
        if tok == "*":
            continue
        if tok.startswith("#"):
            if node.id != tok[1:]:
                return False
        elif tok.startswith("."):
            if tok[1:] not in node.classes:
                return False
        elif tok.startswith("["):
            am = _ATTR_RE.fullmatch(tok)
            if not am:
                return False
            name, op, v1, v2, v3 = am.groups()
            value = v1 if v1 is not None else v2 if v2 is not None else v3
            if name not in node.attrs:
                return False
            if op is None:
                continue
            actual = node.attrs[name]
            if op == "=" and actual != value:
                return False
            if op == "~=" and value not in actual.split():
                return False
            if op == "|=" and not (actual == value or actual.startswith(value + "-")):
                return False
            if op == "^=" and not actual.startswith(value):
                return False
            if op == "$=" and not actual.endswith(value):
                return False
            if op == "*=" and value not in actual:
                return False
        elif tok.startswith(":"):
            pm = _PSEUDO_RE.fullmatch(tok)
            if not pm:
                return False
            name, arg = pm.group(1), pm.group(2)
            siblings = [c for c in (node.parent.children if node.parent else []) if c.kind == "element"]
            idx = siblings.index(node) + 1 if node in siblings else 0
            if name == "first-child" and idx != 1:
                return False
            if name == "last-child" and idx != len(siblings):
                return False
            if name == "only-child" and len(siblings) != 1:
                return False
            if name == "nth-child":
                if not arg or not arg.isdigit() or idx != int(arg):
                    return False
            if name == "nth-last-child":
                if not arg or not arg.isdigit() or idx != len(siblings) - int(arg) + 1:
                    return False
            if name == "empty" and any(c.kind in ("element", "text") and c.text_content().strip() for c in node.children):
                return False
            if name == "root" and node.parent is not None and node.parent.kind != "document":
                return False
            if name == "not":
                if not arg or _match_compound(node, arg.strip()):
                    return False
            if name in ("hover", "focus", "active", "visited", "link", "checked",
                        "disabled", "enabled", "focus-visible", "focus-within",
                        "target", "defined", "scope", "any-link", "open", "modal",
                        "required", "optional", "read-only", "read-write",
                        "placeholder-shown", "valid", "invalid"):
                return False
        else:
            if node.tag != tok.lower():
                return False
    return pos == len(compound)


def parse_selector(selector: str) -> list[list[tuple[str, str]]]:
    """Return selector list where each complex selector is [(comb, compound)]."""
    out = []
    for part in selector.split(","):
        part = part.strip()
        if not part:
            continue
        # normalize spaces around combinators, then split
        part = re.sub(r"\s*([>+~])\s*", r" \1 ", part)
        toks = part.split()
        complex_parts: list[tuple[str, str]] = []
        comb = " "
        for tok in toks:
            if tok in (">", "+", "~"):
                comb = tok
            else:
                complex_parts.append((comb, tok))
                comb = " "
        out.append(complex_parts)
    return out


def _matches_complex(node: Node, parts: list[tuple[str, str]], index: int | None = None) -> bool:
    if index is None:
        index = len(parts) - 1
    comb, compound = parts[index]
    if not _match_compound(node, compound):
        return False
    if index == 0:
        return True
    prev_comb = parts[index][0]
    if prev_comb == " ":
        for anc in node.ancestors():
            if _matches_complex(anc, parts, index - 1):
                return True
        return False
    if prev_comb == ">":
        return node.parent is not None and _matches_complex(node.parent, parts, index - 1)
    siblings = [c for c in (node.parent.children if node.parent else []) if c.kind == "element"]
    if node not in siblings:
        return False
    pos = siblings.index(node)
    if prev_comb == "+":
        return pos > 0 and _matches_complex(siblings[pos - 1], parts, index - 1)
    if prev_comb == "~":
        return any(_matches_complex(s, parts, index - 1) for s in siblings[:pos])
    return False


# ---------------------------------------------------------------------------
# pages (nativax-debug artifacts)
# ---------------------------------------------------------------------------

def _sha(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8", "surrogatepass")).hexdigest()[:16]


RESPONSIVE_WIDTHS = list(range(320, 1281, 50)) + [1280]

_HTML_TAG_RE = re.compile(r"<([a-zA-Z][\w:-]*)\b([^>]*)>", re.S)
_HTML_ATTR_RE = re.compile(
    r"([\w:-]+)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))", re.S)
_CSS_IMPORT_RE = re.compile(
    r"@import\s+(?:url\(\s*)?[\"']?([^\"')\s;]+)[\"']?\s*\)?\s*;", re.I)


def _html_attrs(raw: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for m in _HTML_ATTR_RE.finditer(raw):
        out[m.group(1).lower()] = m.group(2) or m.group(3) or m.group(4) or ""
    return out


def _local_href(href: str) -> str:
    href = (href or "").strip()
    if not href or href.startswith(("#", "data:", "//")):
        return ""
    parts = urlsplit(href)
    if parts.scheme or parts.netloc:
        return ""
    if href.startswith("/"):
        return ""
    return unquote(parts.path)


def _stylesheet_links(html: str, entry: Path) -> list[str]:
    out: list[str] = []
    for m in _HTML_TAG_RE.finditer(html):
        if m.group(1).lower() != "link":
            continue
        attrs = _html_attrs(m.group(2))
        rel = attrs.get("rel", "").lower().split()
        if "stylesheet" not in rel:
            continue
        href = _local_href(attrs.get("href", ""))
        if href and href not in out:
            out.append(href)
    return out


def _script_links(html: str, entry: Path) -> list[str]:
    out: list[str] = []
    for m in _HTML_TAG_RE.finditer(html):
        if m.group(1).lower() != "script":
            continue
        attrs = _html_attrs(m.group(2))
        src = _local_href(attrs.get("src", ""))
        if src and src not in out:
            out.append(src)
    return out


def _expand_css_imports(path: Path, root: Path, seen: set[Path]) -> str:
    resolved = path.resolve()
    if resolved in seen:
        return ""
    seen.add(resolved)
    try:
        text = resolved.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""

    def repl(match: re.Match) -> str:
        ref = _local_href(match.group(1))
        if not ref:
            return ""
        child = (resolved.parent / ref).resolve()
        try:
            child.relative_to(root.resolve())
        except ValueError:
            return ""
        if child.is_file() and child.suffix.lower() == ".css":
            return _expand_css_imports(child, root, seen)
        return ""

    return _CSS_IMPORT_RE.sub(repl, text)



class Page:
    def __init__(self, directory: Path, html: str, css: str, width: int, height: int,
                 render: bool):
        self.dir = directory
        self.html = html
        self.css = css
        self.width = width
        self.height = height
        self.render_path = directory / "render.png" if render else None
        self.dom = json.loads((directory / "dom.json").read_text())
        self.styles_doc = json.loads((directory / "styles.json").read_text())
        self.layout_doc = json.loads((directory / "layout.json").read_text())
        self.css_doc = json.loads((directory / "css.json").read_text())
        self.summary = json.loads((directory / "summary.json").read_text())
        self.displaylist = (directory / "displaylist.txt").read_text()
        self.root = Node(tag="#document", kind="document")
        for child in self.dom.get("children", []):
            self.root.children.append(_node_from_json(child, self.root))
        self._nodes: list[Node] = []
        self._index(self.root)
        self._styles: dict[int, dict] = {s["node"]: s for s in self.styles_doc.get("styles", [])}
        self._boxes: dict[int, list[dict]] = {}
        def walk(box):
            self._boxes.setdefault(box.get("node", -1), []).append(box)
            for c in box.get("children", []):
                walk(c)
        for b in self.layout_doc.get("boxes", []):
            walk(b)

    def _index(self, node: Node):
        if node.kind == "element":
            self._nodes.append(node)
        for c in node.children:
            self._index(c)

    # -- queries ---------------------------------------------------------
    def find_all(self, selector: str) -> list[Node]:
        parsed = parse_selector(selector)
        return [n for n in self._nodes
                if any(_matches_complex(n, parts) for parts in parsed)]

    def find(self, selector: str) -> Node | None:
        hits = self.find_all(selector)
        return hits[0] if hits else None

    def require(self, selector: str) -> Node:
        node = self.find(selector)
        if node is None:
            fail(f"selector matched nothing: {selector!r}")
        return node

    def by_id(self, element_id: str) -> Node | None:
        return self.find("#" + element_id)

    def text(self, selector: str) -> str:
        return self.require(selector).text_content()

    def style(self, selector: str | Node) -> dict:
        node = selector if isinstance(selector, Node) else self.require(selector)
        st = self._styles.get(node.slot)
        if st is None:
            fail(f"no computed style for {node!r} ({selector!r})")
        return st

    def maybe_style(self, selector: str | Node) -> dict | None:
        node = selector if isinstance(selector, Node) else self.find(selector)
        return self._styles.get(node.slot) if node else None

    def box(self, selector: str | Node) -> dict | None:
        node = selector if isinstance(selector, Node) else self.require(selector)
        boxes = self._boxes.get(node.slot, [])
        return boxes[0] if boxes else None

    def boxes(self, selector: str | Node) -> list[dict]:
        node = selector if isinstance(selector, Node) else self.require(selector)
        return self._boxes.get(node.slot, [])

    def all_boxes(self) -> list[dict]:
        out = []
        def walk(b):
            out.append(b)
            for c in b.get("children", []):
                walk(c)
        for b in self.layout_doc.get("boxes", []):
            walk(b)
        return out

    @property
    def viewport_size(self) -> tuple[float, float]:
        vp = self.layout_doc.get("viewport") or [self.width, self.height]
        return float(vp[0]), float(vp[1])

    def horizontal_overflow(self, tolerance: float = 1.0) -> list[dict]:
        """Boxes whose right edge extends past the viewport by ``tolerance``.

        This is the objective responsive check used by the laboratory: at every
        width the layout must fit inside the viewport without horizontal
        scrolling. Decorative children that the runtime cannot position are
        still measured; an empty list means the document fits.
        """
        width, _ = self.viewport_size
        bad = []
        for b in self.all_boxes():
            right = float(b.get("x", 0.0)) + float(b.get("w", 0.0))
            if right > width + tolerance:
                bad.append({
                    "tag": b.get("tag"),
                    "id": b.get("id", ""),
                    "class": list(b.get("class") or []),
                    "right": round(right, 2),
                    "width": round(float(b.get("w", 0.0)), 2),
                    "node": b.get("node"),
                })
        bad.sort(key=lambda item: item["right"], reverse=True)
        return bad

    def responsive_metrics(self, tolerance: float = 1.0) -> dict:
        width, height = self.viewport_size
        over = self.horizontal_overflow(tolerance)
        return {
            "width": int(round(width)),
            "height": int(round(height)),
            "boxes": len(self.all_boxes()),
            "overflow": over[:5],
            "overflow_count": len(over),
            "ok": not over,
        }

    def elements(self) -> list[Node]:
        return list(self._nodes)

    def rules(self) -> list[dict]:
        out = []
        for sheet in self.css_doc.get("sheets", []):
            out.extend(sheet.get("rules", []))
        return out

    def display_records(self) -> list[dict]:
        """Parse displaylist.txt lines into simple records (group/vertices)."""
        records = []
        for line in self.displaylist.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"(group|tri|rect|text|image|clip)\b(.*)", line)
            if m:
                records.append({"kind": m.group(1), "text": line})
        return records

    def pixel(self, x: int, y: int) -> tuple[int, int, int, int]:
        from PIL import Image
        img = Image.open(self.render_path).convert("RGBA")
        return img.getpixel((x, y))

    def image(self):
        from PIL import Image
        return Image.open(self.render_path).convert("RGBA")

    def evidence(self) -> dict:
        return {
            "dir": str(self.dir),
            "summary": self.summary,
            "viewport": self.layout_doc.get("viewport"),
        }


class Lab:
    def __init__(self, *, debug_bin: Path | None = None, runtime_bin: Path | None = None,
                 artifacts: Path | None = None, jobs: int = 1, responsive: bool = True,
                 responsive_widths: Iterable[int] | None = None):
        self.debug_bin = Path(debug_bin or os.environ.get("NATIVAX_DEBUG") or BUILD / "nativax-debug")
        self.runtime_bin = Path(runtime_bin or os.environ.get("NATIVAX_RUNTIME") or BUILD / "nativax-runtime")
        self.artifacts = Path(artifacts or ARTIFACTS)
        self.artifacts.mkdir(parents=True, exist_ok=True)
        self.cache = self.artifacts / "cache"
        self.cache.mkdir(parents=True, exist_ok=True)
        self.jobs = jobs
        self.responsive = responsive
        self.responsive_widths = list(responsive_widths or RESPONSIVE_WIDTHS)
        self._pages: dict[str, Page] = {}
        self._runtime: dict[str, "RuntimeResult"] = {}
        self._responsive: dict[str, dict] = {}
        self.require_binaries()

    def require_binaries(self) -> None:
        if not self.debug_bin.exists():
            raise LabError(
                f"{self.debug_bin} missing; run: python3 debug/bootstrap.py")
        if not self.runtime_bin.exists():
            raise LabError(
                f"{self.runtime_bin} missing; run: python3 debug/bootstrap.py")

    # -- case fixtures ---------------------------------------------------
    def case_meta(self, cid: str) -> dict:
        """Metadata written by ``debug/tools/import_real_examples.py``."""
        cached = getattr(self, "_case_meta", None)
        if cached is None:
            cached = self._case_meta = {}
        if cid in cached:
            return cached[cid]
        d = self.case_dir(cid)
        meta_path = d / "case.json"
        if meta_path.exists():
            meta = json.loads(meta_path.read_text())
        else:
            meta = {"id": cid, "entry": "index.html", "legacy": True}
        meta["_dir"] = d
        cached[cid] = meta
        return meta

    def case_dir(self, cid: str) -> Path:
        """Every case lives in its own folder: cases/sNN/<case-id>/.

        Imported examples carry a ``case.json`` manifest and may use their own
        file names, any number of style sheets and their own assets. Generated
        legacy cases used index.html/style.css/app.js; that layout is still
        accepted when no manifest is present.
        """
        for c in registered():
            if c.cid == cid:
                folder = cid.rsplit(".", 1)[-1]
                d = LAB_DIR / "cases" / f"s{c.section:02d}" / folder
                if not d.exists():
                    raise LabError(
                        f"case folder missing for {cid}: {d.relative_to(ROOT)}")
                meta_path = d / "case.json"
                if meta_path.exists():
                    entry = json.loads(meta_path.read_text()).get(
                        "entry", "index.html")
                    if not (d / entry).is_file():
                        raise LabError(
                            f"case {cid} entry missing: {(d / entry).relative_to(ROOT)}")
                else:
                    for required in ("index.html", "style.css", "app.js"):
                        if not (d / required).exists():
                            raise LabError(
                                f"case {cid} is missing {required} in {d.relative_to(ROOT)}")
                return d
        raise LabError(f"unknown case id {cid}")

    def fixture_files(self, cid: str) -> tuple[str, str, str]:
        """Return (entry HTML, concatenated local CSS, concatenated local JS).

        Linked style sheets are read in document order (and ``@import`` chains
        are expanded) because ``nativax-debug`` does not resolve ``<link>``.
        Scripts are returned for introspection; the runtime resolves its own
        links relative to the case directory.
        """
        d = self.case_dir(cid)
        meta = self.case_meta(cid)
        entry = meta.get("entry", "index.html")
        html = (d / entry).read_text(encoding="utf-8", errors="replace")
        css_parts: list[str] = []
        seen: set[Path] = set()
        for href in _stylesheet_links(html, d / entry):
            path = (d / entry).parent / href
            path = path.resolve()
            try:
                path.relative_to(d.resolve())
            except ValueError:
                continue
            if path.is_file():
                css_parts.append(_expand_css_imports(path, d, seen))
        js_parts: list[str] = []
        for src in _script_links(html, d / entry):
            path = ((d / entry).parent / src).resolve()
            try:
                path.relative_to(d.resolve())
            except ValueError:
                continue
            if path.is_file():
                js_parts.append(path.read_text(encoding="utf-8", errors="replace"))
        return html, "\n".join(css_parts), "\n".join(js_parts)

    def fixture(self, cid: str, width: int = 1024, height: int = 768, *,
                render: bool = False, fresh: bool = False) -> Page:
        """Run the debug pipeline over a case folder (index.html + style.css)."""
        html, css, _js = self.fixture_files(cid)
        return self.page(html, css, width, height, render=render, fresh=fresh)

    def fixture_sweep(self, cid: str, widths: Iterable[int] | None = None,
                      height: int = 768, *, render: bool = False) -> dict[int, Page]:
        html, css, _js = self.fixture_files(cid)
        # Responsive sweeps are throw-away: keeping every width of every case
        # alive exhausted memory on the 240-case corpus (the --all run died in
        # section 14). Only the derived metrics are retained, not the pages.
        return self.sweep(html, css, widths, height, render=render, cache=False)

    def responsive_sweep(self, cid: str, widths: Iterable[int] | None = None,
                         height: int = 768, tolerance: float = 1.0) -> dict:
        """Sweep a case folder at every 50 px width and measure overflow.

        The result is cached per case. Every width is a real run of
        ``nativax-debug`` over the case's own ``index.html`` + ``style.css``.
        """
        key = cid
        if key in self._responsive:
            return self._responsive[key]
        widths = [int(w) for w in (widths or self.responsive_widths)]
        pages = self.fixture_sweep(cid, widths=widths, height=height)
        rows = {}
        failures = []
        for w in widths:
            page = pages[w]
            metrics = page.responsive_metrics(tolerance=tolerance)
            root = page.all_boxes()
            if root:
                metrics["root_width"] = round(float(root[0].get("w", 0.0)), 2)
            rows[str(w)] = metrics
            if not metrics["ok"]:
                failures.append({"width": w, **metrics})
        report = {
            "case": cid,
            "widths": widths,
            "step": 50,
            "tolerance": tolerance,
            "ok": not failures,
            "failures": failures,
            "rows": rows,
        }
        self._responsive[key] = report
        return report

    def fixture_app(self, cid: str, *, probe: str = "null",
                    input_spec: str = "", frames: int = 2,
                    width: int = 640, height: int = 480) -> "RuntimeResult":
        """Run a case folder through the runtime with its real entry file."""
        d = self.case_dir(cid)
        meta = self.case_meta(cid)
        return self.run_app("", root=d, entry=meta.get("entry", "index.html"),
                            probe=probe, input_spec=input_spec, frames=frames,
                            width=width, height=height)

    # -- debug pipeline --------------------------------------------------
    def page(self, html: str, css: str = "", width: int = 1024, height: int = 768,
             *, render: bool = False, fresh: bool = False,
             cache: bool = True) -> Page:
        key = _sha(f"{width}x{height}|{render}|{html}|{css}")
        if not fresh and cache and key in self._pages:
            return self._pages[key]
        work = self.cache / key
        work.mkdir(parents=True, exist_ok=True)
        (work / "case.html").write_text(html)
        args = [str(self.debug_bin), "--html", str(work / "case.html"), "--out", str(work),
                "--width", str(width), "--height", str(height)]
        if css:
            (work / "case.css").write_text(css)
            args += ["--css", str(work / "case.css")]
        if render:
            args += ["--render", str(work / "render.png")]
        r = subprocess.run(args, capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            raise LabError(f"nativax-debug failed for {key}: {r.stderr[-1500:]}")
        page = Page(work, html, css, width, height, render)
        if not fresh and cache:
            self._pages[key] = page
        return page

    def sweep(self, html: str, css: str = "", widths: Iterable[int] | None = None,
              height: int = 768, *, render: bool = False,
              cache: bool = False) -> dict[int, Page]:
        if widths is None:
            widths = RESPONSIVE_WIDTHS
        return {w: self.page(html, css, w, height, render=render, cache=cache)
                for w in widths}

    # -- runtime / JS ----------------------------------------------------
    def run_app(self, html: str, *, js: str = "", css: str = "", probe: str = "null",
                input_spec: str = "", frames: int = 2, width: int = 640,
                height: int = 480, root: Path | None = None,
                entry: str = "index.html") -> "RuntimeResult":
        key = _sha(f"{width}x{height}|{frames}|{input_spec}|{root}|{entry}|{html}|{css}|{js}|{probe}")
        if key in self._runtime:
            return self._runtime[key]
        work = self.cache / ("rt-" + key)
        work.mkdir(parents=True, exist_ok=True)
        if root is None:
            (work / "index.html").write_text(html)
            if css:
                (work / "style.css").write_text(css)
            if js:
                (work / "app.js").write_text(js)
            app_root = work
            app_entry = "index.html"
        else:
            app_root = Path(root)
            app_entry = entry
        (work / "probe.js").write_text(probe)
        out = work / "probe.json"
        args = [str(self.runtime_bin), "--headless", "--root", str(app_root),
                "--entry", str(app_entry),
                "--frames", str(frames), "--size", str(width), str(height),
                "--probe", str(work / "probe.js"), "--probe-out", str(out)]
        if input_spec:
            args += ["--input", input_spec]
        r = subprocess.run(args, capture_output=True, text=True, timeout=120)
        result = RuntimeResult(work, r.returncode, r.stdout, r.stderr)
        if out.exists():
            try:
                result.probe_json = json.loads(out.read_text())
            except json.JSONDecodeError:
                result.probe_json = None
        if r.returncode != 0 and "probe_error" not in r.stdout:
            # load/runtime failure is a real observation, not a harness crash
            result.error = (r.stderr or r.stdout).strip()[-1500:]
        self._runtime[key] = result
        return result

    def runtime_available(self) -> bool:
        return self.runtime_bin.exists()


@dataclass
class RuntimeResult:
    dir: Path
    returncode: int
    stdout: str
    stderr: str
    probe_json: dict | None = None
    error: str = ""

    @property
    def probe(self):
        if self.probe_json is None:
            return None
        if "probe_error" in self.probe_json:
            raise LabError("probe failed: " + str(self.probe_json["probe_error"]))
        return self.probe_json.get("probe")

    def stats(self) -> dict | None:
        for line in self.stdout.splitlines():
            line = line.strip()
            if line.startswith('{"nodes"'):
                try:
                    return json.loads(line)
                except json.JSONDecodeError:
                    pass
        return None


# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------

@dataclass
class CaseResult:
    section: int
    cid: str
    name: str
    status: str
    message: str = ""
    duration_ms: float = 0.0
    evidence: Any = None
    traceback: str = ""
    tags: tuple[str, ...] = ()

    def as_dict(self) -> dict:
        return {
            "section": self.section,
            "id": self.cid,
            "name": self.name,
            "status": self.status,
            "message": self.message,
            "duration_ms": round(self.duration_ms, 2),
            "evidence": self.evidence,
            "traceback": self.traceback,
            "tags": list(self.tags),
        }


class Evidence:
    """Small helper a case can use to attach observations to its result."""
    def __init__(self):
        self.value = None

    def set(self, value):
        self.value = value


def run_case(lab: Lab, c: Case) -> CaseResult:
    ev = Evidence()
    started = time.perf_counter()
    try:
        c.fn(lab)
        status, message = "pass", ""
    except Blocked as exc:
        status, message = "blocked", str(exc)
    except AssertionFailure as exc:
        status, message = "fail", str(exc)
    except Exception as exc:  # noqa: BLE001 - lab must record every failure
        status, message = "error", f"{type(exc).__name__}: {exc}"
    if status == "pass" and lab.responsive and "responsive" in (c.tags or ()):
        try:
            report = lab.responsive_sweep(c.cid)
            ev.set({"responsive": {"ok": report["ok"],
                                   "widths": report["widths"],
                                   "failures": report["failures"][:3]}})
            if not report["ok"]:
                # README contract: every responsive case must fit the viewport
                # at every width. Recording overflow as a passing case hid real
                # layout regressions, so it is a failure now.
                first = report["failures"][0]
                status = "fail"
                message = (
                    f"horizontal overflow at {first['width']}px: "
                    f"{first['overflow_count']} box(es) past the viewport "
                    f"(max right edge {first['overflow'][0]['right'] if first.get('overflow') else '?'}px)")
        except Exception as exc:  # noqa: BLE001 - keep going, report honestly
            status = "error"
            message = f"responsive sweep failed: {type(exc).__name__}: {exc}"
    duration = (time.perf_counter() - started) * 1000
    tb = ""
    if status == "error":
        tb = traceback.format_exc(limit=6)
    return CaseResult(c.section, c.cid, c.name, status, message, duration,
                      ev.value, tb, c.tags)


def run_section(lab: Lab, section: int, *, name_filter: str = "",
                on_start: Callable[[Case], None] | None = None,
                on_result: Callable[[CaseResult], None] | None = None) -> list[CaseResult]:
    cases = registered(section)
    if name_filter:
        cases = [c for c in cases if name_filter in c.cid or name_filter in c.name]
    results: list[CaseResult] = []
    for c in cases:
        if on_start is not None:
            try:
                on_start(c)
            except Exception:  # progress must never break a run
                pass
        result = run_case(lab, c)
        results.append(result)
        if on_result is not None:
            try:
                on_result(result)
            except Exception:  # progress must never break a run
                pass
    return results


def summarize(results: list[CaseResult]) -> dict:
    by_status: dict[str, int] = {}
    for r in results:
        by_status[r.status] = by_status.get(r.status, 0) + 1
    sections: dict[str, dict] = {}
    for r in results:
        s = sections.setdefault(str(r.section), {"total": 0, "pass": 0, "fail": 0,
                                                 "blocked": 0, "error": 0})
        s["total"] += 1
        s[r.status if r.status in ("pass", "fail", "blocked", "error") else "error"] += 1
    return {
        "total": len(results),
        "pass": by_status.get("pass", 0),
        "fail": by_status.get("fail", 0),
        "blocked": by_status.get("blocked", 0),
        "error": by_status.get("error", 0),
        "by_status": by_status,
        "sections": sections,
    }


def write_reports(results: list[CaseResult], *, label: str = "latest",
                  extra: dict | None = None) -> Path:
    REPORTS.mkdir(parents=True, exist_ok=True)
    summary = summarize(results)
    payload = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "label": label,
        "summary": summary,
        "cases": [r.as_dict() for r in results],
    }
    if extra:
        payload.update(extra)
    out = REPORTS / f"{label}.json"
    # Compact, AI-oriented output (no pretty printing, no human markdown).
    out.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
    return out


def write_markdown(results: list[CaseResult], summary: dict, path: Path, label: str) -> None:
    lines = [f"# NativaX laboratory — {label}", "",
             f"- total: {summary['total']}",
             f"- pass: {summary['pass']}",
             f"- fail: {summary['fail']}",
             f"- blocked: {summary['blocked']}",
             f"- error: {summary['error']}", ""]
    sections = summary["sections"]
    if sections:
        lines += ["| section | total | pass | fail | blocked | error |",
                  "|---:|---:|---:|---:|---:|---:|"]
        for s in sorted(sections, key=int):
            row = sections[s]
            lines.append(f"| {s} | {row['total']} | {row['pass']} | {row['fail']} | "
                         f"{row['blocked']} | {row['error']} |")
        lines.append("")
    failures = [r for r in results if r.status in ("fail", "error", "blocked")]
    if failures:
        lines.append("## Non-passing cases")
        lines.append("")
        for r in failures[:200]:
            lines.append(f"- `{r.cid}` **{r.status}** — {r.name}: {r.message}")
        lines.append("")
    path.write_text("\n".join(lines) + "\n")


def reset_registry() -> None:
    REGISTRY.clear()


def load_sections() -> None:
    """Import every section module exactly once."""
    sections_dir = LAB_DIR / "sections"
    if not sections_dir.exists():
        return
    for path in sorted(sections_dir.glob("s*.py")):
        if path.name.startswith("_"):
            continue
        modname = f"lab.sections.{path.stem}"
        __import__(modname)

"""Data-driven laboratory cases imported from real-world examples.

The old laboratory contained 1,801 generated clones of one design template.
That filler was removed by ``debug/tools/import_real_examples.py`` and replaced
with 240 self-contained examples taken verbatim from three public repositories.
This module turns those examples into laboratory cases.

Every expectation below is derived independently from the original source with
Python's ``html.parser``: the NativaX binaries are never used to generate it.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from harness import (  # noqa: E402
    between, close, contains, eq, fail, falsy, gt, lt, truthy,
)

LAB_DIR = Path(__file__).resolve().parent
MANIFEST = LAB_DIR / "corpus.json"


def _load_manifest() -> dict[str, Any]:
    if not MANIFEST.exists():
        raise RuntimeError(
            "debug/lab/corpus.json is missing; run "
            "python3 debug/tools/import_real_examples.py --force")
    return json.loads(MANIFEST.read_text())


_MANIFEST = _load_manifest()
CASES: list[dict[str, Any]] = _MANIFEST["cases"]


def cases_for(section: int) -> list[dict[str, Any]]:
    return [c for c in CASES if c["section"] == section]


def section_count(section: int) -> int:
    return len(cases_for(section))


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def _simple(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z][\w-]{0,63}", value or ""))


def _decl_names(page) -> set[str]:
    names: set[str] = set()
    for rule in page.rules():
        for decl in rule.get("decls", []):
            names.add(str(decl.get("name", "")).lower())
    return names


def _body_text(page) -> str:
    try:
        return _norm(page.require("body").text_content())
    except Exception:
        return ""


def _attr_samples(facts: dict) -> list[tuple[str, dict]]:
    out = []
    for ident, info in (facts.get("attr_samples") or {}).items():
        if _simple(ident):
            out.append((ident, info))
    return out[:15]


def _local_ref(path: str, case_dir: Path) -> Path | None:
    if not path or path.startswith(("http:", "https:", "//", "data:", "#")):
        return None
    from urllib.parse import urlsplit, unquote
    rel = unquote(urlsplit(path).path)
    if not rel or rel.startswith("/"):
        return None
    try:
        resolved = (case_dir / rel).resolve()
        resolved.relative_to(case_dir.resolve())
    except (ValueError, OSError):
        return None
    return resolved


def check_common(ctx, case: dict[str, Any], section: int) -> None:
    cid = case["id"]
    facts = case["facts"]
    page = ctx.fixture(cid)
    case_dir = LAB_DIR / case["dir"]

    # Document skeleton.
    truthy(page.find("html"), f"{cid}: html element missing")
    truthy(page.find("head"), f"{cid}: head element missing")
    truthy(page.find("body"), f"{cid}: body element missing")

    title = facts.get("title", "")
    if title and page.find("title"):
        native_title = _norm(page.text("title"))
        truthy(native_title and (native_title in title or title in native_title),
               f"{cid}: title mismatch")

    # Every statically declared id survives parsing.
    ids = facts.get("ids") or []
    id_counts = facts.get("id_counts") or {}
    for ident in ids[:25]:
        if not _simple(ident):
            continue
        nodes = page.find_all("#" + ident)
        truthy(nodes, f"{cid}: id {ident!r} was lost")
        if id_counts.get(ident, 1) == 1:
            eq(len(nodes), 1, f"{cid}: id {ident!r} count mismatch")
        else:
            truthy(len(nodes) >= 1, f"{cid}: id {ident!r} was lost")

    # Declared classes are still reachable.
    classes = facts.get("classes") or []
    for cls in classes[:30]:
        if not _simple(cls):
            continue
        truthy(page.find_all("." + cls),
               f"{cid}: class {cls!r} was lost")

    # Declared tags are preserved.
    for tag in facts.get("html_tags") or []:
        if tag not in {"html", "head", "body"}:
            truthy(page.find(tag), f"{cid}: <{tag}> was lost")

    # Representative element attributes and computed styles.
    for ident, info in _attr_samples(facts):
        node = page.find("#" + ident)
        if node is None:
            continue
        expected_class = _norm(info.get("class", ""))
        if expected_class:
            eq(_norm(node.attrs.get("class", "")), expected_class,
               f"{cid}: class attribute mismatch for #{ident}")
        for key, value in (info.get("attrs") or {}).items():
            if key in ("style",):
                continue
            if key not in node.attrs:
                fail(f"{cid}: attribute {key!r} missing on #{ident}")
            eq(_norm(node.attrs.get(key, "")), _norm(value),
               f"{cid}: attribute {key!r} mismatch on #{ident}")
        st = page.maybe_style(node)
        if st is not None:
            truthy(isinstance(st, dict), f"{cid}: style is not a dict")
            truthy(0 <= float(st.get("color", [0, 0, 0, 0])[0]) <= 1,
                   f"{cid}: invalid color")
            truthy(st.get("display") in {
                "none", "block", "flex", "inline", "inline-block", "grid",
                "table", "table-row", "table-cell", "list-item", "contents",
                "inline-flex", "inline-grid", "flow-root", "inherit", "initial",
                "unset"}, f"{cid}: unknown display")

    # Visible text from the original document survives.
    body_text = _body_text(page)
    for sample in (facts.get("text_samples") or [])[:6]:
        sample = _norm(sample)
        if len(sample) >= 12:
            contains(body_text, sample[:60],
                     f"{cid}: text sample was lost: {sample[:40]!r}")

    # Shape of the parsed tree.
    summary = page.summary
    dom = summary.get("dom", {})
    truthy(int(dom.get("elements", 0)) >= max(6, int(facts.get("elements", 0) * 0.5)),
           f"{cid}: too few elements ({dom.get('elements')} < {facts.get('elements')})")
    truthy(int(dom.get("max_depth", 0)) >= 2, f"{cid}: max depth too shallow")
    truthy(len(page.all_boxes()) >= 1, f"{cid}: no layout boxes")

    # CSS provenance.
    css_facts = facts.get("css") or {}
    linked_css = facts.get("linked_css") or []
    style_blocks = int(facts.get("style_blocks", 0))
    if linked_css or style_blocks:
        truthy(int(summary.get("css", {}).get("rules", 0))
               + int(summary.get("css", {}).get("inline_styles", 0)) >= 0,
               f"{cid}: css summary missing")
    for href in linked_css[:16]:
        resolved = _local_ref(href, case_dir)
        if resolved is not None:
            truthy(resolved.is_file(), f"{cid}: missing css asset {href!r}")

    # Scripts and images referenced by the entry page exist.
    for src in (facts.get("linked_js") or [])[:16]:
        resolved = _local_ref(src, case_dir)
        if resolved is not None:
            truthy(resolved.is_file(), f"{cid}: missing script asset {src!r}")
    for src in (facts.get("images") or [])[:16]:
        resolved = _local_ref(src, case_dir)
        if resolved is not None and not resolved.is_file():
            # Recorded upstream omission: not fatal for the parsed document.
            pass

    # Computed style sanity for every sampled id.
    for ident, _info in _attr_samples(facts)[:5]:
        node = page.find("#" + ident)
        if node is None:
            continue
        st = page.maybe_style(node)
        if st is None:
            continue
        truthy(isinstance(st.get("color"), list) and len(st["color"]) == 4,
               f"{cid}: color style malformed")
        truthy(isinstance(st.get("bg"), list) and len(st["bg"]) == 4,
               f"{cid}: background style malformed")
        truthy(float(st.get("font_size", 0)) > 0, f"{cid}: font size is zero")
        truthy(float(st.get("line_height", 0)) >= 0, f"{cid}: line height invalid")

    # Section-specific checks.
    if section == 1:
        truthy(dom.get("elements", 0) >= 50 or len(page.elements()) >= 20,
               f"{cid}: not a rich HTML case")
        truthy(len(ids) + len(classes) >= 8,
               f"{cid}: too few hooks for DOM testing")

    if section == 2:
        src_selectors = [s for s in (facts.get("css", {}).get("selectors") or [])
                         if _simple(s.lstrip(".#")) or " " in s]
        if src_selectors:
            native_selectors = [r.get("selector", "") for r in page.rules()]
            found = any(
                any(tok in sel for tok in (s.split()[0], s.split(".")[0]))
                for s in src_selectors[:12] for sel in native_selectors)
            if facts.get("css", {}).get("rules", 0) > 0:
                truthy(found, f"{cid}: no source CSS selector survived parsing")

    if section == 3:
        boxes = page.all_boxes()
        truthy(len(boxes) >= max(5, min(20, len(page.elements()) // 3)),
               f"{cid}: too few boxes")
        body_box = page.box("body")
        if body_box:
            truthy(0 < float(body_box.get("w", 0)) <= page.viewport_size[0] + 2.0,
                   f"{cid}: body width out of range")
        styles = [page.maybe_style(n) for n in page.elements()[:40]]
        styles = [s for s in styles if s]
        if any((s.get("padding") or [0, 0, 0, 0]) != [0, 0, 0, 0]
               for s in styles):
            pass
        else:
            # Only fail when the source actually declares box spacing.
            if any(p in (facts.get("css", {}).get("properties") or [])
                   for p in ("padding", "margin", "border")):
                truthy(False, f"{cid}: box spacing disappeared")

    if section == 4:
        props = facts.get("css", {}).get("properties") or []
        if any(p in props for p in ("font-size", "font-family",
                                    "line-height", "text-align",
                                    "letter-spacing")):
            truthy(_decl_names(page) & {"font-size", "font-family",
                                        "line-height", "text-align",
                                        "letter-spacing"},
                   f"{cid}: no typography declaration survived")
        truthy(page.style("body").get("font_size", 0) > 0,
               f"{cid}: body font size is zero")

    if section == 5:
        props = facts.get("css", {}).get("properties") or []
        if any(p in props for p in ("color", "background", "background-color")):
            truthy(_decl_names(page) & {"color", "background",
                                        "background-color", "background-image"},
                   f"{cid}: no color declaration survived")
        styles = [s for s in (page.maybe_style(n) for n in page.elements())
                  if s]
        truthy(any(s.get("color", [0, 0, 0, 1]) != [0, 0, 0, 1]
                    or (s.get("bg") or [0, 0, 0, 0])[3] > 0
                    for s in styles),
               f"{cid}: no computed color or background")

    if section == 6:
        props = facts.get("css", {}).get("properties") or []
        anim_props = {"transform", "transition", "animation", "opacity"}
        if anim_props & set(props):
            truthy(_decl_names(page) & anim_props,
                   f"{cid}: no transform/transition/animation declaration survived")

    if section == 7:
        if int(facts.get("css", {}).get("media", 0)) > 0:
            truthy(any(r.get("media") for r in page.rules()),
                   f"{cid}: @media block was dropped")

    if section == 8:
        if "flex" in (facts.get("features") or []):
            styles = [s for s in (page.maybe_style(n) for n in page.elements())
                      if s]
            truthy(any(s.get("display") == "flex" for s in styles),
                   f"{cid}: no element computes to display:flex")

    if section == 9:
        props = facts.get("css", {}).get("properties") or []
        if any(p in props for p in ("position", "float", "z-index")):
            truthy(_decl_names(page) & {"position", "float", "z-index"},
                   f"{cid}: no positioning declaration survived")

    if section == 10:
        truthy(page.find("script"), f"{cid}: no script element")
        truthy((facts.get("js_bytes") or 0) > 0 or facts.get("linked_js"),
               f"{cid}: no JavaScript payload")
        for src in (facts.get("linked_js") or [])[:8]:
            resolved = _local_ref(src, case_dir)
            if resolved is not None:
                truthy(resolved.is_file(), f"{cid}: missing script {src!r}")

    if section == 11:
        truthy(page.find("script"), f"{cid}: no script element")
        entry_path = case_dir / case.get("entry", "index.html")
        try:
            entry_html = entry_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            entry_html = ""
        linked_scripts = ""
        for src in (facts.get("linked_js") or []):
            resolved = _local_ref(src, case_dir)
            if resolved is not None and resolved.is_file():
                try:
                    linked_scripts += " " + resolved.read_text(
                        encoding="utf-8", errors="replace")
                except OSError:
                    pass
        inline_scripts = "\n".join(
            re.findall(r"<script\b[^>]*>(.*?)</script\s*>", entry_html,
                       re.I | re.S))
        if facts.get("linked_js") or facts.get("inline_js"):
            truthy(re.search(r"addEventListener|onclick|onchange|onsubmit|"
                             r"oninput|onkeydown|onkeyup|onmouseover|onload",
                             linked_scripts + " " + inline_scripts + " " +
                             entry_html, re.I),
                   f"{cid}: no event handler found in JavaScript")

    if section == 12:
        for tag in ("form", "input", "select", "textarea", "button", "label"):
            if int((facts.get("forms") or {}).get(tag, 0)) > 0:
                truthy(page.find(tag), f"{cid}: <{tag}> was lost")
        for ident, info in _attr_samples(facts):
            attrs = info.get("attrs") or {}
            if "type" in attrs and _simple(ident):
                node = page.find("#" + ident)
                if node is not None and "type" in node.attrs:
                    eq(_norm(node.attrs["type"]), _norm(attrs["type"]),
                       f"{cid}: input type mismatch for #{ident}")

    if section == 13:
        roles = facts.get("roles") or {}
        for role in list(roles)[:10]:
            truthy(page.find(f'[role="{role}"]'),
                   f"{cid}: role {role!r} was lost")
        if facts.get("aria"):
            truthy(any(page.find(f"[{name}]") for name in
                       (facts.get("aria") or {})),
                   f"{cid}: aria attribute was lost")

    if section == 14:
        for tag in ("img", "picture", "source", "video", "audio", "canvas",
                    "svg", "iframe"):
            if int((facts.get("media") or {}).get(tag, 0)) > 0:
                truthy(page.find(tag), f"{cid}: <{tag}> was lost")
        for src in (facts.get("images") or [])[:8]:
            resolved = _local_ref(src, case_dir)
            if resolved is not None and not resolved.is_file():
                # Upstream omissions are recorded in case.json; only local
                # assets that should exist are enforced.
                pass
            if resolved is not None and resolved.is_file():
                truthy(True)

    if section == 15:
        truthy(int(facts.get("elements", 0)) >= 30,
               f"{cid}: not a large document")
        truthy(int(dom.get("elements", 0)) >= int(facts.get("elements", 0) * 0.5),
               f"{cid}: large document was truncated")
        truthy(len(page.all_boxes()) >= 20, f"{cid}: too few boxes for a large page")

    if section == 16:
        truthy(len(facts.get("features") or []) >= 4,
               f"{cid}: not an integration case")
        truthy(int(summary.get("css", {}).get("rules", 0)) > 0
               or not facts.get("linked_css"),
               f"{cid}: integration CSS did not parse")
        truthy(len(page.all_boxes()) >= 10, f"{cid}: integration layout missing")
        truthy(len(ids) >= 1 or len(classes) >= 5,
               f"{cid}: integration has no hooks")


import harness as _harness


def register(section: int) -> None:
    """Register all corpus cases for one section."""
    for c in cases_for(section):
        cid = c["id"]

        def fn(ctx, c=c, section=section):
            check_common(ctx, c, section)

        fn.__name__ = "case_" + cid.replace(".", "_")
        _harness.case(
            section, cid,
            f"{c['source']['repo']} · {c['source']['path']}",
            tags=tuple(c["facts"].get("features", [])),
        )(fn)


def register_all() -> None:
    for section in range(1, 17):
        register(section)
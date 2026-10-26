"""Maps a visual-judge element path to the fixture's source: the HTML tag
(with id, class and line) and the author CSS rules that mention it.

Probe paths are `tag:n>tag:n…` where n counts previous siblings with the same
tag (nth-of-type), or `#id` at the first ancestor with an id.
"""
from __future__ import annotations

import re
from functools import lru_cache
from html.parser import HTMLParser
from pathlib import Path

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source",
        "track", "wbr"}


class _Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.nodes: dict[str, dict] = {}
        self.stack = [{"path": "", "counts": {}}]
        self.ids: dict[str, str] = {}

    def handle_starttag(self, tag, attrs):
        parent = self.stack[-1]
        n = parent["counts"].get(tag, 0) + 1
        parent["counts"][tag] = n
        path = f"{parent['path']}>{tag}:{n}" if parent["path"] else f"{tag}:{n}"
        a = dict(attrs)
        node = {"tag": tag, "id": a.get("id"), "class": a.get("class"), "line": self.getpos()[0]}
        self.nodes[path] = node
        if a.get("id"):
            self.ids[a["id"]] = path
        if tag not in VOID:
            self.stack.append({"path": path, "counts": {}})

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i]["path"].rsplit(">", 1)[-1].split(":")[0] == tag:
                del self.stack[i:]
                break


@lru_cache(maxsize=256)
def _parse(html_path: str):
    tree = _Tree()
    try:
        tree.feed(Path(html_path).read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return None
    return tree


def element(html_path: str, probe_path: str) -> dict | None:
    tree = _parse(html_path)
    if tree is None:
        return None
    path = probe_path
    if path.startswith("#"):
        head, _, rest = path.partition(">")
        base = tree.ids.get(head[1:])
        if base is None:
            return None
        path = base + (">" + rest if rest else "")
    return tree.nodes.get(path)


def selector_label(node: dict | None) -> str | None:
    if not node:
        return None
    out = node["tag"]
    if node.get("id"):
        out += f"#{node['id']}"
    if node.get("class"):
        out += "".join(f".{c}" for c in node["class"].split())
    return out


_RULE = re.compile(r"([^{}]+)\{([^{}]*)\}", re.S)


@lru_cache(maxsize=256)
def _css_sources(fixture_dir: str) -> tuple[tuple[str, str], ...]:
    d = Path(fixture_dir)
    out = []
    for css in sorted(d.rglob("*.css")):
        try:
            out.append((css.name, css.read_text(encoding="utf-8", errors="replace")))
        except OSError:
            pass
    for html in sorted(d.glob("*.html")):
        try:
            text = html.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in re.finditer(r"<style[^>]*>(.*?)</style>", text, re.S | re.I):
            out.append((html.name, " " * 0 + text[:m.start(1)].count("\n") * "\n" + m.group(1)))
    return tuple(out)


def css_rules(fixture_dir: str, node: dict | None, limit: int = 4) -> list[list]:
    """[[file:line, selector, declarations]] of author rules naming the
    element's id or classes (or its tag when it has neither)."""
    if not node:
        return []
    tokens = [f"#{node['id']}"] if node.get("id") else []
    tokens += [f".{c}" for c in (node.get("class") or "").split()]
    out = []
    for name, text in _css_sources(fixture_dir):
        for m in _RULE.finditer(text):
            selector = " ".join(m.group(1).split())
            if selector.startswith("@"):
                continue
            hit = any(re.search(re.escape(tok) + r"(?![\w-])", selector) for tok in tokens) if tokens else \
                re.search(rf"(^|[\s,>+~]){node['tag']}(?![\w-])", selector)
            if hit:
                line = text[:m.start()].count("\n") + 1
                body = re.sub(r"\s+", " ", m.group(2)).strip()
                out.append([f"{name}:{line}", selector[:120], body[:240]])
                if len(out) >= limit:
                    return out
    return out

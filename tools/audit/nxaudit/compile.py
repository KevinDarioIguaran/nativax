"""Lowers a JSON audit screen to an HTML document NativaX and Chromium load.

Every element gets `id`, `data-nx` (its structural JSON path, e.g.
`screen.children[0].children[1]`) and `data-nx-type`, so a measurement can
always be traced back to the exact JSON node.
"""
from __future__ import annotations

import html
import json

from .catalog import COMPONENTS
from .probe import INSTRUMENTATION

FREEZE = "*,*::before,*::after{animation:none!important;transition:none!important}"


def walk(node: dict, path: str = "screen"):
    """Yields `(path, node)` depth first, root included."""
    yield path, node
    for index, child in enumerate(node.get("children") or []):
        yield from walk(child, f"{path}.children[{index}]")


def find(screen: dict, path: str) -> dict | None:
    for p, node in walk(screen):
        if p == path:
            return node
    return None


def node_by_id(screen: dict, node_id: str) -> tuple[str, dict] | None:
    for p, node in walk(screen):
        if node.get("id") == node_id:
            return p, node
    return None


def _decls(style: dict) -> str:
    return "; ".join(f"{k}: {v}" for k, v in style.items())


def _handler_js(node_id: str, event: str, steps: list[dict]) -> str:
    body = []
    for step in steps:
        target = json.dumps(step.get("target") or node_id)
        el = f"document.getElementById({target})"
        op = step.get("do")
        if op == "set_text":
            body.append(f"{el}.textContent = {json.dumps(step.get('text', ''))};")
        elif op == "increment":
            body.append(f"{el}.textContent = String((parseInt({el}.textContent, 10) || 0) + 1);")
        elif op == "set_style":
            body.append(f"{el}.style.setProperty({json.dumps(step['property'])}, "
                        f"{json.dumps(step['value'])});")
        elif op == "toggle_hidden":
            body.append(f"{el}.style.display = {el}.style.display === 'none' ? '' : 'none';")
        elif op == "append_text":
            body.append(f"var n = document.createElement('p'); n.textContent = "
                        f"{json.dumps(step.get('text', ''))}; {el}.appendChild(n);")
        elif op == "remove":
            body.append(f"var r = {el}; if (r && r.parentNode) r.parentNode.removeChild(r);")
    return (f"document.getElementById({json.dumps(node_id)}).addEventListener("
            f"{json.dumps(event)}, function (e) {{ {' '.join(body)} }});")


def _open_tag(node: dict, path: str, inline: bool) -> tuple[str, str, bool]:
    kind = node["type"]
    spec = COMPONENTS[kind]
    tag = spec["tag"]
    attrs = node.get("attrs") or {}
    if kind == "heading":
        tag = f"h{int(attrs.get('level', 2))}"
    parts = [f'id="{html.escape(node["id"])}"', f'data-nx="{path}"',
             f'data-nx-type="{kind}"']
    if kind == "input":
        parts.append(f'type="{html.escape(str(attrs.get("input_type", "text")))}"')
    if kind == "checkbox":
        parts.append('type="checkbox"')
        if attrs.get("checked"):
            parts.append("checked")
    if kind == "link":
        parts.append('href="#"')
    if kind == "button" and attrs.get("submit") is not True:
        parts.append('type="button"')
    for name in ("placeholder", "value", "tabindex", "aria-label", "title"):
        if name in attrs:
            parts.append(f'{name}="{html.escape(str(attrs[name]))}"')
    if attrs.get("disabled"):
        parts.append("disabled")
    style = dict(spec.get("base_style") or {})
    style.update(node.get("style") or {})
    if inline and style:
        parts.append(f'style="{html.escape(_decls(style))}"')
    return tag, " ".join(parts), spec.get("void", False)


def compile_screen(scenario: dict) -> str:
    screen = scenario["screen"]
    env = scenario.get("environment") or {}
    inline = env.get("style_mode", "sheet") == "inline"
    body_margin = env.get("body_margin", "0px")
    font = env.get("font_family", "'Liberation Sans'")
    rules = [FREEZE, f"body{{margin:{body_margin};font-family:{font}}}"]
    scripts = []
    out: list[str] = []

    def emit(node: dict, path: str, depth: int):
        tag, attrs, void = _open_tag(node, path, inline)
        spec = COMPONENTS[node["type"]]
        if not inline:
            style = dict(spec.get("base_style") or {})
            style.update(node.get("style") or {})
            if style:
                rules.append(f"#{node['id']}{{{_decls(style)}}}")
        for event, steps in (node.get("on") or {}).items():
            scripts.append(_handler_js(node["id"], event, steps))
        pad = "  " * depth
        if void:
            out.append(f"{pad}<{tag} {attrs}>")
            return
        if node["type"] == "select":
            options = "".join(f"<option>{html.escape(str(o))}</option>"
                              for o in (node.get("attrs") or {}).get("options", ["A", "B"]))
            out.append(f"{pad}<{tag} {attrs}>{options}</{tag}>")
            return
        text = html.escape(node.get("text") or "")
        children = node.get("children") or []
        if not children:
            out.append(f"{pad}<{tag} {attrs}>{text}</{tag}>")
            return
        out.append(f"{pad}<{tag} {attrs}>{text}")
        for index, child in enumerate(children):
            emit(child, f"{path}.children[{index}]", depth + 1)
        out.append(f"{pad}</{tag}>")

    emit(screen, "screen", 1)
    extra_css = env.get("extra_css") or ""
    return (
        "<!doctype html>\n<html><head><meta charset=\"utf-8\">"
        f"<title>{html.escape(scenario.get('scenario_id', 'audit'))}</title>\n"
        f"<script>{INSTRUMENTATION}</script>\n"
        f"<style>\n{chr(10).join(rules)}\n{extra_css}\n</style></head>\n<body>\n"
        + "\n".join(out)
        + ("\n<script>\n" + "\n".join(scripts) + "\n</script>" if scripts else "")
        + "\n</body></html>\n"
    )

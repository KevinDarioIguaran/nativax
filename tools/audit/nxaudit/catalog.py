"""Component and property catalog for JSON audit screens.

NativaX has no JSON screen format of its own: it renders HTML, CSS and
JavaScript. An audit screen is a JSON component tree that `compile.py`
lowers to a real HTML document, so every component here names the HTML it
becomes. Property names are CSS longhands/shorthands; whether NativaX parses
them is not assumed but read from `nativa_css` (`css_support()`), and whether
it renders them correctly is what the audit measures.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# Component type -> HTML lowering and structural rules. `executable: False`
# marks a type that exists in the schema but cannot run in the offscreen
# harness; the generator never emits it and the report says why.
COMPONENTS: dict[str, dict] = {
    "screen": {"tag": "main", "container": True, "executable": True},
    "container": {"tag": "div", "container": True, "executable": True},
    "row": {"tag": "div", "container": True, "executable": True,
            "base_style": {"display": "flex", "flex-direction": "row"}},
    "column": {"tag": "div", "container": True, "executable": True,
               "base_style": {"display": "flex", "flex-direction": "column"}},
    "grid": {"tag": "div", "container": True, "executable": True,
             "base_style": {"display": "grid"}},
    "scroll": {"tag": "div", "container": True, "executable": True,
               "base_style": {"overflow-y": "auto"}},
    "stack": {"tag": "div", "container": True, "executable": True,
              "base_style": {"position": "relative"}},
    "form": {"tag": "form", "container": True, "executable": True},
    "list": {"tag": "ul", "container": True, "executable": True,
             "child_types": ["list_item"]},
    "list_item": {"tag": "li", "container": True, "executable": True},
    "text": {"tag": "p", "container": False, "executable": True, "text": True},
    "inline_text": {"tag": "span", "container": False, "executable": True,
                    "text": True},
    "heading": {"tag": "h2", "container": False, "executable": True,
                "text": True},
    "button": {"tag": "button", "container": False, "executable": True,
               "text": True, "focusable": True},
    "link": {"tag": "a", "container": False, "executable": True, "text": True,
             "focusable": True},
    "input": {"tag": "input", "container": False, "executable": True,
              "void": True, "focusable": True},
    "checkbox": {"tag": "input", "container": False, "executable": True,
                 "void": True, "focusable": True},
    "textarea": {"tag": "textarea", "container": False, "executable": True,
                 "text": True, "focusable": True},
    "select": {"tag": "select", "container": False, "executable": True,
               "focusable": True},
    "spacer": {"tag": "div", "container": False, "executable": True},
    # The offscreen harness has no image resolver for data: URIs; an image
    # would measure the resolver, not the runtime.
    "image": {"tag": "img", "container": False, "executable": False,
              "void": True,
              "reason": "audit harness passes no imageResolver; images "
                        "would measure the missing resolver"},
}

INPUT_TYPES = ["text", "number", "password", "email", "search"]

# Property -> value domains. `valid` values are used for nominal screens,
# `boundary` for extreme-but-legal values, `invalid` for values a browser
# must drop at parse time (the screen stays valid JSON; only the CSS is bad).
PROPERTIES: dict[str, dict] = {
    "width": {"valid": ["40px", "120px", "50%", "100%", "auto", "12em",
                        "calc(50% - 10px)", "fit-content"],
              "boundary": ["0px", "1px", "4000px", "0%", "100vw"],
              "invalid": ["-10px", "12pz", "calc(", "red"]},
    "height": {"valid": ["20px", "48px", "120px", "auto", "50%"],
               "boundary": ["0px", "1px", "3000px", "100vh"],
               "invalid": ["-4px", "tall", "10"]},
    "min-width": {"valid": ["0px", "60px", "30%"],
                  "boundary": ["2000px"], "invalid": ["-1px"]},
    "max-width": {"valid": ["none", "80px", "200px", "60%"],
                  "boundary": ["0px", "1px"], "invalid": ["auto"]},
    "min-height": {"valid": ["0px", "40px"], "boundary": ["2000px"],
                   "invalid": ["-5px"]},
    "max-height": {"valid": ["none", "60px", "150px"],
                   "boundary": ["0px"], "invalid": ["big"]},
    "padding": {"valid": ["0px", "4px", "8px 12px", "10px 4px 2px 20px",
                          "1em", "5%"],
                "boundary": ["0px", "200px", "0.5px"],
                "invalid": ["-8px", "8 px", "auto"]},
    "margin": {"valid": ["0px", "8px", "4px 16px", "auto", "0 auto",
                         "-6px"],
               "boundary": ["-200px", "300px", "0.3px"],
               "invalid": ["8 px", "big"]},
    "border": {"valid": ["1px solid #333333", "3px dashed red",
                         "2px dotted rgb(0, 128, 0)", "none",
                         "4px double #0055aa"],
               "boundary": ["0px solid black", "40px solid #ccc"],
               "invalid": ["solid solid", "3px wavy red"]},
    "border-radius": {"valid": ["0px", "4px", "12px", "50%",
                                "8px 0px 8px 0px"],
                      "boundary": ["9999px", "0.5px"],
                      "invalid": ["-3px", "round"]},
    "box-sizing": {"valid": ["content-box", "border-box"],
                   "invalid": ["padding-box"]},
    "background-color": {"valid": ["#ffffff", "#f0f4ff", "rgb(200, 30, 30)",
                                   "rgba(0, 0, 0, 0.5)", "transparent",
                                   "hsl(120, 60%, 40%)", "teal"],
                         "boundary": ["rgba(0, 0, 0, 0)", "#000"],
                         "invalid": ["#ggg", "rgb(1,2)", "notacolor"]},
    "color": {"valid": ["#111111", "#ff0000", "rgb(0, 0, 255)", "navy",
                        "currentcolor"],
              "boundary": ["transparent"], "invalid": ["#12", "blu"]},
    "opacity": {"valid": ["1", "0.5", "0.9"], "boundary": ["0", "1.0001"],
                "invalid": ["half", "50%%"]},
    "visibility": {"valid": ["visible", "hidden"], "invalid": ["gone"]},
    "display": {"valid": ["block", "inline", "inline-block", "flex",
                          "inline-flex", "grid", "none"],
                "invalid": ["flexbox", "box"]},
    "position": {"valid": ["static", "relative", "absolute"],
                 "invalid": ["floating"]},
    "top": {"valid": ["0px", "10px", "-5px", "20%"],
            "boundary": ["5000px"], "invalid": ["up"]},
    "left": {"valid": ["0px", "12px", "-8px", "30%"],
             "boundary": ["-5000px"], "invalid": ["10pxx"]},
    "z-index": {"valid": ["0", "1", "10", "-1"],
                "boundary": ["2147483647"], "invalid": ["1.5"]},
    "overflow": {"valid": ["visible", "hidden", "auto", "scroll"],
                 "invalid": ["clip-all"]},
    "font-size": {"valid": ["12px", "14px", "16px", "20px", "1.5em",
                            "large", "small"],
                  "boundary": ["0px", "1px", "96px"],
                  "invalid": ["-12px", "huge"]},
    "font-weight": {"valid": ["400", "700", "bold", "normal", "300"],
                    "boundary": ["1", "1000"],
                    "invalid": ["heavy", "1001"]},
    "font-style": {"valid": ["normal", "italic"], "invalid": ["slanted"]},
    "font-family": {"valid": ["'Liberation Sans'", "'Liberation Serif'",
                              "'DejaVu Sans Mono'", "'Noto Sans'",
                              "sans-serif", "serif", "monospace"],
                    "invalid": []},
    "line-height": {"valid": ["normal", "1.2", "1.5", "20px", "150%"],
                    "boundary": ["0", "0.1", "10"],
                    "invalid": ["-1", "tall"]},
    "letter-spacing": {"valid": ["normal", "1px", "0.1em", "-0.5px"],
                       "boundary": ["20px"], "invalid": ["wide"]},
    "text-align": {"valid": ["left", "center", "right", "justify"],
                   "invalid": ["middle"]},
    "text-transform": {"valid": ["none", "uppercase", "lowercase",
                                 "capitalize"],
                       "invalid": ["upper"]},
    "text-decoration-line": {"valid": ["none", "underline",
                                       "line-through"],
                             "invalid": ["strike"]},
    "white-space": {"valid": ["normal", "nowrap", "pre", "pre-wrap"],
                    "invalid": ["no-wrap"]},
    "word-break": {"valid": ["normal", "break-all", "keep-all"],
                   "invalid": ["anywhere-ish"]},
    "overflow-wrap": {"valid": ["normal", "break-word", "anywhere"],
                      "invalid": ["wrap"]},
    "text-overflow": {"valid": ["clip", "ellipsis"], "invalid": ["dots"]},
    "flex-direction": {"valid": ["row", "column", "row-reverse",
                                 "column-reverse"],
                       "invalid": ["horizontal"]},
    "flex-wrap": {"valid": ["nowrap", "wrap", "wrap-reverse"],
                  "invalid": ["yes"]},
    "justify-content": {"valid": ["flex-start", "center", "flex-end",
                                  "space-between", "space-around",
                                  "space-evenly"],
                        "invalid": ["middle"]},
    "align-items": {"valid": ["stretch", "flex-start", "center", "flex-end",
                              "baseline"],
                    "invalid": ["top"]},
    "align-self": {"valid": ["auto", "flex-start", "center", "flex-end",
                             "stretch"],
                   "invalid": ["mid"]},
    "flex-grow": {"valid": ["0", "1", "2"], "boundary": ["1000"],
                  "invalid": ["-1"]},
    "flex-shrink": {"valid": ["0", "1", "3"], "invalid": ["-2"]},
    "flex-basis": {"valid": ["auto", "0px", "50px", "30%"],
                   "invalid": ["-10px"]},
    "gap": {"valid": ["0px", "4px", "12px", "8px 16px"],
            "boundary": ["100px"], "invalid": ["-4px"]},
    "grid-template-columns": {"valid": ["1fr 1fr", "100px auto",
                                        "repeat(3, 1fr)", "1fr 2fr 1fr",
                                        "repeat(2, minmax(0, 1fr))"],
                              "boundary": ["repeat(12, 1fr)"],
                              "invalid": ["1fr,1fr", "repeat(x, 1fr)"]},
    "order": {"valid": ["0", "1", "-1", "3"], "invalid": ["first"]},
    "box-shadow": {"valid": ["none", "0px 2px 4px rgba(0, 0, 0, 0.3)",
                             "inset 0 0 0 2px #333"],
                   "invalid": ["2px"]},
    "vertical-align": {"valid": ["baseline", "middle", "top", "bottom"],
                       "invalid": ["center"]},
    "aspect-ratio": {"valid": ["auto", "1 / 1", "16 / 9"],
                     "invalid": ["wide"]},
    "transform": {"valid": ["none", "translateX(10px)", "scale(0.9)",
                            "rotate(10deg)"],
                  "invalid": ["spin(4)"]},
}

# Shorthand -> longhands that the probe reads back. Comparing longhands lets
# the report name the exact computed property that diverged.
LONGHANDS: dict[str, list[str]] = {
    "padding": ["padding-top", "padding-right", "padding-bottom",
                "padding-left"],
    "margin": ["margin-top", "margin-right", "margin-bottom", "margin-left"],
    "border": ["border-top-width", "border-right-width", "border-bottom-width",
               "border-left-width", "border-top-style", "border-top-color"],
    "border-radius": ["border-top-left-radius", "border-top-right-radius",
                      "border-bottom-right-radius",
                      "border-bottom-left-radius"],
    "overflow": ["overflow-x", "overflow-y"],
    "gap": ["row-gap", "column-gap"],
}

# Computed properties the probe reads for every element.
PROBED_PROPERTIES: list[str] = sorted({
    longhand
    for name in PROPERTIES
    for longhand in LONGHANDS.get(name, [name])
})

# Properties whose computed value Chromium serializes from layout (`width:
# auto` becomes the used pixel width); a mismatch there is reported by the
# geometry oracle, not as a style divergence.
LAYOUT_SERIALIZED = {"width", "height", "top", "left", "margin-left",
                     "margin-right", "flex-basis", "grid-template-columns",
                     "min-width", "min-height", "line-height"}

TEXT_SAMPLES = {
    "short": ["OK", "Go", "Aceptar", "Save"],
    "medium": ["Texto de prueba para la interfaz",
               "The quick brown fox jumps over the lazy dog"],
    "long": ["Cadena de prueba suficientemente larga para evaluar el "
             "comportamiento del texto en contenedores estrechos y anchos " * 3],
    "unicode": ["Ñandú añejo — ¿qué tal? ¡Sí!", "Zażółć gęślą jaźń",
                "Ελληνικά κείμενο", "Кириллица тест", "→ ← ↑ ↓ ✓ ✗ ★"],
    "special": ["<b>no html</b> & \"quotes\" 'single'", "a b c",
                "tab\there", "line1\nline2"],
    "unbreakable": ["Supercalifragilisticexpialidocious" * 3,
                    "https://example.invalid/a/very/long/path/without/spaces"],
    "empty": [""],
}


def css_support(cache: Path | None = None) -> dict:
    """Asks nativa_css which property names it parses (`isSupportedProperty`).

    The answer comes from the real registry through `tools/audit/dart/
    css_support.dart`; it is cached per source mtime so a run does not pay a
    Dart start each time. Returns `{"source": ..., "properties": {name: bool}}`.
    """
    cache = cache or ROOT / ".audit" / "css-support.json"
    source = ROOT / "packages" / "nativa_css" / "lib" / "src" / "properties.dart"
    names = sorted(set(PROPERTIES) | set(PROBED_PROPERTIES))
    stamp = source.stat().st_mtime_ns if source.exists() else 0
    try:
        cached = json.loads(cache.read_text())
        if cached.get("stamp") == stamp and set(cached["properties"]) >= set(names):
            return cached
    except (OSError, ValueError, KeyError):
        pass
    script = ROOT / "tools" / "audit" / "dart" / "css_support.dart"
    result = subprocess.run(
        ["dart", "--packages=.dart_tool/package_config.json", str(script),
         *names],
        cwd=ROOT, capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(f"css_support.dart failed: {result.stderr[-400:]}")
    data = {"stamp": stamp, "source": str(source.relative_to(ROOT)),
            "properties": json.loads(result.stdout)}
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(data, indent=2, sort_keys=True))
    return data


def catalog_document(support: dict | None = None) -> dict:
    """Machine-readable catalog for reports and docs."""
    support = support or {"properties": {}}
    parsed = support.get("properties", {})
    return {
        "components": {
            name: {
                "html": spec["tag"],
                "container": spec["container"],
                "executable": spec["executable"],
                **({"reason": spec["reason"]} if "reason" in spec else {}),
            }
            for name, spec in COMPONENTS.items()
        },
        "properties": {
            name: {
                "nativa_css_parses": parsed.get(name),
                "longhands_probed": LONGHANDS.get(name, [name]),
                "values": {k: len(v) for k, v in domain.items()},
            }
            for name, domain in PROPERTIES.items()
        },
        "actions": sorted(ACTIONS),
        "assertion_properties": sorted(ASSERTION_PROPERTIES),
    }


# Interactions the executors implement. `reference` says how Chromium
# reproduces it: `input` = hit-tested synthetic DOM events at the same point,
# `script` = identical JS in both engines, `model` = spec model in the
# reference page (keyboard focus traversal), `native` = same API.
ACTIONS = {
    "click": {"reference": "input", "needs_target": True},
    "type": {"reference": "input", "needs_target": True},
    "key": {"reference": "model", "needs_target": False},
    "resize": {"reference": "native", "needs_target": False},
    "rebuild": {"reference": "native", "needs_target": False},
    "script": {"reference": "script", "needs_target": False},
    "wait": {"reference": "native", "needs_target": False},
}

ASSERTION_PROPERTIES = {
    "rect.x", "rect.y", "rect.width", "rect.height", "visible",
    "overflow_x", "overflow_y", "text", "value", "checked", "focused",
    "events", "style", "exists",
}

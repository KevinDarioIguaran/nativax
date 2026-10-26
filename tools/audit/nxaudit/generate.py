"""Scenario generators. Every scenario is a pure function of (family, seed,
generator version), so `regenerate(family, seed)` rebuilds it byte for byte.

Families:
  basic          one component x one property x one value, enumerated
  combinatorial  pairwise covering array over a container/child template
  random         seeded random trees from the valid domains
  adversarial    depth, width, huge/Unicode text, boundary values
  invalid        legal JSON whose CSS values a browser must drop
  schema_invalid deliberately broken scenario JSON (must be rejected)
  interaction    handlers + click/type/Tab/resize/rebuild with assertions
  mutation       one recorded edit applied to an executed scenario
  regression     minimized cases saved under tools/audit/regressions
"""
from __future__ import annotations

import copy
import hashlib
import itertools
import json
import random
from pathlib import Path

from .catalog import COMPONENTS, INPUT_TYPES, PROPERTIES, TEXT_SAMPLES

GENERATOR_VERSION = "1.0.0"
REGRESSIONS = Path(__file__).resolve().parents[1] / "regressions"

LEAF_TYPES = ["text", "inline_text", "heading", "button", "link", "input",
              "checkbox", "textarea", "select", "spacer"]
BOX_TYPES = ["container", "row", "column", "grid", "scroll", "stack", "form"]
TEXT_TYPES = [t for t, s in COMPONENTS.items() if s.get("text")]
# Properties meaningful on any element; layout-container ones are added to
# boxes only so a scenario does not spend its budget on no-op declarations.
COMMON_PROPS = ["width", "height", "padding", "margin", "border",
                "border-radius", "box-sizing", "background-color", "color",
                "opacity", "font-size", "font-weight", "font-family",
                "line-height", "letter-spacing", "text-align", "display",
                "white-space", "visibility", "max-width", "min-height",
                "text-transform", "box-shadow", "overflow", "word-break",
                "font-style", "text-decoration-line", "vertical-align",
                "position", "top", "left", "z-index", "transform",
                "min-width", "max-height", "overflow-wrap", "text-overflow",
                "aspect-ratio"]
FLEX_PROPS = ["flex-direction", "flex-wrap", "justify-content", "align-items",
              "gap"]
FLEX_ITEM_PROPS = ["flex-grow", "flex-shrink", "flex-basis", "align-self",
                   "order"]
GRID_PROPS = ["grid-template-columns", "gap", "align-items"]


def content_hash(scenario: dict) -> str:
    key = {k: scenario.get(k) for k in ("screen", "environment", "actions")}
    return hashlib.sha1(json.dumps(key, sort_keys=True).encode()).hexdigest()


def _finish(family: str, sub: str, seed, screen: dict, *, category="valid",
            objective: str, actions=None, assertions=None, env=None,
            tags=None, source=None, expected=None) -> dict:
    env = {"viewport_width": 360, "viewport_height": 640, "wait_ms": 300,
           **(env or {})}
    scenario = {
        "schema_version": "1.0",
        "scenario_id": "",
        "title": f"{family}/{sub}",
        "category": category,
        "family": family,
        "objective": objective,
        "source": source or {"kind": "generator", "generator": family,
                             "generator_version": GENERATOR_VERSION,
                             "parent": None, "mutations": []},
        "seed": seed,
        "screen": screen,
        "environment": env,
        "preconditions": [],
        "actions": actions or [],
        "assertions": assertions or [],
        "expected": expected or {
            "no_crash": True, "no_script_errors": True,
            "reference_parity": True,
            "lifecycle_stable": any(a["op"] == "rebuild" for a in actions or []),
        },
        "limits": {"max_nodes": 5000, "max_depth": 200, "max_ms": 20000,
                   "max_rss_growth_kb": 262144},
        "tags": [],
    }
    scenario["scenario_id"] = f"{family}.{_slug(sub)}.{content_hash(scenario)[:10]}"
    scenario["tags"] = sorted(set(tags or []) | set(features_tags(scenario)))
    return scenario


def _slug(value: str) -> str:
    out = "".join(c if c.isalnum() else "_" for c in value.lower()).strip("_")
    return out[:48] or "x"


class _Ids:
    def __init__(self):
        self.counts: dict[str, int] = {}

    def __call__(self, kind: str) -> str:
        self.counts[kind] = self.counts.get(kind, 0) + 1
        return f"{kind}_{self.counts[kind]}"


def _leaf(kind: str, ids: _Ids, rng: random.Random, text_class: str | None = None) -> dict:
    node = {"type": kind, "id": ids(kind)}
    if COMPONENTS[kind].get("text"):
        cls = text_class or rng.choice(["short", "short", "medium", "unicode"])
        node["text"] = rng.choice(TEXT_SAMPLES[cls])
    if kind == "input":
        node["attrs"] = {"input_type": rng.choice(INPUT_TYPES),
                         "placeholder": rng.choice(["Nombre", "", "email@x"])}
    if kind == "select":
        node["attrs"] = {"options": ["Uno", "Dos", "Tres"]}
    if kind == "spacer":
        node["style"] = {"width": "40px", "height": "20px",
                         "background-color": "#88aacc"}
    return node


def _value(rng: random.Random, prop: str, domain: str = "valid") -> str:
    values = PROPERTIES[prop].get(domain) or PROPERTIES[prop]["valid"]
    return rng.choice(values)


# ------------------------------------------------------------------ basic
def basic(index: int) -> dict:
    """Enumerates (component, property, value) triples in a fixed order."""
    triples = [(kind, prop, value)
               for kind in LEAF_TYPES + BOX_TYPES
               for prop in COMMON_PROPS
               for value in PROPERTIES[prop]["valid"]]
    kind, prop, value = triples[index % len(triples)]
    rng = random.Random(index)
    ids = _Ids()
    if kind in BOX_TYPES:
        target = {"type": kind, "id": ids(kind), "style": {prop: value},
                  "children": [_leaf("text", ids, rng, "medium"),
                               _leaf("button", ids, rng, "short")]}
    else:
        target = _leaf(kind, ids, rng)
        target.setdefault("style", {})[prop] = value
    screen = {"type": "screen", "id": "screen_main",
              "children": [{"type": "container", "id": "frame",
                            "style": {"width": "300px", "padding": "8px"},
                            "children": [target]}]}
    return _finish("basic", f"{kind}_{prop}", index, screen,
                   objective=f"'{kind}' with {prop}: {value} matches the reference "
                             "in computed style and geometry",
                   tags=[kind, prop])


def basic_size() -> int:
    return sum(len(PROPERTIES[p]["valid"]) for p in COMMON_PROPS) * len(LEAF_TYPES + BOX_TYPES)


# ---------------------------------------------------------- combinatorial
PAIRWISE_FACTORS: dict[str, list] = {
    "container": ["container", "row", "column", "grid", "scroll", "stack"],
    "child": ["text", "button", "input", "heading", "inline_text", "checkbox"],
    "width": ["auto", "120px", "50%", "fit-content"],
    "padding": ["0px", "8px 12px", "5%"],
    "border": ["none", "1px solid #333333", "4px double #0055aa"],
    "box-sizing": ["content-box", "border-box"],
    "font-size": ["12px", "16px", "1.5em"],
    "text": ["short", "long", "unicode", "unbreakable"],
    "align": ["flex-start", "center", "stretch"],
    "white-space": ["normal", "nowrap"],
    "overflow": ["visible", "hidden"],
    "viewport": [240, 360, 800],
}


def pairwise_rows(factors: dict[str, list], strength: int = 2, seed: int = 0) -> list[dict]:
    """Greedy covering array (AETG-style): every value pair of every two
    factors appears in at least one row. Deterministic for a seed."""
    names = list(factors)
    rng = random.Random(seed)
    uncovered = set()
    for combo in itertools.combinations(range(len(names)), strength):
        for values in itertools.product(*(range(len(factors[names[i]])) for i in combo)):
            uncovered.add(tuple(zip(combo, values)))
    rows = []
    while uncovered:
        best, best_gain = None, -1
        for _ in range(40):
            seed_pair = rng.choice(sorted(uncovered))
            row = [None] * len(names)
            for i, v in seed_pair:
                row[i] = v
            order = [i for i in range(len(names)) if row[i] is None]
            rng.shuffle(order)
            for i in order:
                scores = []
                for v in range(len(factors[names[i]])):
                    row[i] = v
                    gain = sum(1 for combo in itertools.combinations(
                        [j for j in range(len(names)) if row[j] is not None], strength)
                        if i in combo and tuple((j, row[j]) for j in combo) in uncovered)
                    scores.append((gain, -v))
                row[i] = -max(scores)[1]
            gain = sum(1 for combo in itertools.combinations(range(len(names)), strength)
                       if tuple((j, row[j]) for j in combo) in uncovered)
            if gain > best_gain:
                best, best_gain = list(row), gain
        for combo in itertools.combinations(range(len(names)), strength):
            uncovered.discard(tuple((j, best[j]) for j in combo))
        rows.append({names[i]: factors[names[i]][best[i]] for i in range(len(names))})
    return rows


_PAIRWISE_CACHE: dict[int, list[dict]] = {}


def combinatorial(index: int, strength: int = 2) -> dict:
    rows = _PAIRWISE_CACHE.get(strength)
    if rows is None:
        rows = _PAIRWISE_CACHE[strength] = pairwise_rows(PAIRWISE_FACTORS, strength)
    row = rows[index % len(rows)]
    rng = random.Random(index)
    ids = _Ids()
    child_style = {"font-size": row["font-size"], "white-space": row["white-space"]}
    children = []
    for _ in range(3):
        child = _leaf(row["child"], ids, rng, row["text"] if COMPONENTS[row["child"]].get("text") else None)
        child.setdefault("style", {}).update(child_style)
        children.append(child)
    box_style = {"width": row["width"], "padding": row["padding"],
                 "border": row["border"], "box-sizing": row["box-sizing"],
                 "overflow": row["overflow"]}
    if row["container"] in ("row", "column", "grid"):
        box_style["align-items"] = row["align"]
    if row["container"] == "grid":
        box_style["grid-template-columns"] = "1fr 1fr"
    if row["container"] == "scroll":
        box_style["height"] = "80px"
    box = {"type": row["container"], "id": ids(row["container"]),
           "style": box_style, "children": children}
    screen = {"type": "screen", "id": "screen_main", "children": [box]}
    return _finish("combinatorial", f"pairwise_{index % len(rows)}", index, screen,
                   env={"viewport_width": row["viewport"]},
                   objective="pairwise interaction of " + ", ".join(
                       f"{k}={v}" for k, v in row.items()),
                   tags=[f"pairwise:{strength}"])


def combinatorial_size(strength: int = 2) -> int:
    rows = _PAIRWISE_CACHE.get(strength)
    if rows is None:
        rows = _PAIRWISE_CACHE[strength] = pairwise_rows(PAIRWISE_FACTORS, strength)
    return len(rows)


# ----------------------------------------------------------------- random
def _random_tree(rng, ids, depth, max_depth, fanout, domain_mix):
    if depth >= max_depth or rng.random() < 0.3:
        node = _leaf(rng.choice(LEAF_TYPES), ids, rng)
        props = rng.sample(COMMON_PROPS, rng.randint(0, 3))
    else:
        kind = rng.choice(BOX_TYPES)
        node = {"type": kind, "id": ids(kind), "children": [
            _random_tree(rng, ids, depth + 1, max_depth, fanout, domain_mix)
            for _ in range(rng.randint(1, fanout))]}
        props = rng.sample(COMMON_PROPS, rng.randint(0, 3))
        if kind in ("row", "column"):
            props += rng.sample(FLEX_PROPS, rng.randint(0, 2))
        if kind == "grid":
            props += ["grid-template-columns"]
    style = {}
    for prop in props:
        domain = rng.choices(["valid", "boundary"], domain_mix)[0]
        style[prop] = _value(rng, prop, domain)
    if style:
        node["style"] = {**node.get("style", {}), **style}
    return node


def random_screen(seed: int) -> dict:
    rng = random.Random(seed)
    ids = _Ids()
    screen = {"type": "screen", "id": "screen_main", "children": [
        _random_tree(rng, ids, 1, rng.randint(2, 5), rng.randint(2, 4), [0.85, 0.15])
        for _ in range(rng.randint(1, 3))]}
    return _finish("random", "tree", seed, screen,
                   env={"viewport_width": rng.choice([240, 320, 360, 414, 800])},
                   objective="seeded random tree from valid and boundary values "
                             "matches the reference")


# ------------------------------------------------------------ adversarial
ADVERSARIAL_KINDS = ["deep", "wide", "huge_text", "unicode", "boundary",
                     "empty", "dense_grid", "tiny_viewport"]


def adversarial(index: int) -> dict:
    kind = ADVERSARIAL_KINDS[index % len(ADVERSARIAL_KINDS)]
    rng = random.Random(index)
    ids = _Ids()
    env = {}
    category = "boundary"
    if kind == "deep":
        depth = 20 + (index // len(ADVERSARIAL_KINDS)) % 60
        node = _leaf("text", ids, rng, "short")
        for _ in range(depth):
            node = {"type": "container", "id": ids("container"),
                    "style": {"padding": "1px"}, "children": [node]}
        children = [node]
    elif kind == "wide":
        count = 50 + (index * 37) % 250
        children = [{"type": "row", "id": "wide_row", "style": {"flex-wrap": "wrap"},
                     "children": [_leaf("button", ids, rng, "short") for _ in range(count)]}]
    elif kind == "huge_text":
        children = [{"type": "text", "id": "huge", "text": TEXT_SAMPLES["long"][0] * 8,
                     "style": {"width": rng.choice(["80px", "200px", "auto"])}}]
    elif kind == "unicode":
        children = [_leaf("text", ids, rng, "unicode"), _leaf("button", ids, rng, "unicode"),
                    _leaf("text", ids, rng, "special"), _leaf("text", ids, rng, "unbreakable")]
        for c in children:
            c["style"] = {"width": "150px", "overflow-wrap": rng.choice(["normal", "anywhere"])}
    elif kind == "boundary":
        target = _leaf(rng.choice(LEAF_TYPES), ids, rng)
        props = rng.sample([p for p in COMMON_PROPS if PROPERTIES[p].get("boundary")], 3)
        target["style"] = {p: _value(rng, p, "boundary") for p in props}
        children = [target]
    elif kind == "empty":
        children = [{"type": "container", "id": "empty_box"},
                    {"type": "text", "id": "empty_text", "text": ""},
                    {"type": "row", "id": "empty_row", "style": {"gap": "10px"}}]
    elif kind == "dense_grid":
        cols = 3 + index % 9
        children = [{"type": "grid", "id": "dense",
                     "style": {"grid-template-columns": f"repeat({cols}, 1fr)", "gap": "2px"},
                     "children": [_leaf(rng.choice(["text", "button", "spacer"]), ids, rng, "short")
                                  for _ in range(cols * 6)]}]
    else:  # tiny_viewport
        env = {"viewport_width": rng.choice([1, 20, 50]), "viewport_height": 100}
        children = [_leaf("text", ids, rng, "medium"), _leaf("input", ids, rng)]
    screen = {"type": "screen", "id": "screen_main", "children": children}
    return _finish("adversarial", kind, index, screen, category=category, env=env,
                   objective=f"adversarial '{kind}' screen renders without crash "
                             "and matches the reference",
                   tags=[f"adversarial:{kind}"])


# ---------------------------------------------------------------- invalid
def invalid_content(index: int) -> dict:
    rng = random.Random(index)
    props = [p for p in COMMON_PROPS if PROPERTIES[p].get("invalid")]
    prop = props[index % len(props)]
    ids = _Ids()
    target = _leaf(rng.choice(["text", "button", "heading", "input"]), ids, rng)
    good = _value(rng, prop, "valid")
    bad = _value(rng, prop, "invalid")
    # A valid declaration first, the invalid one after: the cascade must keep
    # the valid value, exactly like the reference.
    target["style"] = {prop: good}
    screen = {"type": "screen", "id": "screen_main", "children": [
        {"type": "container", "id": "frame", "style": {"width": "300px"}, "children": [target]}]}
    scenario = _finish("invalid", f"{prop}", index, screen, category="invalid_content",
                       env={"extra_css": f"#{target['id']} {{ {prop}: {bad}; }}"},
                       objective=f"invalid '{prop}: {bad}' is dropped and '{good}' wins",
                       tags=[prop, "invalid_css"])
    return scenario


SCHEMA_BREAKS = ["missing_id", "duplicate_id", "unknown_type", "children_on_leaf",
                 "bad_action_target", "bad_viewport", "wrong_type", "unknown_field",
                 "nested_screen", "image_not_executable"]


def schema_invalid(index: int) -> dict:
    """A scenario that must be rejected by `check_scenario` before running."""
    base = basic(index)
    broken = copy.deepcopy(base)
    kind = SCHEMA_BREAKS[index % len(SCHEMA_BREAKS)]
    target = broken["screen"]["children"][0]["children"][0]
    if kind == "missing_id":
        del target["id"]
    elif kind == "duplicate_id":
        broken["screen"]["children"][0]["children"].append(copy.deepcopy(target))
    elif kind == "unknown_type":
        target["type"] = "carousel"
    elif kind == "children_on_leaf":
        broken["screen"]["children"][0]["children"] = [
            {"type": "text", "id": "leaf", "text": "x",
             "children": [{"type": "text", "id": "inner"}]}]
    elif kind == "bad_action_target":
        broken["actions"] = [{"op": "click", "target": "does_not_exist"}]
    elif kind == "bad_viewport":
        broken["environment"]["viewport_width"] = -5
    elif kind == "wrong_type":
        broken["environment"]["wait_ms"] = "300"
    elif kind == "unknown_field":
        broken["colour_scheme"] = "dark"
    elif kind == "nested_screen":
        target["type"] = "screen"
    else:
        target["type"] = "image"
    broken["category"] = "schema_invalid"
    broken["family"] = "basic"
    broken["objective"] = f"validator rejects '{kind}'"
    broken["scenario_id"] = f"schema_invalid.{kind}.{index:06d}"
    broken["tags"] = sorted(set(broken.get("tags", [])) | {f"schema:{kind}"})
    return broken


# ------------------------------------------------------------ interaction
INTERACTION_KINDS = ["counter", "typing", "tab_order", "toggle", "resize", "rebuild",
                     "dynamic_append", "style_update", "checkbox", "repeated_clicks"]


def interaction(index: int) -> dict:
    kind = INTERACTION_KINDS[index % len(INTERACTION_KINDS)]
    rng = random.Random(index)
    ids = _Ids()
    actions, assertions = [], []
    counter = {"type": "text", "id": "counter", "text": "0"}
    button = {"type": "button", "id": "btn", "text": rng.choice(TEXT_SAMPLES["short"]),
              "style": {"padding": rng.choice(["4px 12px", "10px", "0px"])},
              "on": {"click": [{"do": "increment", "target": "counter"}]}}
    field = {"type": "input", "id": "field", "attrs": {"input_type": "text"}}
    second = {"type": "button", "id": "btn2", "text": "Dos"}
    children = [{"type": "row", "id": "bar", "style": {"gap": "8px", "align-items": "center"},
                 "children": [button, counter]}, field, second]
    env = {}
    if kind == "counter":
        actions = [{"op": "click", "target": "btn"}]
        assertions = [{"id": "a_count", "target": "counter", "property": "text",
                       "operator": "equals", "expected": "1", "oracle": "absolute"}]
    elif kind == "repeated_clicks":
        n = 2 + index % 5
        actions = [{"op": "click", "target": "btn"} for _ in range(n)]
        assertions = [{"id": "a_count", "target": "counter", "property": "text",
                       "operator": "equals", "expected": str(n), "oracle": "absolute"}]
    elif kind == "typing":
        text = rng.choice(["hola", "Ñandú 123", "a" * 40, ""])
        actions = [{"op": "type", "target": "field", "text": text}]
        assertions = [{"id": "a_value", "target": "field", "property": "value",
                       "operator": "equals", "expected": text, "oracle": "absolute"},
                      {"id": "a_focus", "target": "field", "property": "focused",
                       "operator": "equals", "expected": True, "oracle": "absolute"}]
    elif kind == "tab_order":
        actions = [{"op": "click", "target": "field"}, {"op": "key", "key": "Tab"}]
        assertions = [{"id": "a_focus", "target": "btn2", "property": "focused",
                       "operator": "equals", "expected": True, "oracle": "absolute"}]
    elif kind == "toggle":
        button["on"] = {"click": [{"do": "toggle_hidden", "target": "field"}]}
        actions = [{"op": "click", "target": "btn"}]
        assertions = [{"id": "a_hidden", "target": "field", "property": "visible",
                       "operator": "equals", "expected": False, "oracle": "absolute"}]
    elif kind == "resize":
        env = {"viewport_width": 800}
        children[0]["style"]["flex-wrap"] = "wrap"
        actions = [{"op": "resize", "width": 240, "height": 640},
                   {"op": "resize", "width": 800, "height": 640}]
    elif kind == "rebuild":
        actions = [{"op": "click", "target": "btn"}, {"op": "rebuild"}]
        assertions = [{"id": "a_reset", "target": "counter", "property": "text",
                       "operator": "equals", "expected": "0", "oracle": "absolute"}]
    elif kind == "dynamic_append":
        button["on"] = {"click": [{"do": "append_text", "target": "list_box",
                                   "text": "Nuevo elemento"}]}
        children.append({"type": "column", "id": "list_box", "style": {"gap": "4px"},
                         "children": [{"type": "text", "id": "seed_item", "text": "x"}]})
        actions = [{"op": "click", "target": "btn"}, {"op": "click", "target": "btn"}]
    elif kind == "style_update":
        prop = rng.choice(["width", "padding", "background-color", "font-size"])
        button["on"] = {"click": [{"do": "set_style", "target": "counter",
                                   "property": prop, "value": _value(rng, prop)}]}
        actions = [{"op": "click", "target": "btn"}]
    else:  # checkbox
        children.append({"type": "checkbox", "id": "check"})
        actions = [{"op": "click", "target": "check"}]
        assertions = [{"id": "a_checked", "target": "check", "property": "checked",
                       "operator": "equals", "expected": True, "oracle": "absolute"}]
    screen = {"type": "screen", "id": "screen_main",
              "style": {"padding": "8px"}, "children": children}
    return _finish("interaction", kind, index, screen, actions=actions,
                   assertions=assertions, env=env,
                   objective=f"interaction '{kind}': state, events and focus match "
                             "the assertions and the reference",
                   tags=[f"interaction:{kind}"])


# --------------------------------------------------------------- mutation
MUTATIONS = ["drop_property", "change_value", "boundary_value", "invalid_value",
             "duplicate_node", "reverse_children", "change_type", "wrap_node",
             "change_viewport", "add_rebuild", "long_text"]


def mutate(parent: dict, seed: int) -> dict:
    rng = random.Random(seed)
    child = copy.deepcopy(parent)
    nodes = []
    stack = [child["screen"]]
    while stack:
        n = stack.pop()
        nodes.append(n)
        stack.extend(n.get("children") or [])
    op = MUTATIONS[seed % len(MUTATIONS)]
    styled = [n for n in nodes if n.get("style")]
    non_root = nodes[1:]
    detail = {"op": op}
    if op in ("drop_property", "change_value", "boundary_value", "invalid_value") and styled:
        node = rng.choice(styled)
        prop = rng.choice(sorted(node["style"]))
        detail.update(node=node["id"], property=prop, before=node["style"][prop])
        if op == "drop_property":
            del node["style"][prop]
        elif prop in PROPERTIES:
            domain = {"change_value": "valid", "boundary_value": "boundary",
                      "invalid_value": "invalid"}[op]
            node["style"][prop] = _value(rng, prop, domain)
            if op == "invalid_value":
                child["category"] = "invalid_content"
        detail["after"] = node["style"].get(prop)
    elif op == "duplicate_node" and non_root:
        parent_nodes = [n for n in nodes if n.get("children")]
        holder = rng.choice(parent_nodes)
        clone = copy.deepcopy(rng.choice(holder["children"]))
        suffix = f"_d{seed % 1000}"
        for n in _all(clone):
            n["id"] = n["id"] + suffix
            n.pop("on", None)
        holder["children"].append(clone)
        detail.update(node=clone["id"])
    elif op == "reverse_children":
        holders = [n for n in nodes if len(n.get("children") or []) > 1]
        if holders:
            holder = rng.choice(holders)
            holder["children"].reverse()
            detail.update(node=holder["id"])
    elif op == "change_type" and non_root:
        node = rng.choice(non_root)
        if node.get("children"):
            node["type"] = rng.choice(BOX_TYPES)
        else:
            new = rng.choice([t for t in LEAF_TYPES if t not in ("input", "checkbox", "select")])
            node["type"] = new
            node.pop("attrs", None)
            if COMPONENTS[new].get("text"):
                node.setdefault("text", "Texto")
            else:
                node.pop("text", None)
        detail.update(node=node["id"], after=node["type"])
    elif op == "wrap_node" and non_root:
        holder = rng.choice([n for n in nodes if n.get("children")])
        i = rng.randrange(len(holder["children"]))
        wrapper_type = rng.choice(BOX_TYPES)
        holder["children"][i] = {"type": wrapper_type, "id": f"wrap_{seed % 100000}",
                                 "style": {"padding": _value(rng, "padding")},
                                 "children": [holder["children"][i]]}
        detail.update(node=f"wrap_{seed % 100000}", after=wrapper_type)
    elif op == "change_viewport":
        child["environment"]["viewport_width"] = rng.choice([120, 240, 320, 600, 1024])
        detail.update(after=child["environment"]["viewport_width"])
    elif op == "add_rebuild":
        child["actions"] = list(child.get("actions") or []) + [{"op": "rebuild"}]
        child["expected"]["lifecycle_stable"] = True
    else:  # long_text
        texty = [n for n in nodes if COMPONENTS[n["type"]].get("text")]
        if texty:
            node = rng.choice(texty)
            node["text"] = rng.choice(TEXT_SAMPLES["long"] + TEXT_SAMPLES["unbreakable"])
            detail.update(node=node["id"])
    if child.get("category") == "schema_invalid":
        child["category"] = "valid"
    child["family"] = "mutation"
    child["source"] = {"kind": "mutation", "generator": "mutation",
                       "generator_version": GENERATOR_VERSION,
                       "parent": parent["scenario_id"],
                       "mutations": list(parent.get("source", {}).get("mutations") or []) + [detail]}
    child["seed"] = seed
    child["objective"] = f"mutation {op} of {parent['scenario_id']}: {parent['objective']}"
    child["title"] = f"mutation/{op}"
    # Assertions that referenced a node a mutation renamed stay valid; ones
    # whose expected value depends on the parent screen are dropped.
    child["assertions"] = [a for a in child.get("assertions") or []
                           if op in ("change_viewport", "drop_property", "change_value")]
    child["scenario_id"] = f"mutation.{op}.{content_hash(child)[:10]}"
    child["tags"] = sorted(set(features_tags(child)) | {f"mutation:{op}"})
    return child


def _all(node):
    yield node
    for c in node.get("children") or []:
        yield from _all(c)


def regressions() -> list[dict]:
    out = []
    for path in sorted(REGRESSIONS.glob("*.json")):
        try:
            scenario = json.loads(path.read_text())
        except ValueError:
            continue
        scenario["family"] = "regression"
        out.append(scenario)
    return out


# --------------------------------------------------------------- features
def features(scenario: dict) -> set[str]:
    """Coverage features of a scenario (component, property, value class,
    property pairs, nesting, depth, actions, text classes, viewport)."""
    out: set[str] = {f"category:{scenario.get('category')}"}
    text_class = {s: k for k, vals in TEXT_SAMPLES.items() for s in vals}

    def visit(node, parent_type, depth):
        kind = node.get("type")
        out.add(f"type:{kind}")
        out.add(f"nest:{parent_type}>{kind}")
        out.add(f"depth:{min(depth, 10) if depth <= 10 else '10+'}")
        style = node.get("style") or {}
        for prop, value in style.items():
            out.add(f"prop:{prop}")
            out.add(f"prop_on:{kind}:{prop}")
            domain = PROPERTIES.get(prop, {})
            cls = next((d for d in ("valid", "boundary", "invalid")
                        if value in domain.get(d, [])), "other")
            out.add(f"value:{prop}={value}")
            out.add(f"class:{prop}:{cls}")
        for a, b in itertools.combinations(sorted(style), 2):
            out.add(f"pair:{a}+{b}")
        if parent_type in ("row", "column", "grid"):
            for prop in style:
                out.add(f"item:{parent_type}:{prop}")
        if "text" in node:
            out.add(f"text:{text_class.get(node['text'], 'other')}")
        for event in node.get("on") or {}:
            out.add(f"handler:{event}")
        for child in node.get("children") or []:
            visit(child, kind, depth + 1)

    if isinstance(scenario.get("screen"), dict):
        visit(scenario["screen"], "root", 1)
    for action in scenario.get("actions") or []:
        out.add(f"action:{action.get('op')}")
    ops = [a.get("op") for a in scenario.get("actions") or []]
    for a, b in zip(ops, ops[1:]):
        out.add(f"transition:{a}->{b}")
    width = (scenario.get("environment") or {}).get("viewport_width", 360)
    out.add(f"viewport:{'xs' if width < 200 else 's' if width < 400 else 'm' if width < 900 else 'l'}")
    return out


def features_tags(scenario: dict) -> list[str]:
    return sorted({f.split(":", 1)[1].split(":")[0] if f.startswith(("type:", "prop:")) else ""
                   for f in features(scenario)} - {""})


FAMILIES = {
    "basic": basic,
    "combinatorial": combinatorial,
    "random": random_screen,
    "adversarial": adversarial,
    "invalid": invalid_content,
    "schema_invalid": schema_invalid,
    "interaction": interaction,
}


def regenerate(family: str, seed: int) -> dict:
    return FAMILIES[family](seed)

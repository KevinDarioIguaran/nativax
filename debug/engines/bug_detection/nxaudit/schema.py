"""Scenario/report validation: a stdlib JSON Schema subset plus semantics.

The machine has no `jsonschema` package, so this implements the keywords the
two shipped schemas use (type, enum, const, required, properties,
additionalProperties, pattern, min/maxLength, minimum/maximum, items,
maxItems, maxProperties, uniqueItems, local `$ref`). `test_schema` checks the
validator itself against valid and broken documents.
"""
from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

from .catalog import ACTIONS, COMPONENTS

SCHEMAS = Path(__file__).resolve().parents[1] / "schemas"
SCENARIO_SCHEMA_VERSION = "1.0"
REPORT_VERSION = "1.0"

_TYPES = {
    "object": dict, "array": list, "string": str, "boolean": bool,
    "null": type(None),
}


@lru_cache(maxsize=None)
def load_schema(name: str) -> dict:
    return json.loads((SCHEMAS / f"{name}.schema.json").read_text())


def _is_type(value, name: str) -> bool:
    if name == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return isinstance(value, _TYPES[name])


def validate(value, schema: dict, root: dict | None = None, path: str = "$") -> list[str]:
    """Returns a list of `path: message` errors (empty when valid)."""
    root = root or schema
    errors: list[str] = []
    if "$ref" in schema:
        ref = schema["$ref"]
        target = root
        for part in ref.lstrip("#/").split("/"):
            target = target[part]
        return validate(value, target, root, path)
    if "const" in schema and value != schema["const"]:
        errors.append(f"{path}: expected {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} not in enum")
    if "type" in schema:
        names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_is_type(value, n) for n in names):
            return errors + [f"{path}: expected {'/'.join(names)}"]
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{path}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(f"{path}: longer than {schema['maxLength']}")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append(f"{path}: does not match {schema['pattern']}")
    if _is_type(value, "number"):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: below {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: above {schema['maximum']}")
    if isinstance(value, list):
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{path}: more than {schema['maxItems']} items")
        if schema.get("uniqueItems"):
            seen = [json.dumps(v, sort_keys=True) for v in value]
            if len(seen) != len(set(seen)):
                errors.append(f"{path}: items not unique")
        if "items" in schema:
            for index, item in enumerate(value):
                errors += validate(item, schema["items"], root, f"{path}[{index}]")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing required '{key}'")
        if "maxProperties" in schema and len(value) > schema["maxProperties"]:
            errors.append(f"{path}: more than {schema['maxProperties']} properties")
        props = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for key, item in value.items():
            if key in props:
                errors += validate(item, props[key], root, f"{path}.{key}")
            elif extra is False:
                errors.append(f"{path}: unknown property '{key}'")
            elif isinstance(extra, dict):
                errors += validate(item, extra, root, f"{path}.{key}")
    return errors


def semantic_errors(scenario: dict) -> list[str]:
    """Rules JSON Schema cannot express: ids, targets, structure, limits."""
    errors: list[str] = []
    screen = scenario.get("screen")
    if not isinstance(screen, dict):
        return ["$.screen: not an object"]
    if screen.get("type") != "screen":
        errors.append("$.screen.type: root must be 'screen'")
    ids: dict[str, str] = {}
    count = 0
    max_depth = 0

    def visit(node, path, depth):
        nonlocal count, max_depth
        if not isinstance(node, dict):
            errors.append(f"{path}: not an object")
            return
        count += 1
        max_depth = max(max_depth, depth)
        node_id = node.get("id")
        if node_id in ids:
            errors.append(f"{path}.id: duplicate id '{node_id}' (first at {ids[node_id]})")
        elif isinstance(node_id, str):
            ids[node_id] = path
        spec = COMPONENTS.get(node.get("type"))
        children = node.get("children") or []
        if spec is not None:
            if children and not spec["container"]:
                errors.append(f"{path}: '{node['type']}' cannot have children")
            if not spec["executable"]:
                errors.append(f"{path}: '{node['type']}' is not executable: {spec['reason']}")
            allowed = spec.get("child_types")
            for i, child in enumerate(children):
                if allowed and isinstance(child, dict) and child.get("type") not in allowed:
                    errors.append(f"{path}.children[{i}]: '{node['type']}' only takes {allowed}")
            if node.get("type") == "screen" and path != "screen":
                errors.append(f"{path}: nested 'screen'")
        for i, child in enumerate(children if isinstance(children, list) else []):
            visit(child, f"{path}.children[{i}]", depth + 1)

    visit(screen, "screen", 1)
    for event, steps in _handlers(screen):
        for step in steps:
            target = step.get("target")
            if target is not None and target not in ids:
                errors.append(f"handler {event}: unknown target '{target}'")
    for index, action in enumerate(scenario.get("actions") or []):
        spec = ACTIONS.get(action.get("op"))
        if spec and spec["needs_target"] and action.get("target") not in ids:
            errors.append(f"$.actions[{index}]: unknown target '{action.get('target')}'")
        if action.get("op") == "resize" and not ("width" in action and "height" in action):
            errors.append(f"$.actions[{index}]: resize needs width and height")
    for index, assertion in enumerate(scenario.get("assertions") or []):
        if assertion.get("target") not in ids and assertion.get("target") != "$document":
            errors.append(f"$.assertions[{index}]: unknown target '{assertion.get('target')}'")
        if assertion.get("property") == "style" and not assertion.get("style_property"):
            errors.append(f"$.assertions[{index}]: style assertion needs style_property")
    limits = scenario.get("limits") or {}
    if count > limits.get("max_nodes", 5000):
        errors.append(f"$.screen: {count} nodes exceed limits.max_nodes")
    if max_depth > limits.get("max_depth", 200):
        errors.append(f"$.screen: depth {max_depth} exceeds limits.max_depth")
    return errors


def _handlers(screen: dict):
    stack = [screen]
    while stack:
        node = stack.pop()
        if not isinstance(node, dict):
            continue
        for event, steps in (node.get("on") or {}).items():
            yield event, steps if isinstance(steps, list) else []
        stack.extend(node.get("children") or [])


def check_scenario(scenario) -> list[str]:
    errors = validate(scenario, load_schema("scenario"))
    if isinstance(scenario, dict):
        errors += semantic_errors(scenario)
    return errors


def check_report(report) -> list[str]:
    return validate(report, load_schema("report"))

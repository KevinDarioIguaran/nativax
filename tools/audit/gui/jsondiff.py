"""Structural JSON diff for the audit GUI.

Objects are compared by key (key order is not a change). Lists of objects
that carry an `id` (component trees) are matched by id, so a moved component
is reported as `moved` instead of a cascade of changes; other lists are
compared by position. Paths use the engine's notation (`$.screen.children[0]`).
"""
from __future__ import annotations

ADDED, REMOVED, CHANGED, MOVED, TYPE = "added", "removed", "changed", "moved", "type_changed"


def _kind(v):
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, (int, float)):
        return "number"
    return type(v).__name__


def diff(a, b, path: str = "$") -> list[dict]:
    out: list[dict] = []
    _diff(a, b, path, out)
    return out


def _diff(a, b, path, out):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in a:
            if k not in b:
                out.append({"path": f"{path}.{k}", "op": REMOVED, "before": a[k], "after": None})
        for k in b:
            if k not in a:
                out.append({"path": f"{path}.{k}", "op": ADDED, "before": None, "after": b[k]})
            else:
                _diff(a[k], b[k], f"{path}.{k}", out)
        return
    if isinstance(a, list) and isinstance(b, list):
        if _by_id(a) and _by_id(b):
            ia = {x["id"]: i for i, x in enumerate(a)}
            ib = {x["id"]: i for i, x in enumerate(b)}
            for key, i in ia.items():
                if key not in ib:
                    out.append({"path": f"{path}[{i}]", "op": REMOVED, "before": a[i], "after": None,
                                "id": key})
            for key, j in ib.items():
                if key not in ia:
                    out.append({"path": f"{path}[{j}]", "op": ADDED, "before": None, "after": b[j], "id": key})
                    continue
                i = ia[key]
                if i != j:
                    out.append({"path": f"{path}[{j}]", "op": MOVED, "before": i, "after": j, "id": key})
                _diff(a[i], b[j], f"{path}[{j}]", out)
            return
        for i in range(max(len(a), len(b))):
            if i >= len(a):
                out.append({"path": f"{path}[{i}]", "op": ADDED, "before": None, "after": b[i]})
            elif i >= len(b):
                out.append({"path": f"{path}[{i}]", "op": REMOVED, "before": a[i], "after": None})
            else:
                _diff(a[i], b[i], f"{path}[{i}]", out)
        return
    if _kind(a) != _kind(b):
        out.append({"path": path, "op": TYPE, "before": a, "after": b})
    elif a != b:
        out.append({"path": path, "op": CHANGED, "before": a, "after": b})


def _by_id(items) -> bool:
    return bool(items) and all(isinstance(x, dict) and isinstance(x.get("id"), str) for x in items) \
        and len({x["id"] for x in items}) == len(items)


def summarize(changes: list[dict]) -> dict:
    out = {ADDED: 0, REMOVED: 0, CHANGED: 0, MOVED: 0, TYPE: 0}
    for c in changes:
        out[c["op"]] += 1
    return out


def to_nx_path(path: str) -> str | None:
    """`$.screen.children[0].style.width` -> `screen.children[0]` (the node)."""
    if not path.startswith("$.screen"):
        return None
    tail = path[2:]
    node = "screen"
    rest = tail[len("screen"):]
    while rest.startswith(".children["):
        end = rest.index("]") + 1
        node += rest[:end]
        rest = rest[end:]
    return node

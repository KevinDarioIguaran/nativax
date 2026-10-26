"""Test-case reduction that keeps the defect fingerprint.

Each round builds every one-step reduction of the current case (drop a
subtree, a declaration, a handler, an action, halve a text, drop extra CSS),
runs them all in ONE batch per engine and keeps the smallest candidate whose
comparison still yields the same issue fingerprint. It stops when no
candidate reproduces (1-minimal w.r.t. these units) or the round budget is
spent. Units whose removal lost the fingerprint in the final round are the
`necessary_conditions` the diagnosis cites as evidence.
"""
from __future__ import annotations

import copy

from .generate import content_hash


def size(scenario: dict) -> int:
    n = 0
    stack = [scenario["screen"]]
    while stack:
        node = stack.pop()
        n += 1 + len(node.get("style") or {}) + len(node.get("on") or {})
        n += len(node.get("text") or "") // 16
        stack.extend(node.get("children") or [])
    return n + 2 * len(scenario.get("actions") or []) + (1 if scenario["environment"].get("extra_css") else 0)


def _nodes(screen, path="screen"):
    yield path, screen
    for i, c in enumerate(screen.get("children") or []):
        yield from _nodes(c, f"{path}.children[{i}]")


def _get(screen, path):
    for p, n in _nodes(screen):
        if p == path:
            return n
    return None


def units(scenario: dict, keep_ids: set[str]) -> list[dict]:
    """Removable units, keyed by node id so they stay valid after other
    removals. Nodes in `keep_ids` (the element the issue is about) and nodes
    that actions target are never removed."""
    screen = scenario["screen"]
    referenced = set(keep_ids)
    for a in scenario.get("actions") or []:
        if a.get("target"):
            referenced.add(a["target"])
    out = []
    for path, node in _nodes(screen):
        if path != "screen" and not ({n.get("id") for _, n in _nodes(node)} & referenced):
            out.append({"unit": "node", "id": node.get("id"),
                        "description": f"node {node.get('id')} ({node.get('type')}) at {path}"})
    for path, node in _nodes(screen):
        for prop in node.get("style") or {}:
            out.append({"unit": "style", "id": node.get("id"), "property": prop,
                        "description": f"{node.get('id')} {{{prop}: {node['style'][prop]}}}"})
        for event in node.get("on") or {}:
            out.append({"unit": "handler", "id": node.get("id"), "event": event,
                        "description": f"{node.get('id')} on {event}"})
        text = node.get("text")
        if text and len(text) > 2:
            out.append({"unit": "text", "id": node.get("id"),
                        "description": f"text of {node.get('id')} ({len(text)} chars)"})
    for i, a in enumerate(scenario.get("actions") or []):
        out.append({"unit": "action", "index": i, "description": f"action {i} {a.get('op')}"})
    if scenario["environment"].get("extra_css"):
        out.append({"unit": "css", "description": f"extra CSS {scenario['environment']['extra_css'][:80]}"})
    return out


def _key(u):
    return (u["unit"], u.get("id"), u.get("property"), u.get("event"), u.get("index"))


def apply(scenario: dict, removals: list[dict]) -> dict:
    """A copy of `scenario` with every unit in `removals` applied."""
    cand = copy.deepcopy(scenario)
    by_id = {n.get("id"): (p, n) for p, n in _nodes(cand["screen"])}
    drop_actions = set()
    for u in removals:
        kind = u["unit"]
        if kind == "node":
            for _, n in _nodes(cand["screen"]):
                kids = n.get("children") or []
                if any(k.get("id") == u["id"] for k in kids):
                    n["children"] = [k for k in kids if k.get("id") != u["id"]]
                    break
        elif kind in ("style", "handler", "text") and u.get("id") in by_id:
            node = by_id[u["id"]][1]
            if kind == "style":
                (node.get("style") or {}).pop(u["property"], None)
            elif kind == "handler":
                (node.get("on") or {}).pop(u["event"], None)
            elif node.get("text"):
                node["text"] = node["text"][: len(node["text"]) // 2]
        elif kind == "action":
            drop_actions.add(u["index"])
        elif kind == "css":
            cand["environment"].pop("extra_css", None)
    if drop_actions:
        cand["actions"] = [a for i, a in enumerate(cand.get("actions") or []) if i not in drop_actions]
    return _clean(cand)


def reductions(scenario: dict, keep_ids: set[str]):
    """Yields (unit, candidate) for every single one-step reduction."""
    for u in units(scenario, keep_ids):
        yield u, apply(scenario, [u])


def _clean(cand):
    # Assertions about removed nodes or removed actions no longer apply.
    ids = {n.get("id") for _, n in _nodes(cand["screen"])}
    cand["assertions"] = [a for a in cand.get("assertions") or [] if a.get("target") in ids]
    for _, node in _nodes(cand["screen"]):
        for event, steps in list((node.get("on") or {}).items()):
            node["on"][event] = [s for s in steps if s.get("target") in (None, *ids)]
        if node.get("style") == {}:
            node.pop("style")
        if node.get("on") == {}:
            node.pop("on")
    cand["expected"]["lifecycle_stable"] = any(a.get("op") == "rebuild" for a in cand.get("actions") or [])
    return cand


def minimize(scenario: dict, fp: str, evaluate, keep_ids: set[str], *, max_rounds: int = 10,
             max_candidates: int = 80, log=print) -> dict:
    """`evaluate(list[scenario]) -> {scenario_id: set(fingerprints)}`."""
    current = copy.deepcopy(scenario)
    start_size = size(current)
    removed, rounds, last_failed, one_minimal = [], 0, [], False
    reproduced = fp in evaluate([current]).get(current["scenario_id"], set())
    if not reproduced:
        return {"reproduced": False, "rounds": 0, "start_size": start_size, "final_size": start_size,
                "scenario": current, "removed": [], "necessary_conditions": [],
                "note": "original scenario did not reproduce the fingerprint on re-run"}
    previous_good: list[dict] = []
    while rounds < max_rounds:
        rounds += 1
        available = {_key(u): u for u in units(current, keep_ids)}
        # Singles, plus the reductions that each worked last round applied
        # together (all, halves, quarters): large cuts in one batch.
        cands = [([u], apply(current, [u])) for u in available.values()]
        carry = [available[_key(u)] for u in previous_good
                 if _key(u) in available and u["unit"] != "action"]
        if len(carry) >= 2:
            n = len(carry)
            for chunk in (carry, carry[: n // 2], carry[n // 2:], carry[: n // 4], carry[n // 4: n // 2]):
                if len(chunk) >= 2:
                    cands.append((list(chunk), apply(current, list(chunk))))
        seen = set()
        unique = []
        for us, cand in cands:
            cand["scenario_id"] = f"minimized.{scenario['scenario_id'].split('.')[0]}.{content_hash(cand)[:10]}"
            if cand["scenario_id"] not in seen and size(cand) < size(current):
                seen.add(cand["scenario_id"])
                unique.append((us, cand))
        # Biggest reductions first so the budget goes to large cuts.
        unique.sort(key=lambda uc: size(uc[1]))
        cands = unique[:max_candidates]
        if not cands:
            one_minimal = True
            break
        verdict = evaluate([c for _, c in cands])
        good = [(us, c) for us, c in cands if fp in verdict.get(c["scenario_id"], set())]
        last_failed = [us[0] for us, c in cands if len(us) == 1 and fp not in verdict.get(c["scenario_id"], set())]
        log(f"[minimize] round {rounds}: {len(good)}/{len(cands)} reductions keep {fp[:60]}")
        if not good:
            one_minimal = True
            break
        previous_good = [us[0] for us, _ in good if len(us) == 1]
        us, best = min(good, key=lambda uc: size(uc[1]))
        removed.extend(us)
        current = best
    current["family"] = "minimized"
    current["source"] = {"kind": "minimization", "generator": "minimize",
                         "generator_version": scenario.get("source", {}).get("generator_version"),
                         "parent": scenario["scenario_id"], "mutations": removed}
    return {"reproduced": True, "rounds": rounds, "start_size": start_size, "final_size": size(current),
            "scenario": current, "removed": removed, "one_minimal": one_minimal,
            # Exact only when the last round found no reduction (one_minimal).
            "necessary_conditions": last_failed if one_minimal else []}

"""Deliberate-defect benchmark for the audit engine itself.

The "system under test" is a second, independent Chromium run with known
faults injected into its observations. Because the faults are known, the
benchmark measures what a real run cannot: how many defects the oracles
detect, whether the report points at the faulted element, and how many
issues appear where nothing was injected (false positives; this includes
any nondeterminism between two Chromium runs).
"""
from __future__ import annotations

import copy

from .generate import content_hash

# id -> (description, component type it applies to, expected finding kind,
#        expected property or None)
FAULTS = {
    "F1_button_width": ("first button is 6 px wider", "button", "geometry", "size"),
    "F2_text_color": ("first text has a wrong computed color", "text", "style", "color"),
    "F3_click_dropped": ("click events are not recorded after actions", None, "events", "events"),
    "F4_heading_missing": ("first heading is absent from the DOM", "heading", "missing", None),
    "F5_input_value": ("input value is not updated after typing", "input", "state", "value"),
    "F6_grid_crash": ("any grid container throws during layout", "grid", "crash", None),
    "F7_checkbox_toggle": ("checkbox does not toggle on click", "checkbox", "state", "checked"),
    "F8_padding_left": ("first row loses 4 px of left padding", "row", "style", "padding"),
}


def _types(scenario):
    out = []
    stack = [scenario["screen"]]
    while stack:
        n = stack.pop(0)
        out.append(n)
        stack = (n.get("children") or []) + stack
    return out


def applicable(scenario) -> list[str]:
    nodes = _types(scenario)
    kinds = {n["type"] for n in nodes}
    ops = {a.get("op") for a in scenario.get("actions") or []}
    out = []
    for fid, (_, comp, kind, _) in FAULTS.items():
        if fid == "F3_click_dropped":
            if "click" in ops:
                out.append(fid)
        elif fid == "F5_input_value":
            # Clearing an empty value changes nothing observable.
            if any(a.get("op") == "type" and a.get("text") for a in scenario.get("actions") or []):
                out.append(fid)
        elif fid == "F7_checkbox_toggle":
            if "checkbox" in kinds and "click" in ops:
                out.append(fid)
        elif comp in kinds:
            out.append(fid)
    return out


def choose(scenario) -> str | None:
    """Deterministic: ~70 % of applicable scenarios get one fault."""
    options = applicable(scenario)
    if not options:
        return None
    # Keyed by content, not id: the explorer reuses one observation for
    # scenarios with equal content and different ids, so an id-keyed choice
    # scored one fault against the observation injected with another.
    h = int(content_hash(scenario), 16)
    if h % 10 >= 7:
        return None
    return options[h % len(options)]


def target_id(scenario, fid) -> str | None:
    comp = FAULTS[fid][1]
    # A crash carries no element; it is localized by its stack, not by id.
    if comp is None or FAULTS[fid][2] == "crash":
        return None
    return next((n["id"] for n in _types(scenario) if n["type"] == comp), None)


def inject(scenario: dict, observation: dict, fid: str | None) -> dict:
    obs = copy.deepcopy(observation)
    if fid is None or obs.get("status") != "ok":
        return obs
    target = target_id(scenario, fid)
    if fid == "F6_grid_crash":
        obs["flutter_errors"] = [{"library": "rendering library",
                                  "summary": "Injected fault: grid layout threw",
                                  "context": "during performLayout()", "stack": []}]
        return obs
    for si, state in enumerate(obs.get("states") or []):
        probe = state.get("probe") or {}
        els = probe.get("elements") or []
        if fid == "F3_click_dropped" and si > 0:
            probe["events"] = [e for e in probe.get("events") or [] if not e.startswith("click:")]
        for el in list(els):
            if el.get("id") != target:
                continue
            if fid == "F1_button_width":
                el["rect"][2] = round(el["rect"][2] + 6, 1)
            elif fid == "F2_text_color":
                el["styles"]["color"] = "rgb(1, 2, 3)"
            elif fid == "F4_heading_missing":
                els.remove(el)
            elif fid == "F5_input_value" and si > 0:
                el["value"] = ""
            elif fid == "F7_checkbox_toggle" and si > 0:
                el["checked"] = not el.get("checked")
            elif fid == "F8_padding_left":
                el["styles"]["padding-left"] = "4px" if el["styles"].get("padding-left") != "4px" else "0px"
    return obs


def faulty_backend(chrome_fn):
    """A `nativa_fn` for Runner: an independent Chromium run plus faults."""
    def run(scenarios, work, log=print):
        base = chrome_fn(scenarios, work, log=log)
        return {sid: inject(next(s for s in scenarios if s["scenario_id"] == sid), obs,
                            choose(next(s for s in scenarios if s["scenario_id"] == sid)))
                for sid, obs in base.items()}
    return run


def score(results: list[dict]) -> dict:
    """Detection / localization / false-positive metrics over executed results."""
    per = {fid: {"injected": 0, "detected": 0, "localized": 0, "localizable": 0} for fid in FAULTS}
    clean_scenarios = clean_with_findings = 0
    unexpected = 0
    for r in results:
        scen = r["scenario"]
        fid = choose(scen)
        primaries = [f for f in r["comparison"]["findings"] if f.get("primary", True)
                     and f["kind"] != "oracle_conflict"]
        if fid is None:
            clean_scenarios += 1
            if primaries:
                clean_with_findings += 1
            unexpected += len(primaries)
            continue
        _, comp, kind, prop = FAULTS[fid]
        target = target_id(scen, fid)
        per[fid]["injected"] += 1
        hits = [f for f in primaries if f["kind"] == kind and (prop is None or f.get("property") == prop)]
        if hits:
            per[fid]["detected"] += 1
            if target is not None:
                per[fid]["localizable"] += 1
                if any(f.get("element_id") == target for f in hits):
                    per[fid]["localized"] += 1
        unexpected += len([f for f in primaries if f not in hits and not _is_assertion_echo(f, kind)])
    injected = sum(v["injected"] for v in per.values())
    detected = sum(v["detected"] for v in per.values())
    localized = sum(v["localized"] for v in per.values())
    localizable = sum(v["localizable"] for v in per.values())
    return {
        "faults": per,
        "injected": injected,
        "detected": detected,
        "localized": localized,
        "detection_rate": round(detected / injected, 3) if injected else None,
        "localizable": localizable,
        # Over detected faults that have a target element (crashes excluded).
        "localization_rate": round(localized / localizable, 3) if localizable else None,
        "clean_scenarios": clean_scenarios,
        "clean_scenarios_with_findings": clean_with_findings,
        "false_positive_scenario_rate": round(clean_with_findings / clean_scenarios, 3) if clean_scenarios else None,
        "unexpected_primary_findings": unexpected,
    }


def _is_assertion_echo(f, kind):
    # An injected state fault legitimately also fails the scenario's own
    # assertion about that state; that is the same defect, not a false positive.
    return f["kind"] == "assertion" and kind in ("state", "events", "missing")

"""Oracles: turn a NativaX observation and a Chromium observation into
findings. A finding is evidence about one element/property/state; it is not
yet an issue (see `cluster.py`).

Oracles, each tied to the pipeline stage it isolates:
  crash        NativaX status/FlutterError/timeout          -> stage from library
  script_error error in NativaX that Chromium did not raise -> script
  missing      element measured by Chromium, absent/0x0 here -> dom_build/render_tree
  style        computed value differs (normalized)          -> style_resolution
  geometry     rect differs while computed styles agree     -> layout
  overflow     scroll size > client size disagrees          -> layout
  events       event log differs after an input action      -> events
  focus        activeElement differs                        -> focus
  state        text/value/checked differ after actions      -> state
  lifecycle    NativaX state after `rebuild` != initial     -> lifecycle
  assertion    explicit scenario assertion fails            -> by property
  performance  scenario wall time / RSS growth over limits  -> performance

Chromium is a reference, not ground truth: an `absolute` assertion that
fails in both engines is reported as `oracle_conflict`, never as a defect.
"""
from __future__ import annotations

import re

from .catalog import LAYOUT_SERIALIZED

GEOMETRY_TOL = 1.0
LENGTH_TOL = 0.5
COMPARED_EVENTS = ("click", "input", "submit", "focusin")

_STAGE_SUBSYSTEM = {
    "harness": "audit_harness",
    "runtime_create": "runtime",
    "script": "javascript",
    "dom_build": "html_dom",
    "style_resolution": "css",
    "layout": "layout",
    "render_tree": "render",
    "paint": "render",
    "build": "render",
    "events": "events",
    "focus": "accessibility_focus",
    "state": "state",
    "lifecycle": "lifecycle",
    "performance": "performance",
}

_LIBRARY_STAGE = {
    "rendering library": "layout",
    "widgets library": "build",
    "painting library": "paint",
    "gestures library": "events",
    "services library": "events",
    "scheduler library": "build",
    "flutter_test": "harness",
}


def subsystem(stage: str) -> str:
    return _STAGE_SUBSYSTEM.get(stage, "unknown")


# ------------------------------------------------------------ normalization
_COLOR = re.compile(r"rgba?\(\s*([\d.]+)[ ,]+([\d.]+)[ ,]+([\d.]+)(?:[ ,/]+([\d.]+))?\s*\)")
_NUM = re.compile(r"^(-?[\d.]+)(px)?$")


def normalize(prop: str, value):
    if value is None:
        return None
    v = str(value).strip().lower()
    m = _COLOR.fullmatch(v)
    if m:
        alpha = float(m.group(4)) if m.group(4) is not None else 1.0
        if alpha == 0:
            return ("rgba", 0, 0, 0, 0)
        return ("rgba", *(round(float(m.group(i))) for i in (1, 2, 3)), round(alpha, 2))
    if v == "transparent":
        return ("rgba", 0, 0, 0, 0)
    if prop == "font-weight":
        return {"normal": "400", "bold": "700"}.get(v, v)
    if prop == "font-family":
        return ",".join(p.strip().strip("'\"") for p in v.split(","))
    parts = v.split()
    if parts and all(_NUM.match(p) for p in parts):
        return tuple(float(_NUM.match(p).group(1)) for p in parts)
    return re.sub(r"\s+", " ", v)


def same(prop: str, a, b) -> bool:
    na, nb = normalize(prop, a), normalize(prop, b)
    if isinstance(na, tuple) and isinstance(nb, tuple) and na and nb \
            and na[0] != "rgba" and nb[0] != "rgba" and len(na) == len(nb):
        return all(abs(x - y) <= LENGTH_TOL for x, y in zip(na, nb))
    return na == nb


# -------------------------------------------------------------------- utils
def _by_id(probe) -> dict:
    return {e["id"]: e for e in (probe or {}).get("elements") or [] if e.get("id")}


def _parent_path(path: str) -> str | None:
    if "." not in path:
        return None
    return path[: path.rfind(".children[")]


def _index(path: str) -> int:
    m = re.search(r"\[(\d+)\]$", path)
    return int(m.group(1)) if m else 0


def _rect_delta(a, b):
    return [round(b[i] - a[i], 1) for i in range(4)]


def _rect_same(a, b, tol=GEOMETRY_TOL):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def _finding(kind, stage, *, element=None, prop=None, expected=None, actual=None,
             state="initial", primary=True, severity="medium", message="", extra=None):
    return {
        "kind": kind,
        "stage": stage,
        "subsystem": subsystem(stage),
        "element_id": (element or {}).get("id"),
        "json_path": (element or {}).get("nx"),
        "component_type": (element or {}).get("type"),
        "property": prop,
        "expected": expected,
        "actual": actual,
        "state": state,
        "primary": primary,
        "severity": severity,
        "message": message,
        **(extra or {}),
    }


_FRAME = re.compile(r"package:([a-z_]+)/(\S+?\.dart)[ :](\d+)(?::\d+)?")


def stack_locations(stack: list[str], root) -> list[dict]:
    """Repository frames from a Flutter stack, resolved to files that exist."""
    out = []
    for line in stack or []:
        m = _FRAME.search(line)
        if not m:
            continue
        pkg, rel, ln = m.group(1), m.group(2), int(m.group(3))
        for candidate in (root / "packages" / pkg / "lib" / rel,
                          root / "examples" / "web-challenge" / "lib" / rel):
            if candidate.exists():
                symbol = re.match(r"#\d+\s+(\S+)", line.strip())
                out.append({"file": str(candidate.relative_to(root)), "line": ln,
                            "symbol": symbol.group(1) if symbol else None,
                            "frame": line.strip()[:200]})
                break
    return out


# ------------------------------------------------------------------ oracles
def compare(scenario: dict, nativa: dict, chrome: dict, root) -> dict:
    """Returns {'status', 'findings', 'notes'} for one scenario."""
    findings: list[dict] = []
    notes: list[str] = []
    expected = scenario.get("expected") or {}
    limits = scenario.get("limits") or {}

    n_status = (nativa or {}).get("status")
    c_status = (chrome or {}).get("status")
    if n_status in ("harness_error",):
        return {"status": "inconclusive", "findings": [],
                "notes": [f"NativaX harness did not start: {(nativa or {}).get('error', '')[:400]}"]}

    # crash oracle
    if n_status != "ok":
        findings.append(_finding(
            "crash", (nativa or {}).get("stage") or "harness", severity="critical",
            message=f"NativaX scenario {n_status}: {(nativa or {}).get('error', '')[:600]}"))
    errors = (nativa or {}).get("flutter_errors") or []
    for index, err in enumerate(errors):
        stage = _LIBRARY_STAGE.get(err.get("library") or "", "build")
        # After the first exception Flutter reports every ancestor left
        # without layout ("RenderBox was not laid out" ...): one cause, so
        # only the first error of the scenario opens an issue.
        first = errors[0].get("summary") if index else None
        findings.append(_finding(
            "crash", stage, severity="critical", primary=index == 0,
            message=f"FlutterError ({err.get('library')}): {err.get('summary')}",
            extra={"stack_locations": stack_locations(err.get("stack"), root),
                   "flutter_context": err.get("context"),
                   "stack": err.get("stack"),
                   "error_index": index,
                   "consequence_of": [f"first FlutterError of the scenario: {first}"] if first else []}))
    if n_status != "ok":
        return {"status": "failed", "findings": findings, "notes": notes}

    reference_ok = c_status == "ok"
    if not reference_ok:
        notes.append(f"reference unavailable ({c_status}): only absolute oracles ran")

    n_states = nativa.get("states") or []
    c_states = (chrome or {}).get("states") or [] if reference_ok else []

    # script errors
    c_errors = set()
    for st in c_states:
        c_errors.update((st.get("probe") or {}).get("errors") or [])
    n_errors = list(nativa.get("script_errors") or [])
    for st in n_states:
        n_errors += (st.get("probe") or {}).get("errors") or []
    if expected.get("no_script_errors", True):
        for err in dict.fromkeys(n_errors):
            if err not in c_errors and not err.startswith("probe"):
                findings.append(_finding("script_error", "script", severity="high",
                                         message=f"script error only in NativaX: {err[:300]}"))

    # state-wise reference comparison, stopping where the reference could
    # not perform an action the same way.
    n_actions = {r["index"]: r for r in nativa.get("action_results") or []}
    c_actions = {r["index"]: r for r in (chrome or {}).get("action_results") or []}
    seen: set = set()
    for si, n_state in enumerate(n_states):
        label = n_state.get("after")
        if si > 0:
            ai = si - 1
            na, ca = n_actions.get(ai, {}), c_actions.get(ai, {})
            if not na.get("ok", True) and ca.get("ok", True):
                act = (scenario.get("actions") or [{}])[ai] if ai < len(scenario.get("actions") or []) else {}
                findings.append(_finding(
                    "interaction", "events", severity="high", state=label,
                    element={"id": act.get("target")},
                    message=f"NativaX could not perform '{na.get('op')}': {na.get('note')}"))
            if reference_ok and not ca.get("ok", True):
                notes.append(f"{label}: reference could not perform action ({ca.get('note')}); "
                             "later states compared only by absolute assertions")
                break
        if not reference_ok or si >= len(c_states):
            break
        for f in _compare_probe(scenario, n_state.get("probe"), c_states[si].get("probe"),
                                label, si, c_actions):
            # A divergence already present in an earlier state is the same
            # evidence again; later states only add what changed.
            key = (f["kind"], f["element_id"], f["property"], repr(f["actual"]))
            if key in seen and f["kind"] not in ("events", "focus", "state"):
                continue
            seen.add(key)
            findings.append(f)

    # lifecycle oracle (self-consistency, no reference needed)
    ops = [a.get("op") for a in scenario.get("actions") or []]
    if "rebuild" in ops and n_states:
        first = _by_id(n_states[0].get("probe"))
        rebuilt_at = ops.index("rebuild") + 1
        if rebuilt_at < len(n_states):
            after = _by_id(n_states[rebuilt_at].get("probe"))
            for eid, el in first.items():
                other = after.get(eid)
                if other is None:
                    findings.append(_finding("lifecycle", "lifecycle", element=el, severity="high",
                                             state=n_states[rebuilt_at]["after"],
                                             message="element missing after rebuild"))
                elif not _rect_same(el["rect"], other["rect"]) or el.get("text") != other.get("text"):
                    findings.append(_finding(
                        "lifecycle", "lifecycle", element=el, prop="rect/text", severity="high",
                        expected={"rect": el["rect"], "text": el.get("text")},
                        actual={"rect": other["rect"], "text": other.get("text")},
                        state=n_states[rebuilt_at]["after"],
                        message="rebuild with the same source did not restore the initial state"))

    # explicit assertions
    for assertion in scenario.get("assertions") or []:
        result = _assert(assertion, n_states, c_states)
        if result is not None:
            findings.append(result)

    # performance/resources (NativaX only, reported, never compared to Chromium)
    total = (nativa.get("timings") or {}).get("total_ms")
    if total and limits.get("max_ms") and total > limits["max_ms"]:
        findings.append(_finding("performance", "performance", severity="low",
                                 expected={"max_ms": limits["max_ms"]}, actual={"total_ms": total},
                                 message=f"scenario took {total} ms"))
    rss = nativa.get("rss_kb") or {}
    if rss and limits.get("max_rss_growth_kb") is not None:
        growth = rss.get("after", 0) - rss.get("before", 0)
        if growth > limits["max_rss_growth_kb"]:
            findings.append(_finding("performance", "performance", severity="low",
                                     prop="rss_growth_kb", expected={"max": limits["max_rss_growth_kb"]},
                                     actual={"growth_kb": growth},
                                     message=f"RSS grew {growth} KB during one scenario"))

    defects = [f for f in findings if f["kind"] != "oracle_conflict"]
    status = "failed" if defects else ("inconclusive" if not reference_ok else "passed")
    return {"status": status, "findings": findings, "notes": notes}


def _compare_probe(scenario, n_probe, c_probe, label, si, c_actions):
    out = []
    if n_probe is None or c_probe is None:
        if n_probe is None and c_probe is not None:
            out.append(_finding("crash", "script", severity="high", state=label,
                                message="NativaX probe returned nothing (probe threw or runtime gone)"))
        return out
    n_el, c_el = _by_id(n_probe), _by_id(c_probe)
    authored = {}
    for node_id, node in _nodes(scenario["screen"]):
        authored[node_id] = node.get("style") or {}

    style_bad: dict[str, set] = {}
    for eid, ref in c_el.items():
        mine = n_el.get(eid)
        ref_visible = ref["rect"][2] > 0 or ref["rect"][3] > 0
        if mine is None or (ref_visible and mine["rect"][2] == 0 and mine["rect"][3] == 0
                            and ref["styles"].get("display") != "none"):
            out.append(_finding("missing", "dom_build" if mine is None else "render_tree",
                                element=ref, severity="high", state=label,
                                expected={"rect": ref["rect"]},
                                actual=None if mine is None else {"rect": mine["rect"]},
                                message="element measured by the reference is "
                                        + ("absent from the NativaX DOM" if mine is None
                                           else "zero-sized in NativaX")))
            continue
        bad = set()
        for prop, ref_value in ref["styles"].items():
            if prop in LAYOUT_SERIALIZED:
                continue
            value = mine["styles"].get(prop)
            if not same(prop, value, ref_value):
                bad.add(prop)
        style_bad[eid] = bad
    # style findings, one per (element, property family): the four padding
    # longhands of one declaration are one divergence. An inherited divergence
    # identical to the parent's is a consequence, not a second defect.
    for eid, bad in style_bad.items():
        ref, mine = c_el[eid], n_el[eid]
        parent = _parent_path(ref.get("nx") or "")
        parent_id = next((i for i, e in c_el.items() if e.get("nx") == parent), None)
        groups: dict[str, list[str]] = {}
        for prop in sorted(bad):
            groups.setdefault(family(prop), []).append(prop)
        for fam, props in groups.items():
            inherited = all(parent_id in style_bad and p in style_bad[parent_id]
                            and n_el[parent_id]["styles"].get(p) == mine["styles"].get(p)
                            for p in props)
            own = {k: v for k, v in authored.get(eid, {}).items()
                   if family(k) == fam or k == fam or any(p.startswith(k + "-") for p in props)}
            out.append(_finding(
                "style", "style_resolution", element=ref, prop=fam, state=label,
                expected={p: ref["styles"].get(p) for p in props},
                actual={p: mine["styles"].get(p) for p in props},
                primary=not inherited, severity="medium",
                message=f"computed {', '.join(props)} differ" + (" (authored)" if own else ""),
                extra={"authored": own, "longhands": props}))
    # geometry findings with first-divergence localization
    size_bad, pos_bad = {}, {}
    for eid, ref in c_el.items():
        mine = n_el.get(eid)
        if mine is None or eid not in style_bad:
            continue
        d = _rect_delta(ref["rect"], mine["rect"])
        if abs(d[2]) > GEOMETRY_TOL or abs(d[3]) > GEOMETRY_TOL:
            size_bad[eid] = d
        elif abs(d[0]) > GEOMETRY_TOL or abs(d[1]) > GEOMETRY_TOL:
            pos_bad[eid] = d
    by_path = {e.get("nx"): i for i, e in c_el.items()}
    children_of: dict[str, list[str]] = {}
    for eid, e in c_el.items():
        p = _parent_path(e.get("nx") or "")
        if p is not None and p in by_path:
            children_of.setdefault(by_path[p], []).append(eid)
    for eid, d in {**size_bad, **pos_bad}.items():
        ref, mine = c_el[eid], n_el[eid]
        parent = by_path.get(_parent_path(ref.get("nx") or ""))
        reasons = []
        if eid in size_bad:
            kids = [k for k in children_of.get(eid, []) if k in size_bad]
            if kids:
                reasons.append(f"children also resized: {kids[:4]}")
        else:
            if parent in size_bad or parent in pos_bad:
                reasons.append(f"parent '{parent}' already diverged")
            idx = _index(ref.get("nx") or "")
            before = [s for s in children_of.get(parent, [])
                      if _index(c_el[s].get("nx") or "") < idx and (s in size_bad or s in pos_bad)]
            if before:
                reasons.append(f"preceding siblings diverged: {before[:4]}")
        if style_bad.get(eid):
            reasons.append(f"computed styles already differ: {sorted(style_bad[eid])[:4]}")
        primary = not reasons
        magnitude = max(abs(x) for x in d)
        out.append(_finding(
            "geometry", "layout", element=ref,
            prop="size" if eid in size_bad else "position", state=label,
            expected={"rect": ref["rect"]}, actual={"rect": mine["rect"], "delta": d},
            primary=primary, severity="high" if primary and magnitude > 8 else "medium",
            message=("rect differs while computed styles agree" if not style_bad.get(eid)
                     else "rect differs"),
            extra={"consequence_of": reasons,
                   "parent_display": (c_el.get(parent) or {}).get("styles", {}).get("display"),
                   "authored": authored.get(eid, {})}))
    # overflow / events / focus / state
    for eid, ref in c_el.items():
        mine = n_el.get(eid)
        if mine is None:
            continue
        for axis, i in (("overflow_x", 0), ("overflow_y", 1)):
            ro = ref["scroll"][i] > ref["client"][i] + 1 and ref["client"][i] > 0
            mo = mine["scroll"][i] > mine["client"][i] + 1 and mine["client"][i] > 0
            if ro != mo:
                out.append(_finding("overflow", "layout", element=ref, prop=axis, state=label,
                                    expected={"overflows": ro, "client": ref["client"], "scroll": ref["scroll"]},
                                    actual={"overflows": mo, "client": mine["client"], "scroll": mine["scroll"]},
                                    primary=eid not in size_bad, severity="medium",
                                    message=f"{axis} overflow disagrees"))
        if si > 0:
            for key in ("text", "value", "checked"):
                if ref.get(key) != mine.get(key):
                    out.append(_finding("state", "state", element=ref, prop=key, state=label,
                                        expected=ref.get(key), actual=mine.get(key),
                                        severity="high", message=f"'{key}' differs after actions"))
    if si > 0:
        filt = lambda evs: [e for e in evs or [] if e.split(":")[0] in COMPARED_EVENTS]
        model = (c_actions.get(si - 1) or {}).get("note") or ""
        ne, ce = filt(n_probe.get("events")), filt(c_probe.get("events"))
        if ne != ce and "model" not in model:
            out.append(_finding("events", "events", state=label, prop="events",
                                expected=ce, actual=ne, severity="medium",
                                message="event sequence differs",
                                extra={"first_difference": _first_diff(ce, ne)}))
        if n_probe.get("focused") != c_probe.get("focused"):
            out.append(_finding("focus", "focus", state=label, prop="activeElement",
                                element=c_el.get(c_probe.get("focused")) or n_el.get(n_probe.get("focused")),
                                expected=c_probe.get("focused"), actual=n_probe.get("focused"),
                                severity="medium",
                                message="focused element differs"
                                        + (" (reference uses a focus-traversal model)" if "model" in model else "")))
    return out


def _first_diff(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return {"index": i, "expected": x, "actual": y}
    if len(a) != len(b):
        i = min(len(a), len(b))
        return {"index": i, "expected": a[i] if i < len(a) else None,
                "actual": b[i] if i < len(b) else None}
    return None


FAMILIES = [
    ("padding-", "padding"), ("margin-", "margin"), ("overflow-", "overflow"),
]


def family(prop: str) -> str:
    """Groups longhands that one shorthand or one UA rule sets together."""
    if prop.startswith("border-") and prop.endswith("-radius"):
        return "border-radius"
    if prop.startswith("border-") and prop.endswith("-width"):
        return "border-width"
    if prop.startswith("border-") and prop.endswith("-style"):
        return "border-style"
    if prop.startswith("border-") and prop.endswith("-color"):
        return "border-color"
    if prop in ("row-gap", "column-gap"):
        return "gap"
    for prefix, name in FAMILIES:
        if prop.startswith(prefix):
            return name
    return prop


def _authored(style: dict, prop: str) -> bool:
    return any(prop == k or prop.startswith(k + "-") for k in style)


def _nodes(node):
    yield node.get("id"), node
    for c in node.get("children") or []:
        yield from _nodes(c)


def _state(states, label):
    if not states:
        return None
    if label in (None, "last"):
        return states[-1].get("probe")
    for s in states:
        if s.get("after") == label:
            return s.get("probe")
    return None


def read_property(probe, assertion):
    """Value of an assertion property in one probe (None when unmeasured)."""
    if probe is None:
        return None
    target, prop = assertion["target"], assertion["property"]
    if prop == "focused":
        return probe.get("focused") == target
    if prop == "events":
        return probe.get("events")
    el = _by_id(probe).get(target)
    if prop == "exists":
        return el is not None
    if el is None:
        return None
    if prop.startswith("rect."):
        return el["rect"][["rect.x", "rect.y", "rect.width", "rect.height"].index(prop)]
    if prop == "visible":
        return (el["rect"][2] > 0 or el["rect"][3] > 0) and el["styles"].get("visibility") != "hidden"
    if prop in ("overflow_x", "overflow_y"):
        i = 0 if prop == "overflow_x" else 1
        return el["scroll"][i] > el["client"][i] + 1 and el["client"][i] > 0
    if prop == "style":
        return el["styles"].get(assertion.get("style_property"))
    return el.get(prop)


def holds(op, actual, expected, tol=0.0):
    try:
        if op == "equals":
            return actual == expected
        if op == "not_equals":
            return actual != expected
        if op == "approx":
            return abs(float(actual) - float(expected)) <= tol
        if op == "lt":
            return actual < expected
        if op == "lte":
            return actual <= expected
        if op == "gt":
            return actual > expected
        if op == "gte":
            return actual >= expected
        if op == "contains":
            return expected in actual
    except (TypeError, ValueError):
        return False
    return False


_ASSERT_STAGE = {"rect.x": "layout", "rect.y": "layout", "rect.width": "layout",
                 "rect.height": "layout", "overflow_x": "layout", "overflow_y": "layout",
                 "visible": "render_tree", "text": "state", "value": "state",
                 "checked": "state", "focused": "focus", "events": "events",
                 "style": "style_resolution", "exists": "dom_build"}


def _assert(assertion, n_states, c_states):
    label = assertion.get("state")
    n_value = read_property(_state(n_states, label), assertion)
    c_value = read_property(_state(c_states, label), assertion) if c_states else None
    oracle = assertion.get("oracle", "absolute")
    expected = c_value if oracle == "reference" else assertion.get("expected")
    tol = assertion.get("tolerance", 0.0)
    if oracle == "reference" and not c_states:
        return None
    if holds(assertion["operator"], n_value, expected, tol):
        return None
    stage = _ASSERT_STAGE.get(assertion["property"], "state")
    ref_holds = None
    if oracle == "absolute" and c_states:
        ref_holds = holds(assertion["operator"], c_value, expected, tol)
    kind = "oracle_conflict" if ref_holds is False else "assertion"
    return _finding(
        kind, stage, element={"id": assertion["target"]}, prop=assertion["property"],
        expected=expected, actual=n_value, state=label or "last",
        severity="info" if kind == "oracle_conflict" else "high",
        message=(f"assertion {assertion['id']} fails in NativaX"
                 + ("" if ref_holds is None else
                    " and in the reference too: the assertion or the scenario is wrong, "
                    "not counted as a defect" if ref_holds is False else
                    "; the reference satisfies it")),
        extra={"assertion_id": assertion["id"], "reference_value": c_value,
               "reference_holds": ref_holds})

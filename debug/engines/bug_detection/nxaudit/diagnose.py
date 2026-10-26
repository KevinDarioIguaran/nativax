"""Clustering findings into issues and diagnosing each issue.

Only *primary* findings (first divergence; see compare.py) open issues;
consequential findings are counted on the issue they follow from. The
fingerprint deliberately ignores element ids so the same defect on fifty
screens is one issue with fifty occurrences.

Nothing here claims a root cause. Code locations come from two sources only:
stack frames of a real FlutterError (`confirmed: trace`) and `git grep` hits
for the property/event involved (`search hit`, never a cause).
"""
from __future__ import annotations

import hashlib
import re
import subprocess
from functools import lru_cache
from pathlib import Path

from .compare import normalize

ROOT = Path(__file__).resolve().parents[4]


def _norm_text(value) -> str:
    text = str(value)
    # Flutter object ids (#424ce), relayout boundaries (up29) and dirty flags
    # differ per instance, not per defect.
    text = re.sub(r"#[0-9a-f]{5}\b", "", text)
    text = re.sub(r"relayoutBoundary=up\d+", "", text)
    text = re.sub(r"\b(NEEDS-[A-Z-]+|DETACHED)\b", "", text)
    text = re.sub(r"\d+(\.\d+)?", "#", text)
    return re.sub(r"\s+", " ", text).strip()[:120]


def fingerprint(f: dict) -> str:
    kind = f["kind"]
    t = f.get("component_type")
    if kind == "crash":
        # Stage + normalized message only: the captured stack depth (and so
        # its top repository frame) depends on the harness, not the defect.
        return f"crash|{f['stage']}|{_norm_text(f['message'])}"
    if kind == "style":
        authored = f.get("authored") or {}
        if authored:
            # Authored values: the unit/function class identifies the code
            # path (percentages, em, calc...), not the literal number.
            return f"style|{f['property']}|authored:{value_class(' '.join(authored.values()))}"
        exp = {k: normalize(k, v) for k, v in sorted((f.get("expected") or {}).items())}
        act = {k: normalize(k, v) for k, v in sorted((f.get("actual") or {}).items())}
        # UA/initial values: same reference value -> same NativaX value is
        # one rule, whatever element shows it.
        return f"style|{f['property']}|ua|{sorted(set(map(repr, exp.values())))}->{sorted(set(map(repr, act.values())))}"
    if kind == "geometry":
        d = (f.get("actual") or {}).get("delta") or [0, 0, 0, 0]
        sign = "".join("+" if v > 1 else "-" if v < -1 else "0" for v in d)
        # Parent display and authored declarations are context (listed on the
        # issue), not identity: one defect seen under several layouts stays
        # one issue.
        return f"geometry|{f['property']}|{t}|{sign}"
    if kind == "overflow":
        e = (f.get("expected") or {}).get("overflows")
        return f"overflow|{f['property']}|{t}|{e}"
    if kind == "events":
        diff = f.get("first_difference") or {}
        a = str(diff.get("expected") or "∅").split(":")[0]
        b = str(diff.get("actual") or "∅").split(":")[0]
        return f"events|{a}->{b}"
    if kind == "focus":
        return f"focus|{f['state'].split(':')[-1]}|{t}|{'none' if f['actual'] is None else 'other'}"
    if kind in ("state", "assertion", "oracle_conflict"):
        return f"{kind}|{f['property']}|{t}|{f['state'].split(':')[-1]}"
    if kind == "script_error":
        return f"script|{_norm_text(f['message'])}"
    if kind == "interaction":
        return f"interaction|{_norm_text(f['message'])}"
    return f"{kind}|{f['stage']}|{t}|{f.get('property')}"


def value_class(value: str) -> str:
    v = value.lower()
    classes = [name for name, test in (
        ("calc", "calc(" in v), ("percent", "%" in v), ("em", "em" in v and "rem" not in v),
        ("viewport", "vw" in v or "vh" in v), ("negative", "-" in v and any(c.isdigit() for c in v)),
        ("px", "px" in v)) if test]
    if not classes:
        classes = ["keyword" if v.strip() and not v.strip()[0].isdigit() else "number"]
    return "+".join(classes)


def issue_id(fp: str) -> str:
    return "NX-" + hashlib.sha1(fp.encode()).hexdigest()[:8].upper()


SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}


def cluster(results: list[dict]) -> dict[str, dict]:
    """results: [{'scenario': s, 'comparison': c}] -> {issue_id: issue}."""
    issues: dict[str, dict] = {}
    for item in results:
        scenario, comparison = item["scenario"], item["comparison"]
        primaries = [f for f in comparison["findings"] if f.get("primary", True)]
        consequences = len(comparison["findings"]) - len(primaries)
        for f in primaries:
            fp = fingerprint(f)
            iid = issue_id(fp)
            issue = issues.setdefault(iid, {
                "issue_id": iid, "fingerprint": fp, "kind": f["kind"],
                "stage": f["stage"], "subsystem": f["subsystem"],
                "property": f.get("property"), "severity": f["severity"],
                "component_types": set(), "scenarios": [], "occurrences": [],
                "families": set(), "consequential_findings": 0,
                "first_seen_family": scenario.get("family"),
            })
            issue["occurrences"].append({"scenario_id": scenario["scenario_id"], "finding": f})
            if scenario["scenario_id"] not in issue["scenarios"]:
                issue["scenarios"].append(scenario["scenario_id"])
            issue["families"].add(scenario.get("family"))
            if f["kind"] == "geometry":
                ctx = f"display={f.get('parent_display')} authored={sorted((f.get('authored') or {}).keys())}"
                issue.setdefault("contexts", {})
                issue["contexts"][ctx] = issue["contexts"].get(ctx, 0) + 1
            if f.get("component_type"):
                issue["component_types"].add(f["component_type"])
            if SEVERITY_ORDER[f["severity"]] < SEVERITY_ORDER[issue["severity"]]:
                issue["severity"] = f["severity"]
        if primaries:
            # Attribute consequences to the scenario's most severe issue.
            top = min(primaries, key=lambda f: SEVERITY_ORDER[f["severity"]])
            issues[issue_id(fingerprint(top))]["consequential_findings"] += consequences
    return issues


# ---------------------------------------------------------------- code search
SEARCH_AREAS = {
    "style_resolution": ["packages/nativa_css/lib", "packages/nativa_dom_bindings/lib"],
    "layout": ["packages/nativa_render/lib/src/layout", "packages/nativa_render/lib/src/style_mapping.dart"],
    "render_tree": ["packages/nativa_render/lib/src/render"],
    "dom_build": ["packages/nativa_html/lib", "packages/nativa_dom/lib"],
    "events": ["packages/nativa_render/lib/src/render", "packages/nativa_dom_bindings/lib", "packages/nativax/lib"],
    "focus": ["packages/nativa_render/lib/src/render", "packages/nativa_dom_bindings/lib"],
    "state": ["packages/nativa_render/lib/src/render", "packages/nativa_dom_bindings/lib"],
    "lifecycle": ["packages/nativax/lib/src/view.dart", "packages/nativax/lib/src/runtime.dart"],
    "script": ["packages/nativa_dom_bindings/lib", "packages/nativa_js/lib"],
    "performance": ["packages/nativa_render/lib", "packages/nativax/lib"],
    "build": ["packages/nativa_render/lib"],
    "paint": ["packages/nativa_render/lib/src/render"],
}

LAYOUT_FILES = {
    "flex": "packages/nativa_render/lib/src/layout/css_flex.dart",
    "inline-flex": "packages/nativa_render/lib/src/layout/css_flex.dart",
    "grid": "packages/nativa_render/lib/src/layout/css_grid.dart",
    "block": "packages/nativa_render/lib/src/layout/css_block.dart",
}


@lru_cache(maxsize=512)
def search(term: str, areas: tuple[str, ...], limit: int = 6) -> tuple[dict, ...]:
    """`git grep -n -F` over existing paths; each hit is a real file:line."""
    paths = [a for a in areas if (ROOT / a).exists()]
    if not paths or not term:
        return ()
    try:
        out = subprocess.run(["git", "grep", "-n", "-F", term, "--", *paths], cwd=ROOT,
                             capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ()
    hits = []
    for line in out.splitlines()[:limit]:
        file, ln, text = line.split(":", 2)
        hits.append({"file": file, "line": int(ln), "match": text.strip()[:160],
                     "basis": f"git grep -F {term!r}"})
    return tuple(hits)


def _search_terms(issue: dict, finding: dict) -> list[str]:
    kind, prop = issue["kind"], issue.get("property")
    if kind == "style" and prop:
        return [f"'{prop}'", "getComputedStyle"]
    if kind == "geometry":
        authored = list((finding.get("authored") or {}).keys())
        return [f"'{p}'" for p in authored[:3]] or [f"'{finding.get('component_type')}'"]
    if kind == "overflow":
        return ["scrollWidth", "clientWidth"]
    if kind == "events":
        diff = finding.get("first_difference") or {}
        ev = str(diff.get("expected") or diff.get("actual") or "click").split(":")[0]
        return [f"'{ev}'"]
    if kind == "focus":
        return ["focusin", "requestFocus"]
    if kind == "state":
        return [f"'{prop}'"] if prop else []
    if kind == "lifecycle":
        return ["dispose", "_reload"]
    if kind == "missing":
        return [f"'{_tag(finding)}'"]
    return []


def _tag(f):
    from .catalog import COMPONENTS
    return COMPONENTS.get(f.get("component_type") or "", {}).get("tag", "div")


# ------------------------------------------------------------------ diagnose
def diagnose(issue: dict, scenarios: dict[str, dict], minimization: dict | None) -> dict:
    """Evidence-based diagnosis. Returns location, hypotheses, checks."""
    first = issue["occurrences"][0]
    f = first["finding"]
    scenario = scenarios.get(first["scenario_id"]) or {}
    loc = {"screen_id": (scenario.get("screen") or {}).get("id"),
           "element_id": f.get("element_id"), "json_path": f.get("json_path"),
           "source_file": None, "symbol": None, "line": None, "basis": None}
    if loc["json_path"] is None and f.get("element_id"):
        from .compile import node_by_id
        hit = node_by_id(scenario.get("screen") or {}, f["element_id"])
        if hit:
            loc["json_path"] = hit[0]
    frames = f.get("stack_locations") or []
    if frames:
        loc.update(source_file=frames[0]["file"], line=frames[0]["line"],
                   symbol=frames[0]["symbol"], basis="FlutterError stack frame")

    files = []
    if issue["kind"] == "geometry" and f.get("parent_display") in LAYOUT_FILES:
        files.append({"file": LAYOUT_FILES[f["parent_display"]], "line": None,
                      "match": None, "basis": f"parent display is {f['parent_display']}"})
    for term in _search_terms(issue, f):
        files += list(search(term, tuple(SEARCH_AREAS.get(issue["stage"], []))))
    files = [x for i, x in enumerate(files) if (x["file"], x["line"]) not in
             {(y["file"], y["line"]) for y in files[:i]}][:10]

    hyps, checks = _hypotheses(issue, f, minimization)
    confidence = _confidence(issue, f, frames, minimization)
    return {"location": loc, "files_to_inspect": files, "hypotheses": hyps,
            "next_checks": checks, "confidence": confidence}


def _hypotheses(issue, f, minimization):
    """Hypotheses ranked by the amount of evidence, with evidence for/against."""
    kind = issue["kind"]
    necessary = (minimization or {}).get("necessary_conditions") or []
    removed = (minimization or {}).get("removed") or []
    hyps, checks = [], []

    def add(statement, evidence_for, evidence_against=(), status="unconfirmed"):
        hyps.append({"statement": statement, "status": status,
                     "evidence_for": list(evidence_for), "evidence_against": list(evidence_against)})

    if kind == "crash":
        frames = f.get("stack_locations") or []
        add(f"An exception is thrown during '{f['stage']}': {f['message'][:200]}",
            [f"FlutterError captured by FlutterError.onError ({f.get('flutter_context')})"]
            + [f"top repo frame {fr['file']}:{fr['line']} ({fr['symbol']})" for fr in frames[:2]],
            status="confirmed")
        checks.append("Open the first repository frame and find which input value reaches the throw; "
                      "the minimal JSON names the node that triggers it.")
    elif kind == "style":
        authored = f.get("authored") or {}
        geometry_ok = issue.get("_geometry_matches")
        if authored:
            add(f"The cascade/parser resolves the authored '{issue['property']}' to a different computed value",
                [f"authored {authored}", f"reference {f['expected']!r}, NativaX {f['actual']!r}"])
        else:
            add(f"The initial/UA value or the getComputedStyle serialization of '{issue['property']}' differs "
                "from the reference",
                [f"'{issue['property']}' is not authored on the element",
                 f"reference {f['expected']!r}, NativaX {f['actual']!r}"])
        if geometry_ok:
            hyps[-1]["evidence_for"].append("element geometry matches the reference: the used value may be "
                                            "right and only the serialized value differs")
        checks.append(f"Read the computed value of '{issue['property']}' through css.computed and through "
                      "getComputedStyle for the minimal case to separate cascade from serialization.")
    elif kind == "geometry":
        cond = [c for c in necessary if c.get("unit") in ("style", "text", "node")]
        add(f"The {f.get('parent_display') or 'block'} layout computes a different "
            f"{f['property']} for '{f.get('component_type')}' while computed styles agree",
            ["computed styles of the element agree with the reference",
             f"delta {(f.get('actual') or {}).get('delta')} px",
             "parent rect and preceding siblings agree (first divergence)"]
            + [f"necessary for reproduction: {c['description']}" for c in cond[:6]]
            + [f"seen under {ctx} ({n}x)" for ctx, n in list((issue.get("contexts") or {}).items())[:5]])
        if f.get("component_type") in ("text", "inline_text", "heading", "button", "link"):
            text_needed = any(c.get("unit") == "text" for c in necessary)
            add("Intrinsic text measurement (font metrics / line breaking) differs",
                ["element carries text"] + (["shortening the text removed the failure"] if text_needed else []),
                [] if text_needed or not minimization else
                ["the failure survived text reduction"] if any(r.get("unit") == "text" for r in removed) else [])
        checks.append("Replay the minimal case, then remove each necessary declaration in turn: the one whose "
                      "removal makes NativaX match pins the layout branch.")
    elif kind == "overflow":
        add("scrollWidth/scrollHeight or clientWidth/clientHeight are computed with a different box "
            "(border/padding/scrollbar) than the reference",
            [f"reference {f['expected']}", f"NativaX {f['actual']}"])
        checks.append("Compare offsetWidth, clientWidth and scrollWidth for the minimal element; "
                      "a difference equal to the border width points at the box used by scrollWidth.")
    elif kind in ("events", "focus"):
        add("Default actions of the hit-tested element differ (focus on pointer down, event order)",
            [f"reference {f['expected']}", f"NativaX {f['actual']}",
             "the reference dispatches synthetic events at the same point; focus-on-click follows Chromium"])
        checks.append("Log pointerdown/mousedown/focus order in both engines for the minimal case.")
    elif kind == "state":
        add(f"'{issue['property']}' is not updated or rendered after the action",
            [f"reference {f['expected']!r}", f"NativaX {f['actual']!r}"])
        checks.append("Check whether the DOM value changed (probe) but the widget did not, or vice versa.")
    elif kind == "lifecycle":
        add("Remounting NativaXView with the same source does not reproduce the initial state",
            [f"initial {f['expected']}", f"after rebuild {f['actual']}"])
        checks.append("Mount twice in a widget test and diff the two probes.")
    elif kind == "assertion":
        add(f"The scenario assertion on '{issue['property']}' fails in NativaX",
            [f"expected {f['expected']!r}, observed {f['actual']!r}",
             f"reference value {f.get('reference_value')!r}"])
    elif kind == "missing":
        add("The element is not built or has an empty box in NativaX",
            [f"reference rect {(f.get('expected') or {}).get('rect')}"])
    else:
        add(f"{kind} divergence", [f["message"]])
    return hyps, checks


def _confidence(issue, f, frames, minimization):
    """Rule-based, not a calibrated probability:
    high   = exception with a repository stack frame, or a minimized case that
             reproduces with the stage isolated by the differential;
    medium = stage isolated by the differential (primary finding) but not
             minimized/reproduced yet;
    low    = everything else (oracle-limited, search hits only)."""
    if frames:
        return {"level": "high", "basis": "FlutterError with repository stack frame"}
    if minimization and minimization.get("reproduced"):
        return {"level": "high", "basis": "minimized case reproduces; stage isolated by differential oracle"}
    if f.get("primary", True) and issue["kind"] in ("style", "geometry", "overflow", "state", "missing"):
        return {"level": "medium", "basis": "first divergence isolated by differential oracle"}
    return {"level": "low", "basis": "oracle-limited evidence; code locations are search hits only"}

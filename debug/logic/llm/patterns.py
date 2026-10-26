"""Cross-item patterns: one finding that explains many items.

A model that reads 116 page reports to discover that every form control has
`border-radius: 2px` wastes tokens; the pack states the pattern once with
every affected page. Patterns are computed from the items' own detail, so
they add no new measurement.
"""
from __future__ import annotations

import statistics
import sys
from pathlib import Path

from .core import Item, code_refs, r1, stable_id

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "engines" / "bug_detection"))
try:
    from nxaudit.compare import family  # longhand -> shorthand family (padding-top -> padding)
except Exception:  # noqa: BLE001 - fall back to the property itself
    def family(prop):
        return prop

CSS_CODE = ("packages/nativa_css/lib", "packages/nativa_dom_bindings/lib")


def visual_style(items: list[Item]) -> list[Item]:
    groups: dict[tuple, dict] = {}
    for it in items:
        if it.area != "visual":
            continue
        page = it.detail.get("pg")
        for el in (it.detail.get("root") or []):
            selector, path, line = el[0], el[1], el[2]
            for prop, chrome, nativa in el[7]:
                key = (family(prop), str(chrome), str(nativa))
                g = groups.setdefault(key, {"pages": {}, "props": set(), "tags": {}})
                g["props"].add(prop)
                g["pages"].setdefault(page, set()).add(selector)
                tag = str(selector).split(".")[0].split("#")[0]
                g["tags"][tag] = g["tags"].get(tag, 0) + 1
    out = []
    for (fam, chrome, nativa), g in groups.items():
        if len(g["pages"]) < 3:
            continue
        pages = sorted(g["pages"])
        tags = sorted(g["tags"].items(), key=lambda kv: -kv[1])
        out.append(Item(
            id=stable_id("PAT-VIS", f"{fam}-{chrome}-{nativa}", 60), area="pattern", priority=2,
            headline=(f"visual: computed {fam} {chrome!r}→{nativa!r} in {len(pages)} pages "
                      f"({sum(g['tags'].values())} root elements; tags {','.join(t for t, _ in tags[:4])})"),
            impact=len(pages) * 10,
            detail={"kind": "visual-style", "fam": fam, "props": sorted(g["props"]), "chrome": chrome,
                    "nativa": nativa, "tags": tags[:10],
                    "pages": [[p, sorted(g["pages"][p])[:4]] for p in pages],
                    "code": list(code_refs(f"'{sorted(g['props'])[0]}'", CSS_CODE, 3))},
            data={"pages": len(pages), "fam": fam, "chrome": chrome, "nativa": nativa}))
    return out


def perf_cost(items: list[Item]) -> list[Item]:
    groups: dict[tuple, list] = {}
    for it in items:
        if it.area != "perf" or not it.detail.get("dom"):
            continue
        groups.setdefault((it.detail.get("k"), it.detail["dom"][0]), []).append(it)
    out = []
    for (kind, comp), members in groups.items():
        if len(members) < 3:
            continue
        ratios = [m.data.get("w") for m in members if isinstance(m.data.get("w"), (int, float))]
        out.append(Item(
            id=stable_id("PAT-PERF", f"{kind}-{comp}", 60), area="pattern", priority=2,
            headline=(f"perf: {comp} dominates NativaX cost in {len(members)} {kind} scenarios "
                      f"(work ratio median {r1(statistics.median(ratios), 2) if ratios else '—'}x, "
                      f"max {r1(max(ratios), 2) if ratios else '—'}x)"),
            impact=len(members) * 5,
            detail={"kind": "perf-cost", "k": kind, "comp": comp,
                    "sc": sorted([[m.id.split("-", 1)[1], m.data.get("w"), m.data.get("v")] for m in members],
                                 key=lambda r: -(r[1] or 0))},
            data={"n": len(members), "k": kind, "comp": comp}))
    return out


def link_audit(patterns: list[Item], items: list[Item]) -> None:
    """Marks a visual style pattern and an audit issue that report the same
    family with the same reference/NativaX values (two engines, one defect)."""
    audits = [i for i in items if i.area == "audit" and i.detail.get("k") == "style"]
    for pat in patterns:
        if pat.detail.get("kind") != "visual-style":
            continue
        for a in audits:
            exp, act = a.detail.get("exp"), a.detail.get("act")
            if a.detail.get("prop") != pat.detail["fam"] or not isinstance(exp, dict) or not isinstance(act, dict):
                continue
            if pat.detail["chrome"] in map(str, exp.values()) and pat.detail["nativa"] in map(str, act.values()):
                pat.detail.setdefault("also", []).append(a.id)
                pat.headline += f" · same defect as audit {a.id}"
                pat.priority = 1
                break


def build(items: list[Item]) -> list[Item]:
    pats = visual_style(items) + perf_cost(items)
    link_audit(pats, items)
    covered: dict[str, list] = {}
    for p in pats:
        if p.detail.get("kind") == "visual-style":
            for page, _ in p.detail["pages"]:
                covered.setdefault(page, []).append(p.id)
    for it in items:
        if it.area == "visual" and it.detail.get("pg") in covered:
            it.detail["pat"] = covered[it.detail["pg"]]
    return pats

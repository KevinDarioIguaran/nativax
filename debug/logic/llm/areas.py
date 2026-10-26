"""Per-area digesters: evidence -> ranked Items with dense, compact detail.

Each function returns (summary, items). Keys are short; their meaning is in
LEGEND (written once into index.json). Absent keys mean "not measured".
"""
from __future__ import annotations

import glob
import json
import math
import re
from pathlib import Path

from .core import (ROOT, Item, code_refs, compact, fit, load_json, normalize_reason, previous_comparable,
                   r1, rel, stable_id, tokens)
from . import sources

ART = ROOT / "debug" / "artifacts"
BENCH = ROOT / "debug" / "benchmarks"
CSS_CODE = ("packages/nativa_css/lib", "packages/nativa_dom_bindings/lib")
LAYOUT_CODE = ("packages/nativa_render/lib/src/layout",)
RENDER_CODE = ("packages/nativa_render/lib/src/render",)
LAYOUT_FILE = {"flex": "packages/nativa_render/lib/src/layout/css_flex.dart",
               "inline-flex": "packages/nativa_render/lib/src/layout/css_flex.dart",
               "grid": "packages/nativa_render/lib/src/layout/css_grid.dart",
               "block": "packages/nativa_render/lib/src/layout/css_block.dart"}
DETAIL_BUDGET = 1100

LEGEND = {
    "item": {"id": "stable id", "a": "area", "p": "priority 1..3", "t": "trend vs previous comparable run",
             "h": "headline", "src": "evidence files", "cmd": "reproduce/verify commands", "o": "omitted rows"},
    "visual": {"pg": "page", "fx": "fixture html", "vp": "[w,h,scheme]",
               "sc": "scores % {o:overall,pos,lay,col,des}", "why": "engine verdict reason",
               "px": "pixels {d:% differing dE>2,ink:% of ink differing,me:mean dE,mx:max dE}",
               "prev": "previous comparable overall and delta", "root": "elements the engine flags as root cause",
               "el": "[selector,path,src line,chrome[x,y,w,h],nativa[x,y,w,h],delta[dx,dy,dw,dh],iou,"
                     "styles[[prop,chrome,nativa]],css[[file:line,selector,decls]]]",
               "more": "other divergent elements [selector,delta,iou]", "tiles": "worst 16px tiles [x,y,dE]",
               "code": "grep hits (not causes) {css prop|layout:display: [file:line]}",
               "pat": "patterns that also cover this page"},
    "perf": {"k": "scenario kind", "why": "engine reasons", "n": "NativaX", "c": "Chromium",
             "m": "{s:scenario ms,ev:eval ms,ld:load ms,r:render ms,p95,mx:max frame ms,nodes,rss:peak MB,"
                  "rsst:tail MB,cpu:peak %}", "x": "ratios NativaX/Chromium {w:work,s:scenario,r:render,n:nodes}",
             "tgt": "targets", "dom": "dominant NativaX cost [component, share of work]",
             "prev": "previous comparable work ratio and delta", "code": "scenario definition grep hits",
             "warn": "measurement caveat computed by the pack"},
    "conformance": {"s": "suite", "run": "summary file", "n": "{pass,fail,skip,error,total}", "rate": "pass %",
                    "prev": "previous run of the suite {rate,delta,new_fail,fixed}",
                    "g": "failure groups [where, normalized reason, count, examples[[id,reason,detail]]]"},
    "memory": {"case": "case id", "st": "status", "cls": "classification", "why": "reason",
               "ch": "per-channel evidence (as recorded)", "smp": "samples [batch,rss MB]"},
    "security": {"case": "case id", "sev": "severity", "cat": "category", "exp": "expected", "obs": "observed",
                 "fix": "remediation", "ev": "evidence"},
    "pattern": {"kind": "visual-style | perf-cost", "fam": "CSS property family", "props": "longhands seen",
                "chrome": "reference computed value", "nativa": "NativaX computed value",
                "tags": "[tag,count] of affected root elements", "pages": "[page,[selectors]]",
                "also": "audit issue ids reporting the same defect", "k": "perf scenario kind",
                "comp": "dominant cost component", "sc": "[scenario,work ratio,verdict]"},
    "audit": {"iss": "issue id", "k": "oracle kind", "sub": "subsystem", "stage": "pipeline stage",
              "comp": "component types", "prop": "property", "loc": "location", "exp": "expected (reference)",
              "act": "actual (NativaX)", "min": "minimal reproducing scenario", "need": "necessary conditions",
              "hyp": "hypotheses [status,statement]", "files": "files to inspect [file:line,basis]",
              "fix": "fix requirements", "acc": "acceptance criteria"},
}


def _best(paths: list[Path], size) -> Path | None:
    """The candidate with the most measured items; newest on a tie."""
    scored = []
    for p in paths:
        data = load_json(p)
        if not isinstance(data, dict):
            continue
        scored.append((size(data), p.stat().st_mtime, p))
    if not scored:
        return None
    return max(scored)[2]


# ------------------------------------------------------------------ visual
def _fixture(entry: str) -> Path | None:
    """The page's fixture file. Runs recorded before the 2026-10-25 move name
    tools/visual/...; they are mapped to debug/engines/visual_comparison/."""
    if not entry:
        return None
    p = Path(entry)
    if p.exists():
        return p
    text = str(p).replace("/tools/visual/", "/debug/engines/visual_comparison/")
    moved = Path(text)
    return moved if moved.exists() else p

def visual(path: Path | None = None):
    if path is None:
        cands = [Path(p) for p in glob.glob(str(ART / "visual" / "**" / "results.json"), recursive=True)]
        cands += [Path(p) for p in glob.glob(str(ART / "runs" / "visual" / "*" / "evidence" / "results.json"))]
        path = _best(cands, lambda d: len(d.get("rows") or []))
    if path is None:
        return {"state": "no visual results found"}, []
    data = load_json(path) or {}
    rows = data.get("rows") or []
    base = path.parent
    prev = previous_comparable("visual", "pages", len(rows))
    prev_rows = {r.get("page"): r for r in ((prev or {}).get("data") or {}).get("rows") or []}
    counts = {}
    for r in rows:
        counts[r.get("verdict")] = counts.get(r.get("verdict"), 0) + 1
    scores = [r["overall"] for r in rows if isinstance(r.get("overall"), (int, float))]
    summary = compact({"src": rel(path), "pages": len(rows), "v": counts,
                       "mean": r1(sum(scores) / len(scores), 2) if scores else None,
                       "prev": rel(prev["run"]["file"]) if prev else None})
    items = []
    for r in rows:
        verdict = r.get("verdict")
        if verdict == "PASS":
            continue
        page = str(r.get("page"))
        pdir = base / "pages" / page
        report = load_json(pdir / "report.json") or {}
        elements = (load_json(pdir / "elements.json") or {}).get("rows") or []
        pixels = (load_json(pdir / "pixels.json") or {})
        entry = report.get("entry") or ""
        fixture = _fixture(entry)
        fdir = str(fixture.parent) if fixture else None
        old = prev_rows.get(page)
        delta = None
        if old and isinstance(old.get("overall"), (int, float)) and isinstance(r.get("overall"), (int, float)):
            delta = round(r["overall"] - old["overall"], 2)
        trend = None if delta is None else ("regressed" if delta < -0.5 else "improved" if delta > 0.5 else "unchanged")
        divergent = [e for e in elements if not e.get("position_match") or not e.get("size_match")
                     or e.get("style_mismatches") or e.get("missing") or e.get("extra")]

        def weight(e):
            area = math.sqrt(max(1.0, (e.get("chrome_w") or 0) * (e.get("chrome_h") or 0)))
            return (1 if e.get("root_cause") else 0, ((e.get("position_delta") or 0) + (e.get("size_delta") or 0)) * area)
        divergent.sort(key=weight, reverse=True)
        roots = [e for e in divergent if e.get("root_cause")] or divergent[:3]
        code: dict[str, list] = {}

        def el_row(e):
            node = sources.element(str(fixture), e["path"]) if fixture else None
            styles = [[m.get("property"), m.get("chrome"), m.get("nativa")] for m in e.get("style_mismatches") or []
                      if isinstance(m, dict)]
            for prop, *_ in styles[:4]:
                code.setdefault(prop, list(code_refs(f"'{prop}'", CSS_CODE, 2)))
            return [sources.selector_label(node) or e.get("tag"), e["path"], node and node["line"],
                    [e.get("chrome_x"), e.get("chrome_y"), e.get("chrome_w"), e.get("chrome_h")],
                    [e.get("nativa_x"), e.get("nativa_y"), e.get("nativa_w"), e.get("nativa_h")],
                    [e.get("dx"), e.get("dy"), e.get("dw"), e.get("dh")], e.get("iou"), styles,
                    sources.css_rules(fdir, node, 3) if fdir else []]
        root_rows = [el_row(e) for e in roots[:4]]
        styles_by_path = {}
        chrome = load_json(pdir / "chrome.json") or {}
        for ce in chrome.get("elements") or []:
            styles_by_path[ce.get("path")] = (ce.get("styles") or {}).get("display")
        for e in roots[:4]:
            parent = e["path"].rsplit(">", 1)[0]
            disp = styles_by_path.get(parent)
            if disp in LAYOUT_FILE:
                code.setdefault(f"layout:{disp}", [LAYOUT_FILE[disp]])
        more = [[sources.selector_label(sources.element(str(fixture), e["path"])) if fixture else e.get("tag"),
                 [e.get("dx"), e.get("dy"), e.get("dw"), e.get("dh")], e.get("iou")]
                for e in divergent[len(root_rows):]]
        more, omitted = fit(more, 250)
        totals = pixels.get("totals") or {}
        tiles = [[t.get("x"), t.get("y"), r1(t.get("meanDeltaE") or t.get("deltaE"))]
                 for t in (pixels.get("worstTiles") or [])[:6] if isinstance(t, dict)]
        sc = report.get("scores") or {}
        vp = report.get("viewport") or {}
        detail = compact({
            "pg": page, "fx": rel(fixture) if fixture else None,
            "vp": [vp.get("width"), vp.get("height"), report.get("scheme")],
            "sc": compact({"o": r1(sc.get("overall"), 2), "pos": r1(sc.get("position"), 2), "lay": r1(sc.get("layout"), 2),
                           "col": r1(sc.get("color"), 2), "des": r1(sc.get("design"), 2)}),
            "why": report.get("reason"),
            "px": compact({"d": r1(r.get("mismatched_pct"), 2), "ink": r1(r.get("ink_mismatch_pct"), 2),
                           "me": r1(r.get("mean_delta_e"), 2), "mx": r1(r.get("max_delta_e"), 1)}),
            "prev": [old.get("overall"), delta] if old else None,
            "root": root_rows, "more": more, "o": omitted or None, "tiles": tiles,
            "code": code or None, "miss": [r.get("missing"), r.get("extra")] if r.get("missing") or r.get("extra") else None,
        })
        prio = 1 if verdict == "INVALID" or trend == "regressed" else (2 if verdict == "FAIL" else 3)
        first = root_rows[0] if root_rows else None
        if isinstance(r.get("overall"), (int, float)):
            headline = (f"{page} {verdict} {r1(r.get('overall'), 1)}% (pos {r1(r.get('position'), 0)} lay "
                        f"{r1(r.get('layout'), 0)} col {r1(r.get('color'), 0)} des {r1(r.get('design'), 0)})")
        else:
            headline = f"{page} {verdict}: {str(report.get('reason') or report.get('failure') or 'no score')[:140]}"
        headline += (f" · root {first[0]} Δ{first[5]}" if first else "") + (
            f" · {trend} {delta:+}" if trend and trend != "unchanged" else "")
        items.append(Item(
            id=stable_id("VIS", page.split("/")[-1], 60), area="visual", priority=prio, headline=headline,
            detail=detail, impact=100 - (r.get("overall") or 0), trend=trend,
            sources=[rel(pdir)],
            commands=[f"dart run debug/engines/visual_comparison/bin/visual_check.dart --only '{re.escape(page.split('/')[-1])}' "
                      f"--suite {r.get('suite')} --out /tmp/vis-check"],
            data=compact({"o": r1(r.get("overall"), 2), "v": verdict})))
    return summary, items


# -------------------------------------------------------------------- perf
def _work(e):
    return (e.get("scenario_ms") or 0) + (e.get("render_ms") or 0)


def perf(path: Path | None = None):
    if path is None:
        cands = [Path(p) for p in glob.glob(str(ART / "perf" / "**" / "results.json"), recursive=True)]
        cands += [Path(p) for p in glob.glob(str(ART / "runs" / "perf" / "*" / "evidence" / "results.json"))]
        path = _best(cands, lambda d: len(d.get("results") or []))
    if path is None:
        return {"state": "no performance results found"}, []
    data = load_json(path) or {}
    rows = data.get("results") or []
    prev = previous_comparable("perf", "scenarios", len(rows))
    prev_rows = {r.get("scenario"): r for r in ((prev or {}).get("data") or {}).get("results") or []}
    counts = {}
    for r in rows:
        counts[r.get("verdict")] = counts.get(r.get("verdict"), 0) + 1
    summary = compact({"src": rel(path), "scenarios": len(rows), "v": counts, "tgt": data.get("targets"),
                       "prev": rel(prev["run"]["file"]) if prev else None})
    items = []
    for r in rows:
        if r.get("verdict") == "PASS":
            continue
        n, c = r.get("nativax") or {}, r.get("chromium") or {}
        cmp_ = r.get("comparison") or {}

        def metrics(e):
            fr = e.get("frame_ms") or {}
            return compact({"s": r1(e.get("scenario_ms")), "ev": r1(e.get("eval_ms")), "ld": r1(e.get("load_ms")),
                            "r": r1(e.get("render_ms")), "p95": r1(fr.get("p95")), "mx": r1(fr.get("max")),
                            "nodes": e.get("nodes"), "rss": r1(e.get("rss_peak_mb"), 0),
                            "rsst": r1(e.get("rss_tail_mb"), 0), "cpu": r1(e.get("cpu_peak_pct"), 0),
                            "st": e.get("status") if e.get("status") != "ok" else None,
                            "err": e.get("error")})
        # The engine's work is scenario_ms + render_ms (evaluate.dart); load
        # time is not part of it, so it is reported but never "dominant".
        work = _work(n)
        parts = {"script": n.get("scenario_ms") or 0, "render": n.get("render_ms") or 0}
        dom = max(parts.items(), key=lambda kv: kv[1]) if work else None
        # Idle scenarios measure RSS/CPU, not work, so 0 ms is expected there.
        unmeasured = n.get("status") == "ok" and not work and r.get("kind") != "idle"
        old = prev_rows.get(r.get("scenario"))
        ratio = cmp_.get("work_ratio")
        if unmeasured:
            ratio = None  # a 0 ms NativaX work is a missing measurement, not a 0x ratio
        delta = trend = None
        if old and ratio is not None:
            oc = _work(old.get("chromium") or {})
            oratio = _work(old.get("nativax") or {}) / oc if oc > 0.0001 else None
            if oratio:
                delta = round(ratio - oratio, 3)
                trend = "regressed" if delta > oratio * 0.05 else "improved" if delta < -oratio * 0.05 else "unchanged"
        sid = str(r.get("scenario"))
        detail = compact({
            "k": r.get("kind"), "why": r.get("reasons"), "n": metrics(n), "c": metrics(c),
            "x": compact({"w": r1(ratio, 2), "s": r1(cmp_.get("scenario_ratio"), 2), "r": r1(cmp_.get("render_ratio"), 2),
                          "n": r1(cmp_.get("nodes_ratio"), 2)}),
            "dom": [dom[0], r1(dom[1] / (sum(parts.values()) or 1), 3)] if dom else None,
            "prev": [r1(delta and ratio - delta, 2), delta] if delta is not None else None,
            "code": list(code_refs(f"'{sid}'", ("debug/engines/performance/lib/src",), 2)) or None,
            "warn": "NativaX work is 0 ms with status ok: the scenario was not measured (budget or timeout); "
                    "the engine's ratio 0 must not be read as fast" if unmeasured else None,
        })
        failed = n.get("status") != "ok" or c.get("status") != "ok"
        prio = 1 if (failed and r.get("verdict") == "INVALID") or trend == "regressed" or unmeasured else (
            2 if r.get("verdict") in ("FAIL", "INVALID") else 3)
        headline = (f"{sid} {r.get('verdict')} " + ("NOT MEASURED (NativaX work 0 ms)" if unmeasured else f"work {r1(ratio, 2)}x") + (f" ({dom[0]} {round(100 * dom[1] / (sum(parts.values()) or 1))}%)" if dom else "")
                    + f" · {'; '.join(r.get('reasons') or [])[:140]}"
                    + (f" · {trend} {delta:+}" if trend and trend != "unchanged" else ""))
        items.append(Item(
            id=stable_id("PERF", sid, 60), area="perf", priority=prio, headline=headline, detail=detail,
            impact=ratio or 0, trend=trend, sources=[rel(path)],
            commands=[f"dart run debug/engines/performance/bin/perf.dart run --only '^{re.escape(sid)}$' --out /tmp/perf-check"],
            data=compact({"w": r1(ratio, 2), "v": r.get("verdict")})))
    return summary, items


# ------------------------------------------------------------- conformance
def _group_key(suite: str, test_id: str) -> str:
    if test_id.startswith("#"):            # numbered fixture cases (WPT URL): the suite is the group
        return suite
    if suite.startswith("test262"):
        return "/".join(test_id.split("/")[:3])
    if "#" in test_id and not test_id.startswith("#"):
        return test_id.split("#")[0]
    if "/" in test_id:
        return test_id.rsplit("/", 1)[0]
    return suite


def _jsonl(path: Path):
    try:
        with path.open(encoding="utf-8") as fh:
            return [json.loads(line) for line in fh if line.strip()]
    except (OSError, ValueError):
        return []


def _summary_rows(summary_path: Path, summary: dict):
    if summary.get("resultsFile"):
        return _jsonl(summary_path.parent / summary["resultsFile"])
    if summary.get("results"):
        return summary["results"]
    sibling = summary_path.with_name(summary_path.name.replace(".summary.json", ".jsonl"))
    return _jsonl(sibling) if sibling.exists() else []


def conformance(results_dir: Path | None = None):
    results_dir = results_dir or ART / "conformance" / "results"
    by_suite: dict[str, list[Path]] = {}
    for p in sorted(results_dir.glob("*.summary.json")):
        data = load_json(p) or {}
        if data.get("suite"):
            by_suite.setdefault(data["suite"], []).append(p)
    summary, items = {}, []
    for suite, paths in sorted(by_suite.items()):
        paths = sorted(paths, key=lambda q: q.name)
        cur_path = paths[-1]
        cur = load_json(cur_path) or {}
        rows = _summary_rows(cur_path, cur)
        counts = {str(k).lower(): v for k, v in (cur.get("counts") or {}).items()}
        rate = cur.get("passRate")
        summary[suite] = compact({"run": cur_path.name, "rate": r1(rate, 2), "n": counts})
        fails = [x for x in rows if x.get("status") in ("fail", "error")]
        prev_info = None
        if len(paths) > 1:
            prev_path = paths[-2]
            prev = load_json(prev_path) or {}
            prow = {x.get("id"): x.get("status") for x in _summary_rows(prev_path, prev)}
            if prow:
                new_fail = sum(1 for x in fails if prow.get(x.get("id")) == "pass")
                fixed = sum(1 for x in rows if x.get("status") == "pass" and prow.get(x.get("id")) in ("fail", "error"))
                prev_info = compact({"rate": r1(prev.get("passRate"), 2),
                                     "delta": r1((rate or 0) - (prev.get("passRate") or 0), 2) if rate is not None else None,
                                     "new_fail": new_fail, "fixed": fixed})
        if not fails:
            continue
        groups: dict[tuple, list] = {}
        for x in fails:
            key = (_group_key(suite, str(x.get("id"))), normalize_reason(x.get("reason") or x.get("message") or ""))
            groups.setdefault(key, []).append(x)
        ordered = sorted(groups.items(), key=lambda kv: -len(kv[1]))
        g_rows = [[where, reason, len(xs),
                   [[str(x.get("id"))[:160], str(x.get("reason") or "")[:200], str(x.get("detail") or "")[:300]]
                    for x in xs[:2]]] for (where, reason), xs in ordered]
        g_rows, omitted = fit(g_rows, DETAIL_BUDGET)
        trend = None
        if prev_info and prev_info.get("delta") is not None:
            trend = "regressed" if prev_info["delta"] < -0.1 else "improved" if prev_info["delta"] > 0.1 else "unchanged"
        top = ordered[0]
        headline = (f"{suite} {r1(rate, 2)}% pass · {len(fails)} failing in {len(groups)} groups · top: "
                    f"{top[0][0]} ×{len(top[1])} “{top[0][1][:80]}”"
                    + (f" · {trend} {prev_info['delta']:+} pts, {prev_info.get('new_fail', 0)} new fail"
                       if trend and trend != "unchanged" else ""))
        items.append(Item(
            id=stable_id("COMP", suite, 40), area="conformance", priority=1 if trend == "regressed" else 2,
            headline=headline, impact=len(fails), trend=trend,
            detail=compact({"s": suite, "run": rel(cur_path), "n": counts, "rate": r1(rate, 2), "prev": prev_info,
                            "g": g_rows, "o": omitted or None}),
            sources=[rel(cur_path)],
            commands=[f"cd debug/engines/compatibility && dart run bin/{cur.get('command') or 'run_all'}.dart"],
            data=compact({"rate": r1(rate, 2), "fail": len(fails)})))
    return summary, items


# ---------------------------------------------------- memory and security
def _latest_bench(area: str, prefix: str):
    """Newest run that covers the most cases: a `--only` run of 1 case is not
    the state of the area."""
    runs = sorted(p for p in (BENCH / area).glob("*") if p.is_dir()) if (BENCH / area).exists() else []
    best = None
    for run in runs:
        files = sorted(run.glob(f"{prefix}-*.json"))
        if not files:
            continue
        data = load_json(files[-1]) or {}
        size = len(data.get("results") or [])
        if best is None or size >= best[0]:
            best = (size, run, files[-1], data)
    return (best[1], best[2], best[3]) if best else (None, None, {})


def memory():
    run, path, data = _latest_bench("leaks", "leaks")
    if not path:
        return {"state": "no memory runs found"}, []
    results = data.get("results") or []
    counts = {}
    for r in results:
        st = str(r.get("status")).upper()
        counts[st] = counts.get(st, 0) + 1
    summary = compact({"run": rel(run), "cases": len(results), "v": counts,
                       "profile": (data.get("metadata") or {}).get("profile")})
    items = []
    for r in results:
        cls = (r.get("classification") or {}).get("class") if isinstance(r.get("classification"), dict) else None
        status = str(r.get("status")).upper()
        if status == "PASS" and cls in (None, "no_leak"):
            continue
        samples = [[s.get("batch"), r1((s.get("rssBytes") or 0) / 1048576, 1)] for s in (r.get("samples") or [])[:12]
                   if isinstance(s, dict)]
        ch = (r.get("classification") or {}).get("channels") if isinstance(r.get("classification"), dict) else None
        prio = 1 if cls == "proven_leak" else (2 if status in ("FAIL", "ERROR") or cls == "suspected_leak" else 3)
        items.append(Item(
            id=stable_id("MEM", str(r.get("id")), 60), area="memory", priority=prio,
            headline=f"{r.get('id')} {status}" + (f" class {cls}" if cls else "") + f" · {str(r.get('reason') or '')[:140]}",
            detail=compact({"case": r.get("id"), "st": status, "cls": cls, "why": r.get("reason"),
                            "ch": ch, "smp": samples, "ev": r.get("evidence")}),
            sources=[rel(path)], impact=0,
            commands=[f"cd debug/engines/memory && dart run bin/leaks.dart run --only {r.get('id')}"]))
    return summary, items


def security():
    run, path, data = _latest_bench("security", "security")
    if not path:
        return {"state": "no security runs found"}, []
    results = data.get("results") or []
    counts = {}
    for r in results:
        counts[str(r.get("status")).upper()] = counts.get(str(r.get("status")).upper(), 0) + 1
    summary = compact({"run": rel(run), "cases": len(results), "v": counts})
    items = []
    for r in results:
        status = str(r.get("status")).lower()
        if status == "pass":
            continue
        sev = r.get("severity")
        prio = 1 if status == "fail" and sev in ("critical", "high") else (2 if status == "fail" else 3)
        items.append(Item(
            id=stable_id("SEC", str(r.get("id")), 60), area="security", priority=prio,
            headline=f"{r.get('id')} {status.upper()} {sev} · expected {str(r.get('expected'))[:60]} · observed {str(r.get('observed'))[:60]}",
            detail=compact({"case": r.get("id"), "sev": sev, "cat": r.get("category"), "d": r.get("description"),
                            "exp": r.get("expected"), "obs": r.get("observed"), "fix": r.get("remediation"),
                            "ev": r.get("evidence")}),
            sources=[rel(path)],
            commands=[f"cd debug/engines/security && dart run bin/security.dart run --only {r.get('id')}"]))
    return summary, items


# -------------------------------------------------------------------- audit
def audit(run_dir: Path | None = None):
    run_dir = run_dir or ART / "audit" / "latest"
    summary_doc = load_json(run_dir / "summary.json")
    if not summary_doc:
        return {"state": "no audit run found"}, []
    m = summary_doc.get("metrics") or {}
    summary = compact({"run": summary_doc.get("run_id"), "executed": m.get("executed"),
                       "issues": m.get("unique_issues"), "reproducible": m.get("reproducible")})
    items = []
    for path in sorted((run_dir / "issues").glob("NX-*.json")):
        rep = load_json(path)
        if not rep or rep.get("status") != "failed":
            continue
        c, loc, re_ = rep.get("classification") or {}, rep.get("location") or {}, rep.get("reproduction") or {}
        mini = re_.get("minimization") or {}
        sev = rep.get("severity")
        prio = 1 if sev in ("critical",) else (2 if sev == "high" else 3)
        hyps = [[h.get("status"), h.get("statement")] for h in (rep.get("root_cause") or {}).get("hypotheses") or []]
        files = [[f"{f.get('file')}:{f.get('line')}" if f.get("line") else f.get("file"), f.get("basis")]
                 for f in (rep.get("investigation") or {}).get("files_to_inspect") or []][:6]
        minimal = re_.get("minimal_scenario")
        detail = compact({
            "iss": rep.get("issue_id"), "k": c.get("kind"), "sub": c.get("subsystem"), "stage": c.get("stage"),
            "comp": c.get("component_types"), "prop": c.get("property"),
            "loc": compact({k: loc.get(k) for k in ("element_id", "json_path", "minimal_json_path", "source_file",
                                                     "symbol", "line")}),
            "exp": rep.get("expected"), "act": rep.get("actual"),
            "min": compact({"screen": (minimal or {}).get("screen"), "env": (minimal or {}).get("environment"),
                            "actions": (minimal or {}).get("actions")}) if minimal else None,
            "need": [n.get("description") for n in mini.get("necessary_conditions") or []] or None,
            "hyp": hyps, "files": files, "fix": rep.get("fix_requirements"), "acc": rep.get("acceptance_criteria"),
            "n": (rep.get("occurrences") or {}).get("count"),
        })
        items.append(Item(
            id=rep.get("issue_id"), area="audit", priority=prio,
            headline=" ".join(x for x in (
                sev, c.get("kind"), c.get("subsystem"), ",".join((c.get("component_types") or [])[:2]),
                c.get("property"), f"×{(rep.get('occurrences') or {}).get('count')}") if x)
            + f" · {(rep.get('evidence') or {}).get('message', '')[:110]}",
            detail=detail, impact=(rep.get("occurrences") or {}).get("count") or 0,
            sources=[rel(path)], commands=[re_.get("command")] if re_.get("command") else []))
    return summary, items


DIGESTERS = {"visual": visual, "perf": perf, "conformance": conformance, "memory": memory,
             "security": security, "audit": audit}

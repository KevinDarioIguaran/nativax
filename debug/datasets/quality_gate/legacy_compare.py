"""The quality-gate comparison as it was before per-metric tolerances
(commit f47240e, debug/engines/quality_gate/quality_gate.py), kept verbatim
as the reference for the accuracy table in
debug/architecture/metrics-gate-compat.md. Not used by the gate.
"""


def compare(current, baseline):
    changes = []
    if not baseline:
        return {"verdict": "BASELINE", "changes": [], "regressions": [], "improvements": []}

    def add(area, name, before, after, unit="", higher_is_better=True, tolerance=0.5):
        if before is None or after is None:
            return
        delta = after - before
        status = "equal"
        if abs(delta) < tolerance:
            status = "equal"
        elif (delta > 0) == higher_is_better:
            status = "better"
        else:
            status = "worse"
        changes.append({
            "area": area,
            "metric": name,
            "before": before,
            "after": after,
            "delta": delta,
            "unit": unit,
            "status": status,
        })

    visual_now = current.get("visual") or {}
    visual_base = baseline.get("visual") or {}
    for key in ("overall", "position", "layout", "color", "design"):
        add("visual", key, (visual_base.get("categories") or {}).get(key),
            (visual_now.get("categories") or {}).get(key), " %", True, 0.5)
    for verdict in ("PASS", "FAIL"):
        add("visual", f"{verdict} pages",
            (visual_base.get("verdicts") or {}).get(verdict),
            (visual_now.get("verdicts") or {}).get(verdict),
            "", verdict == "PASS", 0.5)
    add("visual", "ink %", visual_base.get("mean_ink_pct"),
        visual_now.get("mean_ink_pct"), " %", False, 1.0)
    add("visual", "images", visual_base.get("images"),
        visual_now.get("images"), "", True, 0.5)

    perf_now = current.get("perf") or {}
    perf_base = baseline.get("perf") or {}
    for scenario, after in (perf_now.get("work") or {}).items():
        before = (perf_base.get("work") or {}).get(scenario)
        if before is None:
            continue
        add("performance", scenario, before, after, " ms", False, 10.0)
    for verdict in ("PASS", "FAIL"):
        add("performance", f"{verdict} scenarios",
            (perf_base.get("verdicts") or {}).get(verdict),
            (perf_now.get("verdicts") or {}).get(verdict),
            "", verdict == "PASS", 0.5)
    idle_now = (perf_now.get("idle") or {})
    idle_base = (perf_base.get("idle") or {})
    add("idle", "RSS MB", idle_base.get("rss_mb"), idle_now.get("rss_mb"), " MB", False, 5.0)
    add("idle", "CPU %", idle_base.get("cpu_pct"), idle_now.get("cpu_pct"), " %", False, 0.25)

    compat_now = current.get("compat") or {}
    compat_base = baseline.get("compat") or {}
    for suite, after in compat_now.items():
        before = (compat_base.get(suite) or {}).get("passRate")
        if before is None:
            continue
        add("compatibility", suite, before, after.get("passRate"), " %", True, 0.5)

    regressions = [change for change in changes if change["status"] == "worse"]
    improvements = [change for change in changes if change["status"] == "better"]
    verdict = "EQUAL"
    if regressions and not improvements:
        verdict = "WORSE"
    elif regressions and improvements:
        verdict = "MIXED"
    elif improvements:
        verdict = "BETTER"
    return {
        "verdict": verdict,
        "changes": changes,
        "regressions": regressions,
        "improvements": improvements,
    }


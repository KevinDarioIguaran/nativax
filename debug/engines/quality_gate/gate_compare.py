"""Pure comparison logic for the NativaX quality gate.

No I/O here: `quality_gate.py` builds snapshots from artifacts, this module
decides, metric by metric, whether a change is real. Everything is
deterministic and documented in debug/architecture/metrics-gate-compat.md.

A snapshot is a dict with the sections ``visual``, ``perf`` and ``compat``
(as written by quality_gate.py), plus two optional sections:

* ``context``: ``{area: {key: value}}`` describing what was measured and
  where (catalog size and digest, tool/runner/suite version, environment
  class, engine, configuration). ``global`` applies to every area.
* ``noise``: ``{metric_id: {"sd": float, "n": int}}`` from repeated runs
  (see :func:`aggregate`).
"""
from __future__ import annotations

import hashlib
import math
from dataclasses import dataclass

STATUSES = ("improved", "regressed", "unchanged", "inconclusive", "not_comparable")

# Confidence multiplier on the standard error of the difference. 3 keeps the
# false-alarm rate near 0.3 % for normally distributed noise.
NOISE_K = 3.0


@dataclass(frozen=True)
class MetricSpec:
    """How one metric is judged.

    ``abs_tol``/``rel_tol`` give the smallest change that matters in
    practice: ``min_effect = max(abs_tol, rel_tol * |before|)``.
    ``assumed_sd_abs``/``assumed_sd_rel`` are the run-to-run standard
    deviation assumed when no repeated runs are provided (0 for
    deterministic metrics). They are priors, not measurements.
    """

    area: str
    unit: str
    higher_is_better: bool
    abs_tol: float
    rel_tol: float = 0.0
    assumed_sd_abs: float = 0.0
    assumed_sd_rel: float = 0.0


# Areas: visual, performance, idle, compatibility/<suite>.
VISUAL_SCORE = MetricSpec("visual", "pp", True, 0.5)
VISUAL_PAGES_PASS = MetricSpec("visual", "pages", True, 0.5)
VISUAL_PAGES_FAIL = MetricSpec("visual", "pages", False, 0.5)
VISUAL_MISMATCH = MetricSpec("visual", "pp", False, 0.1)
VISUAL_INK = MetricSpec("visual", "pp", False, 1.0)
PERF_WORK = MetricSpec("performance", "ms", False, 1.0, rel_tol=0.10,
                       assumed_sd_abs=0.5, assumed_sd_rel=0.05)
PERF_SCENARIOS_PASS = MetricSpec("performance", "scenarios", True, 0.5)
PERF_SCENARIOS_FAIL = MetricSpec("performance", "scenarios", False, 0.5)
IDLE_RSS = MetricSpec("idle", "MB", False, 5.0, assumed_sd_abs=2.0)
IDLE_CPU = MetricSpec("idle", "pp", False, 0.25, assumed_sd_abs=0.2)
COMPAT_RATE = MetricSpec("compatibility", "pp", True, 0.01)
COMPAT_PASSED = MetricSpec("compatibility", "tests", True, 0.5)


def _get(data, *path):
    for key in path:
        if not isinstance(data, dict):
            return None
        data = data.get(key)
    return data


def _num(value):
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)) and math.isfinite(value):
        return float(value)
    return None


def flatten(snapshot):
    """Returns ``{metric_id: (spec, value)}`` for every known metric.

    ``metric_id`` is ``"<area>/<name>"``; compatibility areas are
    ``"compatibility/<suite>"``.
    """
    out = {}

    def put(metric_id, spec, value):
        value = _num(value)
        if value is not None:
            out[metric_id] = (spec, value)

    visual = snapshot.get("visual") or {}
    for key in ("overall", "position", "layout", "color", "design"):
        put(f"visual/{key}", VISUAL_SCORE, _get(visual, "categories", key))
    put("visual/PASS pages", VISUAL_PAGES_PASS, _get(visual, "verdicts", "PASS"))
    put("visual/FAIL pages", VISUAL_PAGES_FAIL, _get(visual, "verdicts", "FAIL"))
    put("visual/mismatched %", VISUAL_MISMATCH, visual.get("mismatched_pct"))
    put("visual/ink %", VISUAL_INK, visual.get("mean_ink_pct"))

    perf = snapshot.get("perf") or {}
    for scenario, work in (perf.get("work") or {}).items():
        put(f"performance/{scenario}", PERF_WORK, work)
    put("performance/PASS scenarios", PERF_SCENARIOS_PASS, _get(perf, "verdicts", "PASS"))
    put("performance/FAIL scenarios", PERF_SCENARIOS_FAIL, _get(perf, "verdicts", "FAIL"))
    put("idle/RSS MB", IDLE_RSS, _get(perf, "idle", "rss_mb"))
    put("idle/CPU %", IDLE_CPU, _get(perf, "idle", "cpu_pct"))

    for suite, data in (snapshot.get("compat") or {}).items():
        area = f"compatibility/{suite}"
        put(f"{area}/passRate", _with_area(COMPAT_RATE, area), (data or {}).get("passRate"))
        put(f"{area}/PASS tests", _with_area(COMPAT_PASSED, area),
            _get(data, "counts", "PASS"))
    return out


def _with_area(spec, area):
    return MetricSpec(area, spec.unit, spec.higher_is_better, spec.abs_tol,
                      spec.rel_tol, spec.assumed_sd_abs, spec.assumed_sd_rel)


def area_of(metric_id):
    head, _, rest = metric_id.partition("/")
    if head == "compatibility":
        return "compatibility/" + rest.split("/", 1)[0]
    return head


def area_context(snapshot, area):
    """Context that must match for ``area``: global keys plus area keys.

    For ``compatibility/<suite>`` the suite's own summary fields (total
    tests, suite revision, runner version, command) are used as well.
    """
    context = snapshot.get("context") or {}
    merged = dict(context.get("global") or {})
    merged.update(context.get(area) or {})
    if area.startswith("compatibility/"):
        suite = area.split("/", 1)[1]
        data = (snapshot.get("compat") or {}).get(suite) or {}
        counts = data.get("counts") or {}
        if counts:
            merged.setdefault("total_tests", sum(v for v in counts.values()
                                                 if isinstance(v, (int, float))))
        for key in ("suiteCommit", "runnerVersion", "command"):
            if key in data:
                merged.setdefault(key, data.get(key))
    return merged


def comparability(baseline, current, area):
    """Returns ``(comparable, reasons, unverified_keys)``.

    A key that differs, or that only one side records, makes the area not
    comparable. Keys neither side records are listed as unverified.
    """
    before = area_context(baseline, area)
    after = area_context(current, area)
    reasons = []
    for key in sorted(set(before) | set(after)):
        if key not in before:
            reasons.append(f"{key}: not recorded in the baseline")
        elif key not in after:
            reasons.append(f"{key}: not recorded in the current run")
        elif before[key] != after[key]:
            reasons.append(f"{key}: {before[key]!r} -> {after[key]!r}")
    required = REQUIRED_CONTEXT.get(area.split("/", 1)[0], ())
    unverified = [key for key in required if key not in before and key not in after]
    return not reasons, reasons, unverified


# Keys a snapshot should record for each area. Missing on both sides does
# not block the comparison, but it is reported as unverified.
REQUIRED_CONTEXT = {
    "visual": ("environment_class", "catalog_size", "catalog_digest", "tool_version",
               "reference", "viewport"),
    "performance": ("environment_class", "catalog_size", "catalog_digest", "tool_version",
                    "engine", "reference", "viewport"),
    "idle": ("environment_class",),
    "compatibility": ("total_tests", "suiteCommit", "runnerVersion", "command"),
}


def _noise_sd(snapshot, metric_id, spec, value):
    noise = (snapshot.get("noise") or {}).get(metric_id)
    if isinstance(noise, dict) and _num(noise.get("sd")) is not None:
        n = int(noise.get("n") or 1)
        return float(noise["sd"]), max(n, 1), True
    assumed = max(spec.assumed_sd_abs, spec.assumed_sd_rel * abs(value))
    return assumed, 1, False


def judge(spec, before, after, before_noise=(0.0, 1), after_noise=(0.0, 1)):
    """Status of one comparable metric, and the numbers behind it."""
    delta = after - before
    min_effect = max(spec.abs_tol, spec.rel_tol * abs(before))
    sd_b, n_b = before_noise
    sd_a, n_a = after_noise
    se = math.sqrt(sd_b * sd_b / n_b + sd_a * sd_a / n_a)
    noise_threshold = NOISE_K * se
    if abs(delta) < min_effect:
        status = "unchanged"
    elif abs(delta) <= noise_threshold:
        status = "inconclusive"
    elif (delta > 0) == spec.higher_is_better:
        status = "improved"
    else:
        status = "regressed"
    return status, {
        "delta": delta,
        "min_effect": min_effect,
        "noise_threshold": noise_threshold,
    }


def compare(current, baseline):
    """Compares two snapshots. Returns the comparison dict."""
    if not baseline:
        return {"verdict": "no_baseline", "changes": [], "areas": {},
                "counts": {s: 0 for s in STATUSES}}
    now = flatten(current)
    base = flatten(baseline)
    areas = {}
    for metric_id in set(now) | set(base):
        area = area_of(metric_id)
        if area not in areas:
            comparable, reasons, unverified = comparability(baseline, current, area)
            areas[area] = {"comparable": comparable, "reasons": reasons,
                           "unverified": unverified}

    changes = []
    for metric_id in sorted(set(now) | set(base)):
        area = area_of(metric_id)
        spec = (now.get(metric_id) or base.get(metric_id))[0]
        before = base.get(metric_id, (None, None))[1]
        after = now.get(metric_id, (None, None))[1]
        change = {
            "area": area,
            "metric": metric_id.split("/", 2 if area.startswith("compatibility/") else 1)[-1],
            "id": metric_id,
            "before": before,
            "after": after,
            "unit": spec.unit,
            "higher_is_better": spec.higher_is_better,
        }
        if not areas[area]["comparable"]:
            change.update(status="not_comparable", reason="; ".join(areas[area]["reasons"]))
        elif before is None or after is None:
            change.update(status="not_comparable",
                          reason="missing in the " + ("baseline" if before is None else "current run"))
        else:
            sd_b, n_b, measured_b = _noise_sd(baseline, metric_id, spec, before)
            sd_a, n_a, measured_a = _noise_sd(current, metric_id, spec, after)
            status, numbers = judge(spec, before, after, (sd_b, n_b), (sd_a, n_a))
            change.update(status=status, noise_source="measured" if (measured_b or measured_a)
                          else ("assumed" if (sd_b or sd_a) else "none"), **numbers)
        changes.append(change)

    counts = {s: sum(1 for c in changes if c["status"] == s) for s in STATUSES}
    return {
        "verdict": overall(counts),
        "counts": counts,
        "areas": areas,
        "changes": changes,
        "regressions": [c for c in changes if c["status"] == "regressed"],
        "improvements": [c for c in changes if c["status"] == "improved"],
    }


def overall(counts):
    """Precedence: regressed > not_comparable > improved > inconclusive >
    unchanged. A regression in a comparable area is reported even when other
    areas are not comparable; an improvement is never claimed while any
    metric is not comparable."""
    for status in ("regressed", "not_comparable", "improved", "inconclusive"):
        if counts.get(status):
            return status
    return "unchanged"


def aggregate(snapshots):
    """Mean of repeated snapshots plus a ``noise`` section (sample sd, n).

    The first snapshot provides the structure and context; every snapshot
    must have the same context, otherwise ValueError is raised.
    """
    if not snapshots:
        raise ValueError("no snapshots to aggregate")
    first = snapshots[0]
    for other in snapshots[1:]:
        if (other.get("context") or {}) != (first.get("context") or {}):
            raise ValueError("repeated snapshots have different contexts")
    flats = [flatten(s) for s in snapshots]
    import copy

    result = copy.deepcopy(first)
    noise = {}
    for metric_id in flats[0]:
        values = [f[metric_id][1] for f in flats if metric_id in f]
        n = len(values)
        mean = sum(values) / n
        sd = math.sqrt(sum((v - mean) ** 2 for v in values) / (n - 1)) if n > 1 else 0.0
        noise[metric_id] = {"sd": sd, "n": n}
        _set_metric(result, metric_id, mean)
    result["noise"] = noise
    result["repeats"] = len(snapshots)
    return result


def _set_metric(snapshot, metric_id, value):
    area, _, name = metric_id.partition("/")
    if area == "visual":
        visual = snapshot["visual"]
        if name in ("overall", "position", "layout", "color", "design"):
            visual["categories"][name] = value
        elif name == "PASS pages":
            visual["verdicts"]["PASS"] = value
        elif name == "FAIL pages":
            visual["verdicts"]["FAIL"] = value
        elif name == "mismatched %":
            visual["mismatched_pct"] = value
        elif name == "ink %":
            visual["mean_ink_pct"] = value
    elif area == "performance":
        perf = snapshot["perf"]
        if name == "PASS scenarios":
            perf["verdicts"]["PASS"] = value
        elif name == "FAIL scenarios":
            perf["verdicts"]["FAIL"] = value
        else:
            perf["work"][name] = value
    elif area == "idle":
        key = "rss_mb" if name == "RSS MB" else "cpu_pct"
        snapshot["perf"]["idle"][key] = value
    elif area == "compatibility":
        suite, _, field = name.partition("/")
        data = snapshot["compat"][suite]
        if field == "passRate":
            data["passRate"] = value
        else:
            data.setdefault("counts", {})["PASS"] = value


def digest(names):
    """Stable digest of a catalog (sorted names), 16 hex characters."""
    joined = "\n".join(sorted(str(n) for n in names))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]

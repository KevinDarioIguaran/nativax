"""Did it improve? Deterministic comparison of two archived runs of one area.

    python3 debug/logic/compare_runs.py visual <older_run_id> <newer_run_id> [--record]

Algorithm (also documented in debug/architecture/storage.md):

1. **Comparability.** Both runs must be archived runs of the same area with
   the same `lineage_key` (same engine, same configuration). Otherwise the
   result is `not_comparable` and no metric is judged. A 1.0 manifest has no
   key, so the result is `inconclusive` ("lineage unknown").
2. **Per item.** Items are matched by id (visual: page, perf: scenario). An
   item is `improved` / `regressed` when its metric moves by more than the
   noise floor in the better / worse direction, `unchanged` within it, and
   `added` / `removed` when only one run has it. Noise floors are explicit
   arguments with documented defaults; they are recorded in the result.
3. **Overall.** `regressed` if any item regressed, else `improved` if any
   item improved, else `unchanged`; `inconclusive` when no item could be
   judged (no shared items, or every metric missing). Items only present in
   one run never count as improvements: a smaller run is not a better run.

The result can be appended to the newer run's history (`--record`); runs
themselves are never modified.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_LOGIC = Path(__file__).resolve().parent
if str(_LOGIC) not in sys.path:
    sys.path.insert(0, str(_LOGIC))

import storage  # noqa: E402

# Default noise floors. Visual scores are percentages (0-100); the judge's
# Chromium-vs-Chromium self-check scores 100, so 0.5 points is a conservative
# floor for rendering noise. Perf work ratios vary between runs on the same
# machine; 15 % relative change is the floor unless measured noise is passed.
VISUAL_NOISE_POINTS = 0.5
PERF_NOISE_RELATIVE = 0.15


def _load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def visual_items(run_dir: Path) -> dict[str, float | None]:
    data = _load_json(run_dir / "evidence" / "results.json") or {}
    return {r.get("page"): r.get("overall") for r in data.get("rows") or [] if r.get("page")}


def perf_items(run_dir: Path) -> dict[str, float | None]:
    data = _load_json(run_dir / "evidence" / "results.json") or {}
    out = {}
    for r in data.get("results") or []:
        n, c = r.get("nativax") or {}, r.get("chromium") or {}
        if n.get("status") != "ok" or c.get("status") != "ok":
            out[r.get("scenario")] = None
            continue
        nw = (n.get("scenario_ms") or 0) + (n.get("render_ms") or 0)
        cw = (c.get("scenario_ms") or 0) + (c.get("render_ms") or 0)
        out[r.get("scenario")] = nw / cw if cw > 0.0001 else None
    return out


EXTRACTORS = {
    # area: (items, higher_is_better, kind of noise floor, default floor)
    "visual": (visual_items, True, "absolute", VISUAL_NOISE_POINTS),
    "perf": (perf_items, False, "relative", PERF_NOISE_RELATIVE),
}


def compare(area: str, older: Path, newer: Path, *, noise: float | None = None) -> dict:
    older, newer = Path(older), Path(newer)
    ma, mb = storage.load_manifest(older), storage.load_manifest(newer)
    result = {"area": area, "older": older.name, "newer": newer.name, "status": None,
              "reason": None, "noise": None, "items": [], "counts": {},
              "algorithm": "debug/logic/compare_runs.py v1 (see module docstring)"}
    if ma is None or mb is None:
        result.update(status="inconclusive", reason="a manifest is missing or invalid")
        return result
    if ma["area"] != area or mb["area"] != area:
        result.update(status="not_comparable", reason=f"runs are not both '{area}' runs")
        return result
    ka, kb = ma.get("lineage_key"), mb.get("lineage_key")
    if ka is None or kb is None:
        result.update(status="inconclusive",
                      reason="lineage unknown (schema 1.0 manifest): configuration equality cannot be checked")
        return result
    if ka != kb:
        result.update(status="not_comparable",
                      reason=f"different configuration (lineage {ka} vs {kb})")
        return result
    if area not in EXTRACTORS:
        result.update(status="inconclusive", reason=f"no metric extractor for area '{area}'")
        return result
    items_fn, higher_better, noise_kind, default = EXTRACTORS[area]
    floor = default if noise is None else noise
    result["noise"] = {"kind": noise_kind, "value": floor, "source": "default" if noise is None else "argument"}
    a, b = items_fn(older), items_fn(newer)
    rows = []
    for key in sorted(set(a) | set(b), key=str):
        va, vb = a.get(key), b.get(key)
        if key not in a:
            status = "added"
        elif key not in b:
            status = "removed"
        elif va is None or vb is None:
            status = "unmeasured"
        else:
            delta = vb - va
            threshold = floor if noise_kind == "absolute" else abs(va) * floor
            if abs(delta) <= threshold:
                status = "unchanged"
            elif (delta > 0) == higher_better:
                status = "improved"
            else:
                status = "regressed"
        rows.append({"id": key, "before": va, "after": vb,
                     "delta": (vb - va) if isinstance(va, (int, float)) and isinstance(vb, (int, float)) else None,
                     "status": status})
    counts: dict[str, int] = {}
    for r in rows:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    judged = counts.get("improved", 0) + counts.get("regressed", 0) + counts.get("unchanged", 0)
    if judged == 0:
        overall, reason = "inconclusive", "no shared item with both measurements"
    elif counts.get("regressed"):
        overall, reason = "regressed", f"{counts['regressed']} item(s) regressed beyond the noise floor"
    elif counts.get("improved"):
        overall, reason = "improved", f"{counts['improved']} item(s) improved, none regressed"
    else:
        overall, reason = "unchanged", "every shared item within the noise floor"
    result.update(status=overall, reason=reason, items=rows, counts=counts)
    return result


def record(area: str, older: Path, newer: Path, result: dict) -> Path:
    """Appends the comparison to the newer run's history."""
    summary = {k: result[k] for k in ("area", "older", "newer", "status", "reason", "noise", "counts",
                                      "algorithm")}
    summary["items"] = [r for r in result["items"] if r["status"] in ("improved", "regressed")][:500]
    return storage.append_history(newer, "comparison", summary, author="debug/logic/compare_runs.py",
                                  refs=[Path(older).name])


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("area")
    p.add_argument("older")
    p.add_argument("newer")
    p.add_argument("--noise", type=float, help="override the noise floor (see docstring for units)")
    p.add_argument("--record", action="store_true", help="append the result to the newer run's history")
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)
    base = storage.RUNS_ROOT / args.area
    older, newer = base / args.older, base / args.newer
    result = compare(args.area, older, newer, noise=args.noise)
    if args.record and result["status"] in ("improved", "regressed", "unchanged"):
        print(f"recorded: {record(args.area, older, newer, result)}", file=sys.stderr)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"{result['status']}: {result['reason']}")
        for k, v in sorted(result["counts"].items()):
            print(f"  {k}: {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

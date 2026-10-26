#!/usr/bin/env python3
"""Evidence-based recommendations for NativaX quality reports.

This is a deterministic rule engine, not a black-box model. Every
recommendation must point to measured evidence, state a concrete acceptance
criterion, and avoid invented speedups or compatibility claims.
"""
from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[3]


@dataclass
class Recommendation:
    priority: str
    area: str
    title: str
    evidence: list[str] = field(default_factory=list)
    action: str = ""
    acceptance: str = ""
    confidence: str = "medium"
    commands: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def _rows(payload: Any, key: str) -> list[dict]:
    if not isinstance(payload, dict):
        return []
    value = payload.get(key)
    return value if isinstance(value, list) else []


def _num(value: Any, digits: int = 1, dash: str = "—") -> str:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return dash
    if not math.isfinite(number):
        return dash
    return f"{number:.{digits}f}"


def _work(row: dict, engine: str) -> float:
    data = row.get(engine) or {}
    return float(data.get("scenario_ms") or 0) + float(data.get("render_ms") or 0)


def _ratio(row: dict) -> float | None:
    chromium = _work(row, "chromium")
    nativax = _work(row, "nativax")
    if chromium <= 0.0001:
        return None
    return nativax / chromium


def _ratio_label(row: dict) -> str:
    ratio = _ratio(row)
    return f"{ratio:.2f}×" if ratio is not None else "—"


def _is_ok(row: dict) -> bool:
    return (
        (row.get("nativax") or {}).get("status") == "ok"
        and (row.get("chromium") or {}).get("status") == "ok"
    )


def _latest_json(folder: Path) -> dict | None:
    if not folder.exists():
        return None
    candidates = sorted(
        (p for p in folder.glob("*.json") if p.is_file()),
        key=lambda p: p.stat().st_mtime_ns,
        reverse=True,
    )
    for path in candidates:
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict):
            data.setdefault("_path", str(path))
            return data
    return None


_LATEST_CACHE: dict[str, tuple[int, dict | None]] = {}


def load_latest_run(folder: Path) -> dict | None:
    """Loads the newest JSON report in a benchmark folder, cached by mtime."""
    if not folder.exists():
        return None
    files = [p for p in folder.glob("*.json") if p.is_file()]
    if not files:
        return None
    newest = max(files, key=lambda p: p.stat().st_mtime_ns)
    mtime = newest.stat().st_mtime_ns
    key = str(folder.resolve())
    cached = _LATEST_CACHE.get(key)
    if cached is not None and cached[0] == mtime:
        return cached[1]
    data = _latest_json(folder)
    _LATEST_CACHE[key] = (mtime, data)
    return data


def collect(root: Path = ROOT) -> dict[str, Any]:
    """Loads the standard files used by the standalone report command."""
    visual = None
    for candidate in (
        root / ".visual" / "latest" / "results.json",
        root / ".visual" / "runs" / "50projects50days" / "results.json",
    ):
        if candidate.exists():
            try:
                visual = json.loads(candidate.read_text())
            except json.JSONDecodeError:
                continue
            if visual:
                break
    perf = None
    perf_path = root / ".perf" / "latest" / "results.json"
    if perf_path.exists():
        try:
            perf = json.loads(perf_path.read_text())
        except json.JSONDecodeError:
            perf = None
    app_idle = None
    for candidate in (
        root / ".perf" / "latest" / "app-idle.json",
        root / ".perf" / "app-idle.json",
    ):
        if candidate.exists():
            try:
                app_idle = json.loads(candidate.read_text())
            except json.JSONDecodeError:
                continue
            if app_idle:
                break
    matrix = None
    matrix_path = root / ".perf" / "container" / "matrix.json"
    if matrix_path.exists():
        try:
            matrix = json.loads(matrix_path.read_text())
        except json.JSONDecodeError:
            matrix = None
    catalogs = {}
    for name, path in (
        ("perf", root / "debug" / "engines" / "performance" / "scenarios.json"),
        ("visual", root / ".visual" / "catalog.json"),
    ):
        if path.exists():
            try:
                value = json.loads(path.read_text())
                if isinstance(value, list):
                    catalogs[name] = value
            except json.JSONDecodeError:
                pass
    game = None
    game_path = root / ".perf" / "game" / "results.json"
    if game_path.exists():
        try:
            game = json.loads(game_path.read_text())
        except json.JSONDecodeError:
            game = None
    game3d = None
    game3d_path = root / ".perf" / "game3d" / "results.json"
    if game3d_path.exists():
        try:
            game3d = json.loads(game3d_path.read_text())
        except json.JSONDecodeError:
            game3d = None
    video = None
    video_path = root / "tools" / "video_profiles.json"
    if video_path.exists():
        try:
            video = json.loads(video_path.read_text())
        except json.JSONDecodeError:
            video = None
    return {
        "visual": visual,
        "perf": perf,
        "game": game,
        "game3d": game3d,
        "video": video,
        "app_idle": app_idle,
        "matrix": matrix,
        "perf_catalog": catalogs.get("perf", []),
        "visual_catalog": catalogs.get("visual", []),
        "leaks": load_latest_run(root / "benchmarks" / "leaks"),
        "security": load_latest_run(root / "benchmarks" / "security"),
        "capabilities": {"video": False, "game_player": False},
    }


def _visual_categories(rows: list[dict]) -> dict[str, float]:
    result = {}
    for key, label in (
        ("position", "Position"),
        ("layout", "Layout"),
        ("color", "Color"),
        ("design", "Design"),
        ("overall", "Overall"),
    ):
        values = [
            float(row[key])
            for row in rows
            if isinstance(row.get(key), (int, float))
        ]
        result[label] = sum(values) / len(values) if values else 0.0
    return result


def build_recommendations(data: dict[str, Any]) -> list[Recommendation]:
    """Derives prioritized recommendations from current measured data.

    The rules are deliberately conservative: missing data produces a coverage
    recommendation, never a fabricated failure.
    """
    recommendations: list[Recommendation] = []
    visual_payload = data.get("visual") or {}
    perf_payload = data.get("perf") or {}
    visual_rows = _rows(visual_payload, "rows")
    perf_rows = _rows(perf_payload, "results")
    game_payload = data.get("game") or {}
    game3d_payload = data.get("game3d") or {}
    game_rows = _rows(game_payload, "results")
    visual_catalog = data.get("visual_catalog") or []
    perf_catalog = data.get("perf_catalog") or []
    app = data.get("app_idle") or {}
    leaks = data.get("leaks") or {}
    security = data.get("security") or {}
    capabilities = data.get("capabilities") or {}

    # --- Verification coverage ------------------------------------------------
    visual_total = len(visual_catalog) or len(visual_rows)
    perf_total = len(perf_catalog) or len(perf_rows)
    visual_coverage = (len(visual_rows) / visual_total) if visual_total else 0.0
    perf_coverage = (len(perf_rows) / perf_total) if perf_total else 0.0
    if visual_total and len(visual_rows) < visual_total:
        recommendations.append(Recommendation(
            priority="P2",
            area="visual coverage",
            title=f"{visual_total - len(visual_rows)} visual pages are still unmeasured",
            evidence=[
                f"{len(visual_rows)}/{visual_total} pages have a measured result.",
                "Without that sample, fidelity cannot be extrapolated to the full catalog.",
            ],
            action="Run the full visual catalog and review the new pages.",
            acceptance=(
                f"{visual_total}/{visual_total} pages measured; overall and ink "
                "reported with no pending samples."
            ),
            confidence="high" if visual_total >= 100 else "medium",
            commands=[
                "dart run debug/engines/visual_comparison/bin/visual_check.dart --all "
                "--catalog .visual/catalog.json --out .visual/latest",
            ],
        ))
    if perf_total and len(perf_rows) < perf_total:
        recommendations.append(Recommendation(
            priority="P2",
            area="performance coverage",
            title=f"{perf_total - len(perf_rows)} performance scenarios are still unmeasured",
            evidence=[
                f"{len(perf_rows)}/{perf_total} scenarios measured.",
                "The table shows pending rows; no global rate can be declared "
                "and not every workload type can be compared.",
            ],
            action=(
                "Run the base batch first and then the matrix scenarios; "
                "do not mix a short pass with a global claim."
            ),
            acceptance=(
                f"{perf_total}/{perf_total} scenarios executed, at least 3 "
                "rounds in release/AOT for the final decision."
            ),
            confidence="high",
            commands=[
                "dart run debug/engines/performance/bin/perf.dart run --out .perf/latest",
            ],
        ))
    if not app or app.get("status") != "ok":
        recommendations.append(Recommendation(
            priority="P1",
            area="memory",
            title="The real idle app measurement is missing",
            evidence=[
                "The test harness RSS includes Flutter/Dart and does not represent "
                "the app's consumption.",
                "There is no `app-idle.json` with RSS/CPU of the real process.",
            ],
            action="Measure the real Linux app on a blank page, with warm-up and idle time.",
            acceptance="Peak and steady RSS ≤250 MB and CPU ≤1 % in the real app.",
            confidence="high",
            commands=["dart run debug/engines/performance/bin/perf.dart idle-app --seconds 5"],
        ))

    # --- Memory budget and leaks ---------------------------------------------
    if app.get("status") == "ok":
        rss = float(app.get("rss_tail_mb") or 0)
        cpu = float(app.get("cpu_tail_pct") or 0)
        if rss > 250 or cpu > 1:
            recommendations.append(Recommendation(
                priority="P0",
                area="memory",
                title="The app exceeds the idle budget",
                evidence=[f"RSS {rss:.1f} MB (target 250 MB); CPU {cpu:.2f} % (target 1 %)."],
                action="Locate retention in the bridge, documents, caches and renderer before adding features.",
                acceptance="Steady RSS ≤250 MB and CPU ≤1 % for 5 minutes at idle.",
                confidence="high",
                commands=["dart run debug/engines/performance/bin/perf.dart idle-app --seconds 5"],
            ))
        else:
            recommendations.append(Recommendation(
                priority="P2",
                area="memory",
                title="Idle meets the budget; the peak under load is unmeasured",
                evidence=[
                    f"Real idle: {rss:.1f} MB and {cpu:.2f} % CPU.",
                    "There is no peak RSS series of the real app with heavy pages; "
                    "the harness RSS is not valid for that budget.",
                ],
                action="Measure maximum RSS with 1k/10k rows, scrolling and repeated navigation.",
                acceptance=(
                    "App peak RSS ≤250 MB under the agreed load, with no growing "
                    "trend after resources are released."
                ),
                confidence="medium",
                commands=[],
            ))
    leak_results = leaks.get("results") if isinstance(leaks, dict) else None
    if isinstance(leak_results, list):
        failing = [
            row for row in leak_results
            if str(row.get("status", "")).upper() in {"FAIL", "ERROR"}
        ]
        if failing:
            detail = ", ".join(
                f"{row.get('id', '?')}={row.get('status')}" for row in failing[:4]
            )
            recommendations.append(Recommendation(
                priority="P0",
                area="leaks",
                title=f"{len(failing)} memory cases do not release",
                evidence=[detail],
                action=(
                    "Reproduce with positive/negative controls, identify the "
                    "subsystem (bridge, DOM, listeners, runtime) and fix the retention."
                ),
                acceptance="Every case returns to baseline and the retained control is still detected.",
                confidence="high",
                commands=["cd debug/engines/memory && dart run bin/leaks.dart run --profile quick"],
            ))
        elif any(str(row.get("status", "")).upper() == "INCONCLUSIVE" for row in leak_results):
            recommendations.append(Recommendation(
                priority="P2",
                area="leaks",
                title="Some memory cases are INCONCLUSIVE",
                evidence=["The suite cannot assert release with the available counters."],
                action="Add resource counters and repeat the cases with more batches.",
                acceptance="No case stays INCONCLUSIVE without a documented reason.",
                confidence="medium",
                commands=["cd debug/engines/memory && dart run bin/leaks.dart run --profile full"],
            ))

    # --- Known capability gaps ------------------------------------------------
    if capabilities.get("video") is False:
        recommendations.append(Recommendation(
            priority="P1",
            area="multimedia",
            title="There is no real video playback",
            evidence=[
                "NativaX does not decode video: the renderer uses a placeholder and "
                "the DOM reports MEDIA_ERR_SRC_NOT_SUPPORTED.",
                "The 25 video tests cover contract/layout, not playback.",
            ],
            action=(
                "Implement a media pipeline (demux/decode, audio, clock, "
                "seek, video track and render surface) before claiming "
                "video support."
            ),
            acceptance=(
                "Play 360p, 720p and 1080p with audio and seek without blocking the "
                "frame; the unsupported-format error stays explicit."
            ),
            confidence="high",
            commands=[],
        ))
    if capabilities.get("game_player") is False:
        recommendations.append(Recommendation(
            priority="P2",
            area="games",
            title="The full Three.js game-player is unmeasured",
            evidence=[
                "The game matrix uses Canvas 2D and resolution profiles; it does "
                "not run the Three.js bundle of examples/game-player.",
            ],
            action=(
                "Build the game-player and measure NATIVAX_GAME_DPR 0.5/1/1.5/2 "
                "with the same rounds and counters."
            ),
            acceptance="Every quality profile has measured frame p95, RSS and CPU.",
            confidence="high",
            commands=[],
        ))

    # --- Security -------------------------------------------------------------
    security_results = security.get("results") if isinstance(security, dict) else None
    if isinstance(security_results, list):
        bad = [
            row for row in security_results
            if str(row.get("status", "")).upper() in {"FAIL", "ERROR"}
        ]
        if bad:
            detail = ", ".join(
                f"{row.get('id', '?')}={row.get('status')}" for row in bad[:5]
            )
            recommendations.append(Recommendation(
                priority="P0",
                area="security",
                title=f"{len(bad)} security checks fail",
                evidence=[detail],
                action="Fix the trust boundary before continuing with performance or compatibility.",
                acceptance="0 FAIL/ERROR in the security suite; documented SKIPs do not count.",
                confidence="high",
                commands=["cd debug/engines/security && dart run bin/security.dart run"],
            ))

    # --- Performance ----------------------------------------------------------
    category: dict[str, list[dict]] = {}
    for row in perf_rows:
        category.setdefault(str(row.get("kind") or "?"), []).append(row)

    def worst(rows: Iterable[dict]) -> list[dict]:
        return sorted(
            [row for row in rows if _is_ok(row)],
            key=lambda row: _ratio(row) or 0,
            reverse=True,
        )

    dom_rows = worst(category.get("dom", []))
    if dom_rows:
        failing = [
            row for row in dom_rows
            if (row.get("verdict") in {"FAIL", "WARN"})
            or (_ratio(row) or 0) > 3.0
        ]
        if failing:
            top = failing[:3]
            evidence = [
                f"{row.get('scenario')}: {_ratio_label(row)} "
                f"({_work(row, 'nativax'):.1f} vs {_work(row, 'chromium'):.1f} ms)"
                for row in top
            ]
            recommendations.append(Recommendation(
                priority="P1",
                area="DOM / layout",
                title="The dominant cost is in DOM and layout, not pure JS",
                evidence=evidence + [
                    f"{len(failing)} DOM scenarios are above the 3× target.",
                ],
                action=(
                    "Batch DOM mutations, avoid recomputing layout per node and "
                    "make style/layout incremental per subtree."
                ),
                acceptance=(
                    "Creating 1k rows ≤3× Chromium, 10k within budget and "
                    "no maximum frame >100 ms."
                ),
                confidence=(
                    "high"
                    if len(failing) >= 3 and perf_coverage >= 0.5
                    else "medium"
                ),
                commands=[
                    "dart run debug/engines/performance/bin/perf.dart run --only '^dom\\.' "
                    "--out .perf/dom",
                ],
            ))

    scroll_rows = worst(category.get("scroll", []))
    if scroll_rows:
        slow = []
        for row in scroll_rows:
            p95 = ((row.get("nativax") or {}).get("frame_ms") or {}).get("p95")
            if p95 is not None and float(p95) > 16.7:
                slow.append((row, float(p95)))
        if slow:
            slow.sort(key=lambda item: item[1], reverse=True)
            recommendations.append(Recommendation(
                priority="P1",
                area="scroll / frames",
                title="Long-list scrolling misses the frame budget",
                evidence=[
                    f"{row.get('scenario')}: p95 {p95:.1f} ms (target 16.7 ms)."
                    for row, p95 in slow[:4]
                ],
                action=(
                    "Virtualize rows, limit the paint area and avoid global "
                    "layout on every scroll step."
                ),
                acceptance="p95 ≤16.7 ms and maximum frame ≤100 ms in the scroll scenarios.",
                confidence="high" if perf_coverage >= 0.5 else "medium",
                commands=[
                    "dart run debug/engines/performance/bin/perf.dart run --only '^scroll\\.' "
                    "--out .perf/scroll",
                ],
            ))

    js_rows = worst(category.get("js", []))
    js_slow = [
        row for row in js_rows
        if (row.get("verdict") in {"FAIL", "WARN"}) or (_ratio(row) or 0) > 3.0
    ]
    if js_slow:
        recommendations.append(Recommendation(
            priority="P1",
            area="JavaScript",
            title="The JS engine loses on workloads that exceed the budget",
            evidence=[
                f"{row.get('scenario')}: {_ratio_label(row)}"
                for row in js_slow[:4]
            ],
            action=(
                "Separate engine cost from bridge cost; on desktop evaluate V8/"
                "JavaScriptCore behind the same contract. QuickJS without a JIT cannot "
                "match V8 in hot loops."
            ),
            acceptance=(
                "Every JS workload within the agreed target or a documented "
                "per-platform backend decision."
            ),
            confidence="medium" if perf_coverage < 0.5 else "high",
            commands=["dart run debug/engines/performance/bin/perf.dart run --only '^js\\.' --out .perf/js"],
        ))

    game_rows = {
        str(row.get("scenario")): row
        for row in perf_rows
        if str(row.get("scenario", "")).startswith("game.")
    }
    for row in _rows(game_payload, "results") + _rows(game3d_payload, "results"):
        if str(row.get("scenario", "")).startswith(("game.", "game3d.")):
            game_rows[str(row.get("scenario"))] = row
    game_slow = [
        row for row in worst(game_rows.values())
        if (row.get("verdict") in {"FAIL", "WARN"}) or (_ratio(row) or 0) > 3.0
    ]
    if game_slow:
        recommendations.append(Recommendation(
            priority="P1",
            area="games",
            title="Canvas 2D game profiles are above the budget",
            evidence=[
                f"{row.get('scenario')}: {_ratio_label(row)}"
                for row in game_slow[:4]
            ],
            action=(
                "Reduce particles/draw calls per frame or lower the internal scale; "
                "measure each profile separately, do not mix qualities."
            ),
            acceptance="Every quality profile meets its frame p95 and its work budget.",
            confidence="medium" if perf_coverage < 0.5 else "high",
            commands=["dart run debug/engines/performance/bin/perf.dart run --only '^game\\.' --out .perf/game"],
        ))

    # Cross-signal: DOM performance and visual layout both point at the renderer.
    categories = _visual_categories(visual_rows)
    if dom_rows and categories.get("Layout", 100) < 90 and (
        categories.get("Position", 100) < 90
    ):
        recommendations.append(Recommendation(
            priority="P0" if categories.get("Layout", 100) < 70 else "P1",
            area="renderer",
            title="DOM, layout and position point at the same bottleneck",
            evidence=[
                f"Mean visual layout {categories['Layout']:.1f} % and position "
                f"{categories['Position']:.1f} %.",
                "The DOM scenarios exceed the work target.",
            ],
            action=(
                "Prioritize the shared layout/positioning engine before "
                "micro-optimizing individual pages."
            ),
            acceptance=(
                "Layout/position ≥90 % on the measured catalog and DOM create 1k "
                "≤3× Chromium."
            ),
            confidence="high" if visual_coverage >= 0.5 else "medium",
            commands=[],
        ))

    # --- Visual ---------------------------------------------------------------
    if visual_rows:
        low_position = [
            row for row in visual_rows
            if isinstance(row.get("position"), (int, float)) and row["position"] < 70
        ]
        low_ink = [
            row for row in visual_rows
            if isinstance(row.get("ink_mismatch_pct"), (int, float))
            and row["ink_mismatch_pct"] >= 80
        ]
        if low_position:
            low_position = sorted(low_position, key=lambda row: row["position"])[:5]
            recommendations.append(Recommendation(
                priority="P1",
                area="visual fidelity",
                title="Content is mispositioned or outside its box",
                evidence=[
                    f"{row.get('page')}: position {_num(row.get('position'))} %, "
                    f"ink {_num(row.get('ink_mismatch_pct'))} %"
                    for row in low_position
                ],
                action=(
                    "Review containing blocks, transforms, fixed positioning and "
                    "stacking contexts; fix layout before color."
                ),
                acceptance="Position ≥90 % and ink <50 % on the affected pages.",
                confidence="high" if visual_coverage >= 0.5 else "medium",
                commands=[
                    "dart run debug/engines/visual_comparison/bin/visual_check.dart --only 'page' "
                    "--out .visual/latest",
                ],
            ))
        elif low_ink:
            recommendations.append(Recommendation(
                priority="P1",
                area="visual fidelity",
                title="Geometry may match but visible ink is missing",
                evidence=[
                    f"{row.get('page')}: mismatched ink "
                    f"{_num(row.get('ink_mismatch_pct'))} %"
                    for row in low_ink[:5]
                ],
                action="Check visibility, clipping, opacity and paint order.",
                acceptance="Mismatched ink <50 % without worsening position.",
                confidence="high",
                commands=[],
            ))
        if categories.get("Color", 100) < 60:
            recommendations.append(Recommendation(
                priority="P1",
                area="color",
                title="Computed color diverges from the reference render",
                evidence=[f"Mean color {categories['Color']:.1f} %."],
                action="Review inheritance, currentColor, gradients and filters before touching layout.",
                acceptance="Mean color ≥90 % on the measured pages.",
                confidence="medium",
                commands=[],
            ))

    # Deduplicate and sort by priority; preserve insertion order inside a tier.
    seen = set()
    unique = []
    for item in recommendations:
        key = (item.area, item.title)
        if key in seen:
            continue
        seen.add(key)
        unique.append(item)
    order = {"P0": 0, "P1": 1, "P2": 2}
    unique.sort(key=lambda item: (order.get(item.priority, 9), item.area))
    return unique


def _cell(value: Any, limit: int = 120) -> str:
    text = str(value if value is not None else "—").replace("|", "\\|")
    text = text.replace("\n", " ").strip()
    return text[:limit]


def _p95(row: dict) -> float | None:
    value = ((row.get("nativax") or {}).get("frame_ms") or {}).get("p95")
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _perf_action(row: dict) -> str:
    scenario = str(row.get("scenario") or "")
    kind = str(row.get("kind") or "")
    nativa = row.get("nativax") or {}
    if nativa.get("status") not in (None, "ok"):
        if "budget" in str(nativa.get("error", "")).lower():
            return "Reduce the work per operation or raise the budget with a justification; a timeout is not a PASS."
        return "Investigate the engine error before comparing performance."
    ratio = _ratio(row)
    if kind == "scroll" or scenario.startswith("scroll."):
        p95 = _p95(row)
        if p95 is not None and p95 > 16.7:
            return "Virtualize rows, limit paint and remove global layout per step."
    if scenario.startswith(("game.", "game3d.")):
        return "Lower particles/cubes, draw calls or internal DPR; measure each quality separately."
    if kind == "js":
        return "Profile engine vs bridge; evaluate V8/JSC on desktop; QuickJS does not match a JIT."
    if kind == "dom":
        return "Batch mutations, cache style and make layout incremental per subtree."
    if kind == "external":
        return "Reproduce the external benchmark with the same load and review the bottleneck."
    if ratio is not None and ratio > 3:
        return "Reduce work or improve layout/renderer before optimizing micro-cases."
    return "Keep the baseline and watch for regressions."


def _visual_action(row: dict) -> str:
    position = row.get("position")
    layout = row.get("layout")
    color = row.get("color")
    design = row.get("design")
    ink = row.get("ink_mismatch_pct")
    actions = []
    if isinstance(position, (int, float)) and position < 70:
        actions.append("fix position/containing block/transform")
    if isinstance(layout, (int, float)) and layout < 80:
        actions.append("review width/height, flex/grid and intrinsic size")
    if isinstance(color, (int, float)) and color < 60:
        actions.append("review color, background, gradients and filters")
    if isinstance(design, (int, float)) and design < 80:
        actions.append("review computed properties and inheritance")
    if isinstance(ink, (int, float)) and ink >= 80:
        actions.append("check off-screen/clipped content")
    return "; ".join(actions) if actions else "no dominant action"


def _load_json(path: str | None) -> dict | None:
    if not path:
        return None
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def _visual_root_causes(row: dict, limit: int = 4) -> list[str]:
    data = _load_json(row.get("elements_json"))
    if not data:
        return []
    elements = data.get("rows")
    if not isinstance(elements, list):
        return []
    candidates = []
    for element in elements:
        if not isinstance(element, dict):
            continue
        if element.get("missing") or element.get("extra") or element.get("root_cause"):
            candidates.append(element)
            continue
        position = float(element.get("position_delta") or 0)
        size = float(element.get("size_delta") or 0)
        color = float(element.get("color_mean_delta_e") or 0)
        if position >= 8 or size >= 8 or color >= 5:
            candidates.append(element)
    candidates.sort(
        key=lambda e: (
            float(e.get("position_delta") or 0)
            + float(e.get("size_delta") or 0)
            + float(e.get("color_mean_delta_e") or 0) * 4,
        ),
        reverse=True,
    )
    lines = []
    for element in candidates[:limit]:
        path = _cell(element.get("path", "?"), 90)
        details = [
            f"pos Δ {_num(element.get('position_delta'), 1)} px",
            f"size Δ {_num(element.get('size_delta'), 1)} px",
            f"ΔE {_num(element.get('color_mean_delta_e'), 1)}",
        ]
        if element.get("missing"):
            details.append("missing")
        if element.get("extra"):
            details.append("extra")
        mismatches = element.get("style_mismatches") or []
        if mismatches:
            changes = ", ".join(
                f"{_cell(m.get('property'), 20)} {_cell(m.get('chrome'), 24)}→"
                f"{_cell(m.get('nativa'), 24)}"
                for m in mismatches[:3]
                if isinstance(m, dict)
            )
            if changes:
                details.append(f"style: {changes}")
        lines.append(f"- `{path}`: " + "; ".join(details))
    return lines


def detailed_lines(data: dict[str, Any], recommendations: list[Recommendation]) -> list[str]:
    """Detailed, case-level sections for the standalone report."""
    visual_payload = data.get("visual") or {}
    perf_payload = data.get("perf") or {}
    visual_rows = _rows(visual_payload, "rows")
    perf_rows = _rows(perf_payload, "results")
    game_payload = data.get("game") or {}
    game3d_payload = data.get("game3d") or {}
    game_rows = _rows(game_payload, "results")
    visual_catalog = data.get("visual_catalog") or []
    perf_catalog = data.get("perf_catalog") or []
    app = data.get("app_idle") or {}
    leaks = data.get("leaks") or {}
    security = data.get("security") or {}

    lines = ["## Performance detail", ""]
    if perf_rows:
        lines.extend([
            "| Scenario | Kind | Verdict | NativaX ms | Chromium ms | Ratio | p95 ms | max ms | Nodes N/C | Harness RSS MB | Next action |",
            "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|",
        ])
        for row in perf_rows:
            nativa = row.get("nativax") or {}
            chrome = row.get("chromium") or {}
            p95 = _p95(row)
            pmax = ((nativa.get("frame_ms") or {}).get("max"))
            lines.append(
                f"| `{_cell(row.get('scenario'), 48)}` | {_cell(row.get('kind'), 10)} | "
                f"{_cell(row.get('verdict'), 10)} | {_num(_work(row, 'nativax'), 1)} | "
                f"{_num(_work(row, 'chromium'), 1)} | {_ratio_label(row)} | "
                f"{_num(p95, 1)} | {_num(pmax, 1)} | "
                f"{_cell(nativa.get('nodes'), 8)}/{_cell(chrome.get('nodes'), 8)} | "
                f"{_num(nativa.get('rss_peak_mb'), 0)} | {_cell(_perf_action(row), 100)} |"
            )
        lines.append("")
        failures = [row for row in perf_rows if row.get("verdict") in {"FAIL", "WARN"}]
        if failures:
            lines.extend(["### Reasons per scenario", ""])
            for row in failures[:20]:
                reasons = row.get("reasons") or []
                lines.append(
                    f"- `{row.get('scenario')}` — "
                    + ("; ".join(_cell(reason, 180) for reason in reasons) or "no recorded reason")
                )
            if len(failures) > 20:
                lines.append(f"- … and {len(failures) - 20} more scenarios; see `results.json`.")
            lines.append("")
    else:
        lines.extend(["There are no measured performance results.", ""])

    lines.extend(["## Visual detail", ""])
    if visual_rows:
        lines.extend([
            "| Page | Verdict | Overall | Position | Layout | Color | Design | Pixels % | Ink % | Mean ΔE | Action |",
            "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
        ])
        for row in visual_rows:
            lines.append(
                f"| `{_cell(row.get('page'), 58)}` | {_cell(row.get('verdict'), 10)} | "
                f"{_num(row.get('overall'), 1)} | {_num(row.get('position'), 1)} | "
                f"{_num(row.get('layout'), 1)} | {_num(row.get('color'), 1)} | "
                f"{_num(row.get('design'), 1)} | {_num(row.get('mismatched_pct'), 2)} | "
                f"{_num(row.get('ink_mismatch_pct'), 2)} | {_num(row.get('mean_delta_e'), 2)} | "
                f"{_cell(_visual_action(row), 100)} |"
            )
        lines.append("")
        offenders = sorted(
            visual_rows,
            key=lambda row: float(row.get("overall") or 0),
        )[:10]
        if offenders:
            lines.extend(["### Root causes per page (worst 10)", ""])
            for row in offenders:
                lines.extend([
                    f"#### `{row.get('page')}` — {_cell(row.get('verdict'), 10)} · "
                    f"overall {_num(row.get('overall'), 1)} %",
                    "",
                    f"- Suggested action: {_visual_action(row)}",
                ])
                roots = _visual_root_causes(row)
                lines.extend(roots or ["- No element detail; review the artifacts."])
                lines.extend([
                    f"- Artifacts: `{row.get('artifacts', '—')}`",
                    "",
                ])
    else:
        lines.extend(["There are no measured visual pages.", ""])

    lines.extend(["## Games detail", ""])
    game_detail = {
        str(row.get("scenario")): row
        for row in (_rows(data.get("game") or {}, "results")
                    + _rows(data.get("game3d") or {}, "results"))
        if str(row.get("scenario") or "").startswith(("game.", "game3d."))
    }
    for row in perf_rows:
        scenario = str(row.get("scenario") or "")
        if scenario.startswith(("game.", "game3d.")):
            game_detail.setdefault(scenario, row)
    if game_detail:
        lines.extend([
            "| Kind | Scenario | Resolution | Load | Verdict | NativaX ms | "
            "Chromium ms | Ratio | p95 ms | Harness RSS MB | Action |",
            "|---|---|---:|---:|---|---:|---:|---:|---:|---:|---|",
        ])
        for scenario, row in sorted(game_detail.items()):
            kind = "3D" if scenario.startswith("game3d.") else "2D"
            match = re.search(r"game(3d)?\.quality-(\d+)x(\d+)-(?:p|c)(\d+)", scenario)
            resolution = f"{match.group(2)}x{match.group(3)}" if match else "—"
            particles = match.group(4) if match else "—"
            nativa = row.get("nativax") or {}
            lines.append(
                f"| {kind} | `{_cell(scenario, 42)}` | {resolution} | {particles} | "
                f"{_cell(row.get('verdict'), 10)} | "
                f"{_num(_work(row, 'nativax'), 1)} | "
                f"{_num(_work(row, 'chromium'), 1)} | {_ratio_label(row)} | "
                f"{_num(_p95(row), 1)} | {_num(nativa.get('rss_peak_mb'), 0)} | "
                f"{_cell(_perf_action(row), 100)} |"
            )
        lines.append("")
    else:
        lines.extend(["There are no game batch results in `.perf/game`.", ""])

    video = data.get("video") or {}
    lines.extend(["## Video detail", ""])
    capability = video.get("capability") or {}
    lines.extend([
        f"- Real playback: **{'yes' if capability.get('playback') else 'no'}**.",
        f"- Decoder: {_cell(capability.get('decoder'), 80)}.",
        f"- Contract: {_cell(capability.get('media_error'), 80)}.",
        f"- Last run: {_cell((video.get('last_run') or {}).get('status'), 20)} "
        f"({_cell((video.get('last_run') or {}).get('date'), 30)}).",
        "",
    ])
    profiles = video.get("profiles") or []
    if profiles:
        lines.extend([
            "| Profile | Box | Attributes | Contract | Test |",
            "|---|---|---|---|---|",
        ])
        for profile in profiles:
            lines.append(
                f"| {_cell(profile.get('id'), 24)} | {_cell(profile.get('box'), 14)} | "
                f"{_cell(profile.get('attributes'), 80)} | "
                f"{_cell(profile.get('contract'), 60)} | "
                f"{_cell(profile.get('status'), 14)} |"
            )
        lines.append("")

    lines.extend(["## Pending coverage", ""])
    measured_visual = {str(row.get("page")) for row in visual_rows}
    pending_visual = [
        entry for entry in visual_catalog
        if isinstance(entry, dict) and entry.get("id") not in measured_visual
    ]
    if pending_visual:
        by_suite: dict[str, list[str]] = {}
        for entry in pending_visual:
            by_suite.setdefault(str(entry.get("suite") or "?"), []).append(
                str(entry.get("id"))
            )
        lines.extend([
            "| Suite | Pending | First pages |",
            "|---|---:|---|",
        ])
        for suite, ids in sorted(by_suite.items()):
            lines.append(
                f"| {_cell(suite, 32)} | {len(ids)} | "
                f"{_cell(', '.join(ids[:8]), 140)} |"
            )
        lines.extend([
            "",
            f"Total pending: **{len(pending_visual)}** pages. Full list in "
            "`.visual/catalog.json`.",
            "",
        ])
    else:
        lines.extend(["No pending visual pages in the current catalog.", ""])

    measured_perf = {str(row.get("scenario")) for row in perf_rows}
    pending_perf = [
        entry for entry in perf_catalog
        if isinstance(entry, dict) and entry.get("id") not in measured_perf
    ]
    if pending_perf:
        by_prefix: dict[str, int] = {}
        for entry in pending_perf:
            prefix = str(entry.get("id") or "?").split(".", 1)[0]
            by_prefix[prefix] = by_prefix.get(prefix, 0) + 1
        lines.extend([
            "| Scenario group | Pending |",
            "|---|---:|",
        ])
        for prefix, count in sorted(by_prefix.items()):
            lines.append(f"| {_cell(prefix, 32)} | {count} |")
        lines.append(
            f"\nTotal pending: **{len(pending_perf)}** scenarios. Full list "
            "in `debug/engines/performance/scenarios.json`."
        )
        lines.append("")

    leak_results = leaks.get("results") if isinstance(leaks, dict) else None
    lines.extend(["## Memory and leaks", ""])
    if isinstance(leak_results, list) and leak_results:
        lines.extend(["| Case | Status | Reason |", "|---|---|---|"])
        for row in leak_results:
            lines.append(
                f"| `{_cell(row.get('id'), 48)}` | {_cell(row.get('status'), 12)} | "
                f"{_cell(row.get('reason'), 120)} |"
            )
        lines.append("")
    else:
        lines.extend(["There is no recent leak report in `benchmarks/leaks`.", ""])

    security_results = security.get("results") if isinstance(security, dict) else None
    lines.extend(["## Security", ""])
    if isinstance(security_results, list) and security_results:
        lines.extend(["| Case | Category | Severity | Status | Observed |", "|---|---|---|---|---|"])
        for row in security_results:
            lines.append(
                f"| `{_cell(row.get('id'), 42)}` | {_cell(row.get('category'), 16)} | "
                f"{_cell(row.get('severity'), 10)} | {_cell(row.get('status'), 12)} | "
                f"{_cell(row.get('observed'), 100)} |"
            )
        lines.append("")
    else:
        lines.extend(["There is no recent security report in `benchmarks/security`.", ""])

    lines.extend(["## Environment and provenance", ""])
    lines.extend([
        f"- Visual: {len(visual_rows)}/{len(visual_catalog) or len(visual_rows)} pages; "
        f"reference { _cell(visual_payload.get('reference'), 80) }.",
        f"- Performance: {len(perf_rows)}/{len(perf_catalog) or len(perf_rows)} scenarios; "
        f"reference { _cell(perf_payload.get('chrome'), 80) }.",
        f"- App idle: {_num(app.get('rss_tail_mb'), 1)} MB · "
        f"{_num(app.get('cpu_tail_pct'), 2)} % CPU.",
        "- Video values are contract/placeholder only; there is no decoder.",
        "- The game scenarios of this matrix are Canvas 2D.",
    ])
    lines.append("")
    return lines


def markdown_lines(
    data: dict[str, Any],
    recommendations: list[Recommendation],
    include_limits: bool = True,
) -> list[str]:
    visual_rows = _rows(data.get("visual") or {}, "rows")
    perf_rows = _rows(data.get("perf") or {}, "results")
    visual_total = len(data.get("visual_catalog") or []) or len(visual_rows)
    perf_total = len(data.get("perf_catalog") or []) or len(perf_rows)
    app = data.get("app_idle") or {}
    lines = [
        "## Automatic recommendations",
        "",
        f"Rule engine with measured evidence (not a black box). "
        f"Current coverage: **{len(visual_rows)}/{visual_total}** pages and "
        f"**{len(perf_rows)}/{perf_total}** scenarios.",
        "",
    ]
    if not recommendations:
        lines.extend([
            "There are no blocking recommendations with the current data. "
            "Pending coverage is still the limit of the conclusion.",
            "",
        ])
        return lines
    for rec in recommendations:
        lines.extend([
            f"### {rec.priority} · {rec.area} — {rec.title}",
            "",
            f"**Confidence:** {rec.confidence}",
            "",
            "**Evidence**",
            "",
        ])
        lines.extend(f"- {item}" for item in rec.evidence)
        lines.extend([
            "",
            f"**Action:** {rec.action}",
            "",
            f"**Acceptance criterion:** {rec.acceptance}",
        ])
        if rec.commands:
            lines.extend(["", "**Command:**", "", "```bash"])
            lines.extend(rec.commands)
            lines.append("```")
        lines.append("")
    if include_limits:
        lines.extend(limits_lines())
    return lines


def limits_lines() -> list[str]:
    return [
        "## Limits of this conclusion",
        "",
        "- The video tests are contract/placeholder only: NativaX does not decode "
        "video yet; no playback is claimed.",
        "- The game scenarios of this matrix are Canvas 2D; the full Three.js "
        "`examples/game-player` needs a separate measurement.",
        "- The harness RSS (`flutter test`) is not the app RSS; the real idle "
        "is measured separately.",
        "- The recommendations promise no improvement percentages; they use the "
        "measured ratios and thresholds.",
        "",
    ]


def build_markdown(data: dict[str, Any]) -> str:
    recommendations = build_recommendations(data)
    visual_rows = _rows(data.get("visual") or {}, "rows")
    perf_rows = _rows(data.get("perf") or {}, "results")
    visual_total = len(data.get("visual_catalog") or []) or len(visual_rows)
    perf_total = len(data.get("perf_catalog") or []) or len(perf_rows)
    app = data.get("app_idle") or {}
    lines = [
        "# NativaX — quality recommendations",
        "",
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}.",
        "",
        "## Diagnosis",
        "",
        "| Area | Status |",
        "|---|---|",
        f"| Visual fidelity | {len(visual_rows)}/{visual_total} measured |",
        f"| Performance | {len(perf_rows)}/{perf_total} measured |",
        f"| App idle | {_num(app.get('rss_tail_mb'))} MB · "
        f"{_num(app.get('cpu_tail_pct'), 2)} % CPU |",
        f"| Video | {len((data.get('video') or {}).get('profiles') or [])} profiles · "
        f"playback {'yes' if ((data.get('video') or {}).get('capability') or {}).get('playback') else 'no'} |",
        f"| Games | {len((data.get('game') or {}).get('results') or []) + len((data.get('game3d') or {}).get('results') or [])} profiles measured |",
        "",
    ]
    lines.extend(["## Priorities", ""])
    for priority in ("P0", "P1", "P2"):
        count = sum(1 for rec in recommendations if rec.priority == priority)
        if count:
            lines.append(f"- **{priority}:** {count}")
    lines.append("")
    lines.extend(markdown_lines(data, recommendations, include_limits=False))
    lines.extend(detailed_lines(data, recommendations))
    lines.extend(limits_lines())
    lines.extend([
        "## How to use this report",
        "",
        "The panel can show this content from **Informes → Recomendaciones** "
        "or from the **En vivo** report. To regenerate it:",
        "",
        "```bash",
        "python3 debug/engines/recommendations/recommend.py --out progress/reports/recommendations-latest.md",
        "```",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="progress/reports/recommendations-latest.md")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()

    if args.self_check:
        return _self_check()
    data = collect(ROOT)
    text = build_markdown(data)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
    print(out)
    if args.json:
        print(json.dumps(
            [item.as_dict() for item in build_recommendations(data)],
            indent=2,
            ensure_ascii=False,
        ))
    return 0


def _self_check() -> int:
    """Tiny deterministic control for CI without external fixtures."""
    data = {
        "visual": {"rows": [{
            "page": "p", "position": 20, "layout": 30, "color": 40,
            "design": 90, "overall": 30, "ink_mismatch_pct": 90,
        }]},
        "visual_catalog": [{"id": "p"}],
        "perf": {"results": [{
            "scenario": "dom.rows-create-1k", "kind": "dom",
            "verdict": "FAIL", "nativax": {
                "status": "ok", "scenario_ms": 100, "render_ms": 20,
                "frame_ms": {"p95": 100},
            },
            "chromium": {
                "status": "ok", "scenario_ms": 10, "render_ms": 2,
                "frame_ms": {"p95": 1},
            },
        }]},
        "perf_catalog": [{"id": "dom.rows-create-1k"}],
        "app_idle": {"status": "ok", "rss_tail_mb": 120, "cpu_tail_pct": 0},
    }
    recs = build_recommendations(data)
    assert any(r.priority == "P0" for r in recs), "cross-signal P0 expected"
    assert any("DOM" in r.area for r in recs), "DOM recommendation expected"
    md = build_markdown(data)
    assert "Automatic recommendations" in md
    print("recommend self-check OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

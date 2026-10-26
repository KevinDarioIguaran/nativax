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
    confidence: str = "media"
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


def _json_candidates(folder: Path) -> list[Path]:
    """Report JSONs newest first: per-run directories, then legacy flat files.

    Run directories are named by UTC run id, so lexicographic order is
    chronological. ``manifest.json`` is metadata and never the report.
    """
    if not folder.exists():
        return []
    runs = sorted(
        (d for d in folder.iterdir() if d.is_dir() and not d.name.startswith(".")),
        key=lambda d: d.name,
        reverse=True,
    )
    nested = [
        path
        for run in runs
        for path in sorted(run.glob("*.json"), key=lambda item: item.name)
        if path.is_file() and path.name != "manifest.json"
    ]
    if nested:
        return nested
    return sorted(
        (path for path in folder.glob("*.json") if path.is_file()),
        key=lambda path: path.stat().st_mtime_ns,
        reverse=True,
    )


def _latest_json(folder: Path) -> dict | None:
    for path in _json_candidates(folder):
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict):
            data.setdefault("_path", str(path))
            return data
    return None


_LATEST_CACHE: dict[str, tuple[str, dict | None]] = {}


def load_latest_run(folder: Path) -> dict | None:
    """Loads the newest report, cached by run path and mtime."""
    candidates = _json_candidates(folder)
    if not candidates:
        return None
    newest = candidates[0]
    signature = f"{newest}:{newest.stat().st_mtime_ns}"
    key = str(folder.resolve())
    cached = _LATEST_CACHE.get(key)
    if cached is not None and cached[0] == signature:
        return cached[1]
    data = _latest_json(folder)
    _LATEST_CACHE[key] = (signature, data)
    return data


def collect(root: Path = ROOT) -> dict[str, Any]:
    """Loads the standard files used by the standalone report command."""
    artifacts = root / "debug" / "artifacts"
    visual = None
    for candidate in (
        artifacts / "visual" / "latest" / "results.json",
        artifacts / "visual" / "runs" / "50projects50days" / "results.json",
    ):
        if candidate.exists():
            try:
                visual = json.loads(candidate.read_text())
            except json.JSONDecodeError:
                continue
            if visual:
                break
    perf = None
    perf_path = artifacts / "perf" / "latest" / "results.json"
    if perf_path.exists():
        try:
            perf = json.loads(perf_path.read_text())
        except json.JSONDecodeError:
            perf = None
    app_idle = None
    for candidate in (
        artifacts / "perf" / "latest" / "app-idle.json",
        artifacts / "perf" / "app-idle.json",
    ):
        if candidate.exists():
            try:
                app_idle = json.loads(candidate.read_text())
            except json.JSONDecodeError:
                continue
            if app_idle:
                break
    matrix = None
    matrix_path = artifacts / "perf" / "container" / "matrix.json"
    if matrix_path.exists():
        try:
            matrix = json.loads(matrix_path.read_text())
        except json.JSONDecodeError:
            matrix = None
    catalogs = {}
    for name, path in (
        ("perf", root / "debug" / "engines" / "performance" / "scenarios.json"),
        ("visual", artifacts / "visual" / "catalog.json"),
    ):
        if path.exists():
            try:
                value = json.loads(path.read_text())
                if isinstance(value, list):
                    catalogs[name] = value
            except json.JSONDecodeError:
                pass
    game = None
    game_path = artifacts / "perf" / "game" / "results.json"
    if game_path.exists():
        try:
            game = json.loads(game_path.read_text())
        except json.JSONDecodeError:
            game = None
    game3d = None
    game3d_path = artifacts / "perf" / "game3d" / "results.json"
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
        "leaks": load_latest_run(root / "debug" / "benchmarks" / "leaks"),
        "security": load_latest_run(root / "debug" / "benchmarks" / "security"),
        "capabilities": {"video": False, "game_player": False},
    }


def _visual_categories(rows: list[dict]) -> dict[str, float]:
    result = {}
    for key, label in (
        ("position", "Posición"),
        ("layout", "Layout"),
        ("color", "Color"),
        ("design", "Diseño"),
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
            area="cobertura visual",
            title=f"Faltan {visual_total - len(visual_rows)} páginas visuales por medir",
            evidence=[
                f"{len(visual_rows)}/{visual_total} páginas con resultado medido.",
                "Sin esa muestra no se puede extrapolar la fidelidad al catálogo completo.",
            ],
            action="Ejecutar el catálogo visual completo y revisar las páginas nuevas.",
            acceptance=(
                f"{visual_total}/{visual_total} páginas medidas; overall y tinta "
                "reportados sin muestras pendientes."
            ),
            confidence="alta" if visual_total >= 100 else "media",
            commands=[
                "dart run debug/engines/visual_comparison/bin/visual_check.dart --all "
                "--catalog debug/artifacts/visual/catalog.json --out debug/artifacts/visual/latest",
            ],
        ))
    if perf_total and len(perf_rows) < perf_total:
        recommendations.append(Recommendation(
            priority="P2",
            area="cobertura de rendimiento",
            title=f"Faltan {perf_total - len(perf_rows)} escenarios de rendimiento",
            evidence=[
                f"{len(perf_rows)}/{perf_total} escenarios medidos.",
                "La tabla muestra pendientes; no se puede declarar una tasa global "
                "ni comparar todos los tipos de carga.",
            ],
            action=(
                "Ejecutar primero el lote base y luego los escenarios de matriz; "
                "no mezclar una pasada corta con una afirmación global."
            ),
            acceptance=(
                f"{perf_total}/{perf_total} escenarios ejecutados, al menos 3 "
                "rondas en release/AOT para la decisión final."
            ),
            confidence="alta",
            commands=[
                "dart run debug/engines/performance/bin/perf.dart run --out debug/artifacts/perf/latest",
            ],
        ))
    if not app or app.get("status") != "ok":
        recommendations.append(Recommendation(
            priority="P1",
            area="memoria",
            title="Falta la medición real de la app en reposo",
            evidence=[
                "El RSS del arnés de test incluye Flutter/Dart y no representa "
                "el consumo de la app.",
                "No hay `app-idle.json` con RSS/CPU del proceso real.",
            ],
            action="Medir la app Linux real en una página blanca, con calentamiento y reposo.",
            acceptance="RSS pico y estable ≤250 MB y CPU ≤1 % en la app real.",
            confidence="alta",
            commands=["dart run debug/engines/performance/bin/perf.dart idle-app --seconds 5"],
        ))

    # --- Memory budget and leaks ---------------------------------------------
    if app.get("status") == "ok":
        rss = float(app.get("rss_tail_mb") or 0)
        cpu = float(app.get("cpu_tail_pct") or 0)
        if rss > 250 or cpu > 1:
            recommendations.append(Recommendation(
                priority="P0",
                area="memoria",
                title="La app supera el presupuesto de reposo",
                evidence=[f"RSS {rss:.1f} MB (objetivo 250 MB); CPU {cpu:.2f} % (objetivo 1 %)."],
                action="Localizar retenciones en bridge, documentos, caches y renderer antes de añadir funciones.",
                acceptance="RSS estable ≤250 MB y CPU ≤1 % durante 5 minutos en reposo.",
                confidence="alta",
                commands=["dart run debug/engines/performance/bin/perf.dart idle-app --seconds 5"],
            ))
        else:
            recommendations.append(Recommendation(
                priority="P2",
                area="memoria",
                title="El idle cumple; falta el pico bajo carga",
                evidence=[
                    f"Idle real: {rss:.1f} MB y {cpu:.2f} % CPU.",
                    "No hay una serie de RSS pico de la app real con páginas pesadas; "
                    "el RSS del arnés no sirve para ese presupuesto.",
                ],
                action="Medir RSS máximo con 1k/10k filas, scroll y navegación repetida.",
                acceptance=(
                    "RSS pico de la app ≤250 MB en la carga acordada, sin tendencia "
                    "creciente tras liberar recursos."
                ),
                confidence="media",
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
                area="fugas",
                title=f"Hay {len(failing)} casos de memoria que no liberan",
                evidence=[detail],
                action=(
                    "Reproducir con controles positivo/negativo, identificar el "
                    "subsistema (bridge, DOM, listeners, runtime) y corregir la retención."
                ),
                acceptance="Cada caso vuelve a la línea base y el control retenido sigue detectándose.",
                confidence="alta",
                commands=["cd debug/engines/memory && dart run bin/leaks.dart run --profile quick"],
            ))
        elif any(str(row.get("status", "")).upper() == "INCONCLUSIVE" for row in leak_results):
            recommendations.append(Recommendation(
                priority="P2",
                area="fugas",
                title="Algunos casos de memoria son INCONCLUSIVE",
                evidence=["La suite no puede afirmar liberación con los contadores disponibles."],
                action="Añadir contadores de recursos y repetir los casos con más batches.",
                acceptance="Ningún caso queda INCONCLUSIVE sin una razón documentada.",
                confidence="media",
                commands=["cd debug/engines/memory && dart run bin/leaks.dart run --profile full"],
            ))

    # --- Known capability gaps ------------------------------------------------
    if capabilities.get("video") is False:
        recommendations.append(Recommendation(
            priority="P1",
            area="multimedia",
            title="No hay reproducción de vídeo real",
            evidence=[
                "NativaX no decodifica vídeo: el renderer usa un placeholder y "
                "el DOM reporta MEDIA_ERR_SRC_NOT_SUPPORTED.",
                "Los 25 tests de vídeo son de contrato/layout, no de playback.",
            ],
            action=(
                "Implementar pipeline multimedia (demux/decode, audio, reloj, "
                "seek, pista de vídeo y superficie de render) antes de afirmar "
                "soporte de vídeo."
            ),
            acceptance=(
                "Reproducir 360p, 720p y 1080p con audio y seek sin bloquear el "
                "frame; error de formato no soportado sigue siendo explícito."
            ),
            confidence="alta",
            commands=[],
        ))
    if capabilities.get("game_player") is False:
        recommendations.append(Recommendation(
            priority="P2",
            area="juegos",
            title="Falta medir el game-player Three.js completo",
            evidence=[
                "La matriz de juego usa Canvas 2D y perfiles de resolución; no "
                "ejecuta el bundle Three.js de examples/game-player.",
            ],
            action=(
                "Construir el game-player y medir NATIVAX_GAME_DPR 0.5/1/1.5/2 "
                "con las mismas rondas y contadores."
            ),
            acceptance="Cada perfil de calidad tiene frame p95, RSS y CPU medidos.",
            confidence="alta",
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
                area="seguridad",
                title=f"Hay {len(bad)} comprobaciones de seguridad fallidas",
                evidence=[detail],
                action="Corregir el límite de confianza antes de seguir con rendimiento o compatibilidad.",
                acceptance="0 FAIL/ERROR en la suite de seguridad; los SKIP documentados no cuentan.",
                confidence="alta",
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
                title="El coste dominante está en DOM y layout, no en JS puro",
                evidence=evidence + [
                    f"{len(failing)} escenarios DOM están por encima del objetivo de 3×.",
                ],
                action=(
                    "Agrupar mutaciones DOM, evitar recalcular layout por nodo y "
                    "hacer style/layout incremental por subárbol."
                ),
                acceptance=(
                    "Crear 1k filas ≤3× Chromium, 10k dentro del presupuesto y "
                    "sin frame máximo >100 ms."
                ),
                confidence=(
                    "alta"
                    if len(failing) >= 3 and perf_coverage >= 0.5
                    else "media"
                ),
                commands=[
                    "dart run debug/engines/performance/bin/perf.dart run --only '^dom\\.' "
                    "--out debug/artifacts/perf/dom",
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
                title="El scroll de listas largas pierde el presupuesto de frame",
                evidence=[
                    f"{row.get('scenario')}: p95 {p95:.1f} ms (objetivo 16.7 ms)."
                    for row, p95 in slow[:4]
                ],
                action=(
                    "Virtualizar filas, limitar el área de paint y evitar layout "
                    "global en cada paso de scroll."
                ),
                acceptance="p95 ≤16.7 ms y frame máximo ≤100 ms en los escenarios de scroll.",
                confidence="alta" if perf_coverage >= 0.5 else "media",
                commands=[
                    "dart run debug/engines/performance/bin/perf.dart run --only '^scroll\\.' "
                    "--out debug/artifacts/perf/scroll",
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
            title="El motor JS pierde en cargas que superan el presupuesto",
            evidence=[
                f"{row.get('scenario')}: {_ratio_label(row)}"
                for row in js_slow[:4]
            ],
            action=(
                "Separar coste del motor y del bridge; en escritorio evaluar V8/"
                "JavaScriptCore tras el mismo contrato. QuickJS sin JIT no puede "
                "igualar a V8 en bucles calientes."
            ),
            acceptance=(
                "Cada carga JS dentro del objetivo acordado o una decisión "
                "documentada de backend por plataforma."
            ),
            confidence="media" if perf_coverage < 0.5 else "alta",
            commands=["dart run debug/engines/performance/bin/perf.dart run --only '^js\\.' --out debug/artifacts/perf/js"],
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
            area="juegos",
            title="Los perfiles de juego Canvas 2D quedan por encima del presupuesto",
            evidence=[
                f"{row.get('scenario')}: {_ratio_label(row)}"
                for row in game_slow[:4]
            ],
            action=(
                "Reducir partículas/draw calls por frame o bajar la escala interna; "
                "medir cada perfil por separado, no mezclar calidades."
            ),
            acceptance="Cada perfil de calidad cumple su frame p95 y su presupuesto de trabajo.",
            confidence="media" if perf_coverage < 0.5 else "alta",
            commands=["dart run debug/engines/performance/bin/perf.dart run --only '^game\\.' --out debug/artifacts/perf/game"],
        ))

    # Cross-signal: DOM performance and visual layout both point at the renderer.
    categories = _visual_categories(visual_rows)
    if dom_rows and categories.get("Layout", 100) < 90 and (
        categories.get("Posición", 100) < 90
    ):
        recommendations.append(Recommendation(
            priority="P0" if categories.get("Layout", 100) < 70 else "P1",
            area="renderer",
            title="DOM, layout y posición apuntan al mismo cuello de botella",
            evidence=[
                f"Layout visual medio {categories['Layout']:.1f} % y posición "
                f"{categories['Posición']:.1f} %.",
                "Los escenarios DOM superan el objetivo de trabajo.",
            ],
            action=(
                "Priorizar el motor de layout/posicionamiento compartido antes de "
                "microoptimizar páginas individuales."
            ),
            acceptance=(
                "Layout/posición ≥90 % en el catálogo medido y DOM create 1k "
                "≤3× Chromium."
            ),
            confidence="alta" if visual_coverage >= 0.5 else "media",
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
                area="fidelidad visual",
                title="Hay contenido mal posicionado o fuera de su caja",
                evidence=[
                    f"{row.get('page')}: posición {_num(row.get('position'))} %, "
                    f"tinta {_num(row.get('ink_mismatch_pct'))} %"
                    for row in low_position
                ],
                action=(
                    "Revisar containing blocks, transforms, posición fija y "
                    "stacking contexts; corregir el layout antes del color."
                ),
                acceptance="Posición ≥90 % y tinta <50 % en las páginas afectadas.",
                confidence="alta" if visual_coverage >= 0.5 else "media",
                commands=[
                    "dart run debug/engines/visual_comparison/bin/visual_check.dart --only 'pagina' "
                    "--out debug/artifacts/visual/latest",
                ],
            ))
        elif low_ink:
            recommendations.append(Recommendation(
                priority="P1",
                area="fidelidad visual",
                title="La geometría puede coincidir pero falta tinta visible",
                evidence=[
                    f"{row.get('page')}: tinta no coincidente "
                    f"{_num(row.get('ink_mismatch_pct'))} %"
                    for row in low_ink[:5]
                ],
                action="Comprobar visibilidad, recorte, opacidad y orden de pintura.",
                acceptance="Tinta no coincidente <50 % sin empeorar la posición.",
                confidence="alta",
                commands=[],
            ))
        if categories.get("Color", 100) < 60:
            recommendations.append(Recommendation(
                priority="P1",
                area="color",
                title="El color computado se separa del render de referencia",
                evidence=[f"Color medio {categories['Color']:.1f} %."],
                action="Revisar herencia, currentColor, gradientes y filtros antes de tocar layout.",
                acceptance="Color medio ≥90 % en las páginas medidas.",
                confidence="media",
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
            return "Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS."
        return "Investigar el error del motor antes de comparar rendimiento."
    ratio = _ratio(row)
    if kind == "scroll" or scenario.startswith("scroll."):
        p95 = _p95(row)
        if p95 is not None and p95 > 16.7:
            return "Virtualizar filas, limitar paint y eliminar layout global por paso."
    if scenario.startswith(("game.", "game3d.")):
        return "Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado."
    if kind == "js":
        return "Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT."
    if kind == "dom":
        return "Agrupar mutaciones, cachear style y hacer layout incremental por subárbol."
    if kind == "external":
        return "Reproducir el benchmark externo con la misma carga y revisar el cuello."
    if ratio is not None and ratio > 3:
        return "Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos."
    return "Mantener la línea base y vigilar regresiones."


def _visual_action(row: dict) -> str:
    position = row.get("position")
    layout = row.get("layout")
    color = row.get("color")
    design = row.get("design")
    ink = row.get("ink_mismatch_pct")
    actions = []
    if isinstance(position, (int, float)) and position < 70:
        actions.append("corregir posición/containing block/transform")
    if isinstance(layout, (int, float)) and layout < 80:
        actions.append("revisar width/height, flex/grid y tamaño intrínseco")
    if isinstance(color, (int, float)) and color < 60:
        actions.append("revisar color, background, gradientes y filtros")
    if isinstance(design, (int, float)) and design < 80:
        actions.append("revisar propiedades computadas y herencia")
    if isinstance(ink, (int, float)) and ink >= 80:
        actions.append("comprobar contenido fuera de pantalla/recortado")
    return "; ".join(actions) if actions else "sin acción dominante"


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
            f"tamaño Δ {_num(element.get('size_delta'), 1)} px",
            f"ΔE {_num(element.get('color_mean_delta_e'), 1)}",
        ]
        if element.get("missing"):
            details.append("faltante")
        if element.get("extra"):
            details.append("sobrante")
        mismatches = element.get("style_mismatches") or []
        if mismatches:
            changes = ", ".join(
                f"{_cell(m.get('property'), 20)} {_cell(m.get('chrome'), 24)}→"
                f"{_cell(m.get('nativa'), 24)}"
                for m in mismatches[:3]
                if isinstance(m, dict)
            )
            if changes:
                details.append(f"estilo: {changes}")
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

    lines = ["## Detalle de rendimiento", ""]
    if perf_rows:
        lines.extend([
            "| Escenario | Tipo | Veredicto | NativaX ms | Chromium ms | Ratio | p95 ms | max ms | Nodos N/C | RSS arnés MB | Siguiente acción |",
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
            lines.extend(["### Motivos por escenario", ""])
            for row in failures[:20]:
                reasons = row.get("reasons") or []
                lines.append(
                    f"- `{row.get('scenario')}` — "
                    + ("; ".join(_cell(reason, 180) for reason in reasons) or "sin motivo registrado")
                )
            if len(failures) > 20:
                lines.append(f"- … y {len(failures) - 20} escenarios más; ver `results.json`.")
            lines.append("")
    else:
        lines.extend(["No hay resultados de rendimiento medidos.", ""])

    lines.extend(["## Detalle visual", ""])
    if visual_rows:
        lines.extend([
            "| Página | Veredicto | Overall | Posición | Layout | Color | Diseño | Píxeles % | Tinta % | ΔE medio | Acción |",
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
            lines.extend(["### Causas raíz por página (peores 10)", ""])
            for row in offenders:
                lines.extend([
                    f"#### `{row.get('page')}` — {_cell(row.get('verdict'), 10)} · "
                    f"overall {_num(row.get('overall'), 1)} %",
                    "",
                    f"- Acción sugerida: {_visual_action(row)}",
                ])
                roots = _visual_root_causes(row)
                lines.extend(roots or ["- Sin detalle de elementos; revisar artefactos."])
                lines.extend([
                    f"- Artefactos: `{row.get('artifacts', '—')}`",
                    "",
                ])
    else:
        lines.extend(["No hay páginas visuales medidas.", ""])

    lines.extend(["## Detalle de juegos", ""])
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
            "| Tipo | Escenario | Resolución | Carga | Veredicto | NativaX ms | "
            "Chromium ms | Ratio | p95 ms | RSS arnés MB | Acción |",
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
        lines.extend(["No hay resultados del lote de juegos en `debug/artifacts/perf/game`.", ""])

    video = data.get("video") or {}
    lines.extend(["## Detalle de vídeo", ""])
    capability = video.get("capability") or {}
    lines.extend([
        f"- Reproducción real: **{'sí' if capability.get('playback') else 'no'}**.",
        f"- Decoder: {_cell(capability.get('decoder'), 80)}.",
        f"- Contrato: {_cell(capability.get('media_error'), 80)}.",
        f"- Última corrida: {_cell((video.get('last_run') or {}).get('status'), 20)} "
        f"({_cell((video.get('last_run') or {}).get('date'), 30)}).",
        "",
    ])
    profiles = video.get("profiles") or []
    if profiles:
        lines.extend([
            "| Perfil | Caja | Atributos | Contrato | Test |",
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

    lines.extend(["## Cobertura pendiente", ""])
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
            "| Suite | Pendientes | Primeras páginas |",
            "|---|---:|---|",
        ])
        for suite, ids in sorted(by_suite.items()):
            lines.append(
                f"| {_cell(suite, 32)} | {len(ids)} | "
                f"{_cell(', '.join(ids[:8]), 140)} |"
            )
        lines.extend([
            "",
            f"Total pendiente: **{len(pending_visual)}** páginas. Lista completa en "
            "`debug/artifacts/visual/catalog.json`.",
            "",
        ])
    else:
        lines.extend(["Sin páginas visuales pendientes en el catálogo actual.", ""])

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
            "| Grupo de escenarios | Pendientes |",
            "|---|---:|",
        ])
        for prefix, count in sorted(by_prefix.items()):
            lines.append(f"| {_cell(prefix, 32)} | {count} |")
        lines.append(
            f"\nTotal pendiente: **{len(pending_perf)}** escenarios. Lista completa "
            "en `debug/engines/performance/scenarios.json`."
        )
        lines.append("")

    leak_results = leaks.get("results") if isinstance(leaks, dict) else None
    lines.extend(["## Memoria y fugas", ""])
    if isinstance(leak_results, list) and leak_results:
        lines.extend(["| Caso | Estado | Motivo |", "|---|---|---|"])
        for row in leak_results:
            lines.append(
                f"| `{_cell(row.get('id'), 48)}` | {_cell(row.get('status'), 12)} | "
                f"{_cell(row.get('reason'), 120)} |"
            )
        lines.append("")
    else:
        lines.extend(["No hay un informe de fugas reciente en `debug/benchmarks/leaks`.", ""])

    security_results = security.get("results") if isinstance(security, dict) else None
    lines.extend(["## Seguridad", ""])
    if isinstance(security_results, list) and security_results:
        lines.extend(["| Caso | Categoría | Severidad | Estado | Observado |", "|---|---|---|---|---|"])
        for row in security_results:
            lines.append(
                f"| `{_cell(row.get('id'), 42)}` | {_cell(row.get('category'), 16)} | "
                f"{_cell(row.get('severity'), 10)} | {_cell(row.get('status'), 12)} | "
                f"{_cell(row.get('observed'), 100)} |"
            )
        lines.append("")
    else:
        lines.extend(["No hay un informe de seguridad reciente en `debug/benchmarks/security`.", ""])

    lines.extend(["## Entorno y procedencia", ""])
    lines.extend([
        f"- Visual: {len(visual_rows)}/{len(visual_catalog) or len(visual_rows)} páginas; "
        f"referencia { _cell(visual_payload.get('reference'), 80) }.",
        f"- Rendimiento: {len(perf_rows)}/{len(perf_catalog) or len(perf_rows)} escenarios; "
        f"referencia { _cell(perf_payload.get('chrome'), 80) }.",
        f"- App idle: {_num(app.get('rss_tail_mb'), 1)} MB · "
        f"{_num(app.get('cpu_tail_pct'), 2)} % CPU.",
        "- Los valores de vídeo son de contrato/placeholder; no hay decoder.",
        "- Los escenarios de juego de esta matriz son Canvas 2D.",
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
        "## Recomendaciones automáticas",
        "",
        f"Motor de reglas con evidencia medida (no una caja negra). "
        f"Cobertura actual: **{len(visual_rows)}/{visual_total}** páginas y "
        f"**{len(perf_rows)}/{perf_total}** escenarios.",
        "",
    ]
    if not recommendations:
        lines.extend([
            "No hay recomendaciones bloqueantes con los datos actuales. La "
            "cobertura pendiente sigue siendo el límite de la conclusión.",
            "",
        ])
        return lines
    for rec in recommendations:
        lines.extend([
            f"### {rec.priority} · {rec.area} — {rec.title}",
            "",
            f"**Confianza:** {rec.confidence}",
            "",
            "**Evidencia**",
            "",
        ])
        lines.extend(f"- {item}" for item in rec.evidence)
        lines.extend([
            "",
            f"**Acción:** {rec.action}",
            "",
            f"**Criterio de aceptación:** {rec.acceptance}",
        ])
        if rec.commands:
            lines.extend(["", "**Comando:**", "", "```bash"])
            lines.extend(rec.commands)
            lines.append("```")
        lines.append("")
    if include_limits:
        lines.extend(limits_lines())
    return lines


def limits_lines() -> list[str]:
    return [
        "## Límites de esta conclusión",
        "",
        "- Los tests de vídeo son de contrato/placeholder: NativaX no decodifica "
        "vídeo todavía; no se afirma reproducción.",
        "- Los escenarios de juego de esta matriz son Canvas 2D; el "
        "`examples/game-player` Three.js completo requiere una medición aparte.",
        "- El RSS del arnés (`flutter test`) no es el RSS de la app; el idle real "
        "se mide aparte.",
        "- Las recomendaciones no prometen porcentajes de mejora; usan los "
        "cocientes y umbrales medidos.",
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
        "# NativaX — recomendaciones de calidad",
        "",
        f"Generado: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}.",
        "",
        "## Diagnóstico",
        "",
        "| Área | Estado |",
        "|---|---|",
        f"| Fidelidad visual | {len(visual_rows)}/{visual_total} medidas |",
        f"| Rendimiento | {len(perf_rows)}/{perf_total} medidos |",
        f"| App idle | {_num(app.get('rss_tail_mb'))} MB · "
        f"{_num(app.get('cpu_tail_pct'), 2)} % CPU |",
        f"| Vídeo | {len((data.get('video') or {}).get('profiles') or [])} perfiles · "
        f"playback {'sí' if ((data.get('video') or {}).get('capability') or {}).get('playback') else 'no'} |",
        f"| Juegos | {len((data.get('game') or {}).get('results') or []) + len((data.get('game3d') or {}).get('results') or [])} perfiles medidos |",
        "",
    ]
    lines.extend(["## Prioridades", ""])
    for priority in ("P0", "P1", "P2"):
        count = sum(1 for rec in recommendations if rec.priority == priority)
        if count:
            lines.append(f"- **{priority}:** {count}")
    lines.append("")
    lines.extend(markdown_lines(data, recommendations, include_limits=False))
    lines.extend(detailed_lines(data, recommendations))
    lines.extend(limits_lines())
    lines.extend([
        "## Cómo usar este informe",
        "",
        "El panel puede mostrar este contenido desde **Informes → Recomendaciones** "
        "o desde el informe **En vivo**. Para regenerarlo:",
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
    assert "Recomendaciones automáticas" in md
    print("recommend self-check OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

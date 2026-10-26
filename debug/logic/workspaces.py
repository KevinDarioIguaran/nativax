"""View models for the per-type report workspaces.

Each loader reads one report unit (a `catalog.ReportRef`) and returns plain
data for its workspace. Loaders never compute diagnostic results: they read
what the engine wrote. A missing file becomes an entry in `missing`, never a
default value.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

_LOGIC = Path(__file__).resolve().parent
if str(_LOGIC) not in sys.path:
    sys.path.insert(0, str(_LOGIC))

import catalog  # noqa: E402
import storage  # noqa: E402


def _json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except FileNotFoundError:
        return None, f"{path.name}: not in this report"
    except (OSError, ValueError) as error:
        return None, f"{path.name}: unreadable ({error})"


def _jsonl(path: Path, limit: int | None = None):
    rows, bad = [], 0
    try:
        with path.open(encoding="utf-8") as fh:
            for line in fh:
                if not line.strip():
                    continue
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    bad += 1
                if limit and len(rows) >= limit:
                    break
    except OSError as error:
        return [], 0, str(error)
    return rows, bad, None


def _engine_json(ev: Path, prefix: str):
    files = sorted(p for p in ev.glob(f"{prefix}*.json"))
    if not files:
        return None, None, [f"no {prefix}*.json in this report"]
    data, err = _json(files[0])
    return data, files[0], [err] if err else []


def common(ref) -> dict:
    """Manifest, integrity status and history of a run-manifest unit."""
    path = Path(ref.path)
    out = {"manifest": None, "integrity": [], "history": [], "verify": None}
    if ref.layout.startswith("run-manifest"):
        out["manifest"], _ = _json(path / "manifest.json")
        out["verify"] = storage.verify(path)
        out["history"] = storage.history(path)
    return out


# ------------------------------------------------------------------ visual
def visual(ref) -> dict:
    ev = catalog.evidence_dir(Path(ref.path))
    results, err = _json(ev / "results.json")
    report, err2 = _json(ev / "report.json")
    missing = [e for e in (err, err2) if e]
    pages = []
    for row in (results or {}).get("rows") or []:
        # Page ids are "<suite>/<page>". The engine also records absolute
        # paths to where it originally wrote (`artifacts`, `chrome_png`);
        # those point outside the archive, so only the archived copy is used.
        page = str(row.get("page"))
        pdir = ev / "pages" / page
        if not pdir.is_dir() and row.get("suite"):
            pdir = ev / "pages" / str(row["suite"]) / page
        pages.append({**row, "_dir": str(pdir)})
    return {"rows": pages, "columns": (results or {}).get("columns"), "report": report,
            "missing": missing, "environment": (report or {}).get("environment")}


def visual_page(page_dir: Path) -> dict:
    page_dir = Path(page_dir)
    images = {name: (page_dir / f"{name}.png") for name in ("chrome", "nativax", "diff", "overlay")}
    regions, rerr = _json(page_dir / "regions.json")
    env, eerr = _json(page_dir / "environment.json")
    pixels, perr = _json(page_dir / "pixels.json")
    elements, lerr = _json(page_dir / "elements.json")
    report, rperr = _json(page_dir / "report.json")
    return {
        "images": {k: (p if p.is_file() else None) for k, p in images.items()},
        "regions": (regions or {}).get("regions") if isinstance(regions, dict) else regions,
        "regions_doc": regions, "environment": env, "pixels": pixels, "elements": elements,
        "report": report,
        "missing": [e for e in (rerr, eerr, perr, lerr, rperr) if e]
        + [f"{k}.png: not in this report" for k, p in images.items() if not p.is_file()],
    }


# ------------------------------------------------------------- performance
def performance(ref) -> dict:
    ev = catalog.evidence_dir(Path(ref.path))
    data, err = _json(ev / "results.json")
    rows = []
    for r in (data or {}).get("results") or []:
        n, c = r.get("nativax") or {}, r.get("chromium") or {}
        nw = (n.get("scenario_ms") or 0) + (n.get("render_ms") or 0) if n.get("status") == "ok" else None
        cw = (c.get("scenario_ms") or 0) + (c.get("render_ms") or 0) if c.get("status") == "ok" else None
        rows.append({"scenario": r.get("scenario"), "kind": r.get("kind"), "verdict": r.get("verdict"),
                     "nativa_ms": nw, "chrome_ms": cw,
                     "ratio": (nw / cw) if nw is not None and cw and cw > 0.0001 else None,
                     "p95": (n.get("frame_ms") or {}).get("p95"), "rss_mb": n.get("rss_peak_mb"),
                     "nodes": n.get("nodes"), "reasons": "; ".join(r.get("reasons") or []), "_raw": r})
    idle, _ = _json(ev / "app-idle.json")
    return {"rows": rows, "summary": (data or {}).get("summary"), "environment": (data or {}).get("environment"),
            "idle": idle, "missing": [err] if err else []}


# ---------------------------------------------- memory / security / bench
def memory(ref) -> dict:
    data, path, missing = _engine_json(catalog.evidence_dir(Path(ref.path)), "leaks")
    rows = []
    for r in (data or {}).get("results") or []:
        evidence = r.get("evidence") if isinstance(r.get("evidence"), dict) else {}
        rows.append({"id": r.get("id"), "subsystem": r.get("subsystem"), "status": r.get("status"),
                     "classification": r.get("classification") or evidence.get("classification"),
                     "reason": r.get("reason"), "duration_ms": r.get("durationMs"),
                     "threshold_bytes": r.get("thresholdBytes"), "samples": len(r.get("samples") or []),
                     "_raw": r})
    if rows and all(r["classification"] is None for r in rows):
        missing.append("no leak classification fields: this run predates the proven/suspected "
                       "classification of the memory engine")
    return {"rows": rows, "metadata": (data or {}).get("metadata"), "source": str(path) if path else None,
            "missing": missing}


def security(ref) -> dict:
    data, path, missing = _engine_json(catalog.evidence_dir(Path(ref.path)), "security")
    rows = [{"id": r.get("id"), "category": r.get("category"), "severity": r.get("severity"),
             "status": r.get("status"), "expected": r.get("expected"), "observed": r.get("observed"),
             "description": r.get("description"), "remediation": r.get("remediation"), "_raw": r}
            for r in (data or {}).get("results") or []]
    return {"rows": rows, "metadata": (data or {}).get("metadata"), "source": str(path) if path else None,
            "missing": missing}


def microbenchmarks(ref) -> dict:
    data, path, missing = _engine_json(catalog.evidence_dir(Path(ref.path)), "bench")
    rows = [{"name": r.get("name"), "category": r.get("category"), "unit": r.get("unit"),
             "median_ms": r.get("medianMs"), "p95_ms": r.get("p95Ms"), "ci_low": r.get("medianCiLowMs"),
             "ci_high": r.get("medianCiHighMs"), "stddev_ms": r.get("stdDevMs"), "rounds": r.get("rounds"),
             "warmup": r.get("warmup"), "language": r.get("language"), "_raw": r}
            for r in (data or {}).get("results") or []]
    return {"rows": rows, "metadata": (data or {}).get("metadata"), "notes": (data or {}).get("notes"),
            "source": str(path) if path else None, "missing": missing}


# ----------------------------------------------------------- compatibility
def compatibility(ref, limit: int = 20000) -> dict:
    summary_path = Path(ref.path)
    summary, err = _json(summary_path)
    rows, bad, rerr = [], 0, None
    if summary is not None:
        if summary.get("resultsFile"):
            rows, bad, rerr = _jsonl(summary_path.parent / summary["resultsFile"], limit)
        else:
            rows = list(summary.get("results") or [])[:limit]
    missing = [e for e in (err, rerr) if e]
    if bad:
        missing.append(f"{bad} unreadable result line(s)")
    return {"summary": {k: v for k, v in (summary or {}).items() if k != "results"}, "rows": rows,
            "missing": missing, "truncated": len(rows) >= limit}


LOADERS = {"visual_comparison": visual, "performance": performance, "memory": memory,
           "security": security, "microbenchmarks": microbenchmarks, "compatibility": compatibility}

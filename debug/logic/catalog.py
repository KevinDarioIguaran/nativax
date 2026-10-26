"""Report catalog: every report of the debug suite as an independent unit.

Three storage conventions exist on disk and are read as they are (nothing
is moved or rewritten here):

1. Run manifests (`nativax/diagnostic-run-manifest@1.0|1.1`):
   `debug/artifacts/runs/<area>/<run_id>/` (evidence under `evidence/`) and
   `debug/benchmarks/<area>/<run_id>/` (evidence next to the manifest).
2. Audit runs written by `debug/engines/bug_detection`:
   `debug/artifacts/audit/**/runs/<run>/` with `summary.json` / `state.json`.
3. Conformance results: `debug/artifacts/conformance/results/<suite>-<ts>.summary.json`
   with its sibling `.jsonl` (one unit per summary; the pair is flat, not a
   directory — recorded as a limitation of that layout).

Each `ReportRef` points at one unit. Loading a unit never reads another
unit's files; comparisons are explicit calls with two refs.
"""
from __future__ import annotations

import json
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

_LOGIC = Path(__file__).resolve().parent
if str(_LOGIC) not in sys.path:
    sys.path.insert(0, str(_LOGIC))

import storage  # noqa: E402

ROOT = storage.ROOT
RUN_ROOTS = (ROOT / "debug" / "artifacts" / "runs", ROOT / "debug" / "benchmarks")
AUDIT_ROOT = ROOT / "debug" / "artifacts" / "audit"
CONFORMANCE_RESULTS = ROOT / "debug" / "artifacts" / "conformance" / "results"

# Storage area -> report type (the type picks the workspace and the schema).
AREA_TYPES = {
    "visual": "visual_comparison", "perf": "performance", "games": "performance",
    "games3d": "performance", "leaks": "memory", "memory": "memory", "security": "security",
    "microbench": "microbenchmarks", "microbenchmarks": "microbenchmarks",
    "quality_gate": "quality_gate", "gate": "quality_gate", "recommendations": "recommendations",
    "compatibility": "compatibility", "conformance": "compatibility",
}
TYPES = ("bug_detection", "visual_comparison", "performance", "memory", "compatibility", "security",
         "microbenchmarks", "recommendations", "quality_gate", "engine_audit")


@dataclass
class ReportRef:
    type: str
    area: str
    id: str
    path: str
    layout: str
    created_at: str | None = None
    status: str | None = None
    health: str = "unknown"          # error | warn | ok | unknown
    commit: str | None = None
    engine: str | None = None
    summary: str = ""
    counts: dict = field(default_factory=dict)
    previous: str | None = None
    lineage_key: str | None = None
    errors: list = field(default_factory=list)
    alias_of: str | None = None

    def as_dict(self):
        return asdict(self)


def _json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except FileNotFoundError:
        return None, f"{path.name} is missing"
    except (OSError, ValueError) as error:
        return None, f"{path.name} is unreadable: {error}"


def evidence_dir(run_dir: Path) -> Path:
    return run_dir / "evidence" if (run_dir / "evidence").is_dir() else run_dir


# ---------------------------------------------------------------- discovery
def _run_refs() -> list[ReportRef]:
    out = []
    for base in RUN_ROOTS:
        if not base.is_dir():
            continue
        for area_dir in sorted(p for p in base.iterdir() if p.is_dir()):
            for run_dir in sorted(p for p in area_dir.iterdir() if p.is_dir()):
                if not (run_dir / "manifest.json").exists():
                    continue
                manifest, err = _json(run_dir / "manifest.json")
                errors = [err] if err else []
                if manifest is not None:
                    errors += [f"manifest: {e}" for e in storage.check_manifest(manifest)]
                m = manifest or {}
                status = m.get("status")
                health = {"completed": "ok", "failed": "error", "aborted": "warn"}.get(status, "unknown")
                ref = ReportRef(
                    type=AREA_TYPES.get(area_dir.name, area_dir.name), area=area_dir.name,
                    id=run_dir.name, path=str(run_dir),
                    layout=f"run-manifest-{m.get('schema_version', '?')}",
                    created_at=m.get("archived_at"), status=status, health=health,
                    commit=m.get("git_revision"), engine=m.get("engine"),
                    summary=m.get("notes") or "", previous=m.get("previous_run"),
                    lineage_key=m.get("lineage_key"), errors=errors)
                _enrich_run(ref, run_dir)
                out.append(ref)
    return out


def _enrich_run(ref: ReportRef, run_dir: Path) -> None:
    """Outcome counts from the engine's own result file (read-only)."""
    ev = evidence_dir(run_dir)
    if ref.type in ("visual_comparison", "performance"):
        data, _ = _json(ev / "results.json")
        rows = (data or {}).get("rows") if ref.type == "visual_comparison" else (data or {}).get("results")
        if rows is not None:
            counts: dict[str, int] = {}
            for r in rows:
                v = str(r.get("verdict") or "unknown").upper()
                counts[v] = counts.get(v, 0) + 1
            ref.counts = counts
            ref.summary = " · ".join(f"{k} {v}" for k, v in sorted(counts.items()))
            if counts.get("FAIL") or counts.get("INVALID"):
                ref.health = "error" if ref.health != "unknown" else ref.health
            elif counts.get("WARN") and ref.health == "ok":
                ref.health = "warn"
    elif ref.type in ("memory", "security", "microbenchmarks"):
        jsons = sorted(p for p in ev.glob("*.json") if p.name not in ("manifest.json", "integrity.json"))
        data, _ = _json(jsons[0]) if jsons else (None, None)
        results = (data or {}).get("results") if isinstance(data, dict) else None
        if isinstance(results, list):
            counts = {}
            for r in results:
                v = str(r.get("status") or r.get("verdict") or "measured").upper()
                counts[v] = counts.get(v, 0) + 1
            ref.counts = counts
            ref.summary = " · ".join(f"{k} {v}" for k, v in sorted(counts.items()))
            if counts.get("FAIL") or counts.get("ERROR"):
                ref.health = "error"


def _audit_refs() -> list[ReportRef]:
    out = []
    if not AUDIT_ROOT.is_dir():
        return out
    for summary_or_state in sorted(AUDIT_ROOT.rglob("summary.json")) + sorted(AUDIT_ROOT.rglob("state.json")):
        run_dir = summary_or_state.parent
        if any(o.path == str(run_dir) for o in out) or "work" in run_dir.parts or "replay" in run_dir.parts:
            continue
        kind = "engine_audit" if ("benchmark" in run_dir.parts or "self-check" in run_dir.parts) else "bug_detection"
        summary, err = _json(run_dir / "summary.json")
        ref = ReportRef(type=kind, area="audit", id=run_dir.name, path=str(run_dir), layout="audit-run")
        if summary is None:
            state, _ = _json(run_dir / "state.json")
            ref.status = "incomplete"
            ref.summary = "summary.json missing: run in progress or interrupted"
            ref.created_at = (state or {}).get("updated_at")
            ref.errors = [err] if err and "missing" not in err else []
            out.append(ref)
            continue
        m = summary.get("metrics") or {}
        issues = [i for i in summary.get("issues") or [] if i.get("status") == "failed"]
        severe = sum(1 for i in issues if i.get("severity") in ("critical", "high"))
        ref.status = "completed"
        ref.created_at = summary.get("started_at")
        ref.commit = (summary.get("system") or {}).get("git_commit")
        ref.engine = "nxaudit"
        ref.health = "error" if severe else ("warn" if issues else "ok")
        ref.counts = {"executed": m.get("executed"), "issues": len(issues), "critical_high": severe}
        ref.summary = f"{m.get('executed', '—')} scenarios · {len(issues)} issues ({severe} critical/high)"
        if run_dir.name == "latest":
            ref.alias_of = summary.get("run_id")
        out.append(ref)
    return out


def _conformance_refs() -> list[ReportRef]:
    out = []
    if not CONFORMANCE_RESULTS.is_dir():
        return out
    for path in sorted(CONFORMANCE_RESULTS.glob("*.summary.json")):
        data, err = _json(path)
        d = data or {}
        counts = d.get("counts") or {k: d.get(k) for k in ("pass", "fail", "skip", "error") if k in d}
        ref = ReportRef(type="compatibility", area="conformance", id=path.name[: -len(".summary.json")],
                        path=str(path), layout="conformance-summary",
                        created_at=d.get("startedAt") or d.get("started_at") or d.get("timestamp"),
                        status="completed" if data else None,
                        health="unknown", engine=d.get("suite"),
                        commit=d.get("gitRevision") or d.get("git_revision"),
                        counts=counts or {}, errors=[err] if err else [])
        if counts:
            ref.summary = " · ".join(f"{k} {v}" for k, v in counts.items() if v is not None)
            if d.get("passRate") is not None:
                ref.summary += f" · pass rate {d['passRate']:.2f} %"
            # Failing conformance tests are expected; a runner error is not.
            low = {str(k).lower(): v or 0 for k, v in counts.items()}
            ref.health = "error" if low.get("error") else ("warn" if low.get("fail") else "ok")
        if ref.created_at and "+" not in ref.created_at[10:] and not ref.created_at.endswith("Z"):
            ref.errors.append("startedAt has no timezone offset (runner output before the 2026-10-26 fix)")
        out.append(ref)
    return out


def discover() -> list[ReportRef]:
    refs = _run_refs() + _audit_refs() + _conformance_refs()
    return sorted(refs, key=lambda r: (r.created_at or "", r.id), reverse=True)


def counts_by_type(refs: list[ReportRef]) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {}
    for r in refs:
        bucket = out.setdefault(r.type, {})
        bucket[r.health] = bucket.get(r.health, 0) + 1
        bucket["total"] = bucket.get("total", 0) + 1
    return out


def search(refs: list[ReportRef], query: str) -> list[ReportRef]:
    """Case-insensitive substring match over id, type, area, engine, commit,
    summary and errors. Every term must match (AND)."""
    terms = [t for t in query.lower().split() if t]
    if not terms:
        return list(refs)
    out = []
    for r in refs:
        hay = " ".join(str(x) for x in (r.id, r.type, r.area, r.engine, r.commit, r.summary, r.status,
                                         r.path, " ".join(r.errors))).lower()
        if all(t in hay for t in terms):
            out.append(r)
    return out


def comparable(a: ReportRef, b: ReportRef) -> tuple[bool, str]:
    """Whether two refs may be compared side by side, and why not."""
    if a.type != b.type:
        return False, f"different report types ({a.type} vs {b.type})"
    if a.layout.startswith("run-manifest") and b.layout.startswith("run-manifest"):
        if a.lineage_key is None or b.lineage_key is None:
            return False, "lineage unknown (schema 1.0 manifest): configuration equality cannot be checked"
        if a.lineage_key != b.lineage_key:
            return False, f"different configuration ({a.lineage_key} vs {b.lineage_key})"
        return True, "same area, engine and configuration"
    if a.layout == b.layout == "audit-run":
        return True, "both are audit runs; configuration differences are listed by the comparison"
    return False, f"no comparison defined between layouts {a.layout} and {b.layout}"

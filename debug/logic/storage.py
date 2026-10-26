"""Immutable per-run storage for the diagnostic engines.

Every finished run of an area is archived under
``debug/artifacts/runs/<area>/<run_id>/``:

    debug/artifacts/runs/visual/20261025T211530Z-f47240e/
        manifest.json          versioned, schema-validated record
        evidence/              byte copy of what the engine wrote
        reports/               snapshot of that area's report

Nothing in a run directory is ever rewritten: a new run creates a new
directory, so the screenshots, probes and reports of earlier runs survive.
``prune()`` is the only deletion path and it must be called explicitly.

The engines keep writing to their existing ``latest`` directories — readers
(`debug/artifacts/visual/latest`, `debug/artifacts/perf/latest`, DataStore,
recommend, quality_gate) do not change. Archiving copies from there after the
run finishes.

Layout contract (schema `debug/logic/schemas/run-manifest.schema.json`):
`run_id` is `<UTC ISO basic>Z[-<git short sha>][-N]`, so sorting run ids
lexicographically sorts runs oldest to newest. Timestamps carry an offset.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

_LOGIC = Path(__file__).resolve().parent
if str(_LOGIC) not in sys.path:
    sys.path.insert(0, str(_LOGIC))

from json_validate import validate  # noqa: E402

ROOT = _LOGIC.parent.parent
RUNS_ROOT = ROOT / "debug" / "artifacts" / "runs"
SCHEMA_PATH = _LOGIC / "schemas" / "run-manifest.schema.json"
HISTORY_SCHEMA_PATH = _LOGIC / "schemas" / "run-history-entry.schema.json"
SCHEMA_VERSION = "1.1"
STATUS_VALUES = ("completed", "failed", "aborted")
HISTORY_KINDS = ("annotation", "review", "reevaluation", "comparison", "superseded_by",
                 "verification", "migration_note")
# argv flags whose value is an output location: they do not change what a
# run measures, so they are left out of the lineage key.
_OUTPUT_FLAGS = {"--out", "--out-dir", "--json", "--md", "--jsonl", "--results-dir", "--markdown"}

_git_revision_cache: str | None | bool = False


@lru_cache(maxsize=1)
def load_schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text())


def check_manifest(manifest) -> list[str]:
    """Schema errors for a manifest (empty list when valid)."""
    return validate(manifest, load_schema())


def now_iso() -> str:
    """Local time with an explicit UTC offset, second precision."""
    return datetime.now().astimezone().isoformat(timespec="seconds")


def git_revision(root: Path | None = None) -> str | None:
    """Short commit of the inspected tree, or None outside a checkout.

    Only the default repository root is cached; an explicit `root` is always
    measured so callers cannot receive another tree's revision.
    """
    global _git_revision_cache
    if root is None and _git_revision_cache is not False:
        return _git_revision_cache
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=str(root or ROOT),
            capture_output=True,
            text=True,
            timeout=10,
        )
        revision = out.stdout.strip() if out.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        revision = None
    revision = revision or None
    if root is None:
        _git_revision_cache = revision
    return revision


def _runs_root(runs_root: Path | None) -> Path:
    return Path(runs_root) if runs_root is not None else RUNS_ROOT


def _new_run_dir(area_root: Path, revision: str | None) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    base = f"{stamp}-{revision}" if revision else stamp
    run_dir = area_root / base
    counter = 2
    while run_dir.exists():
        run_dir = area_root / f"{base}-{counter}"
        counter += 1
    return run_dir


def _evidence_stats(evidence_dir: Path) -> tuple[int, int]:
    files = 0
    total = 0
    for path in evidence_dir.rglob("*"):
        if path.is_file():
            files += 1
            total += path.stat().st_size
    return files, total


def lineage_key(area: str, engine: str | None, argv: list[str] | None) -> str:
    """Same area, engine and configuration (argv without output paths)."""
    parts, skip = [], False
    for arg in [str(a) for a in (argv or [])]:
        if skip:
            skip = False
            continue
        if arg in _OUTPUT_FLAGS:
            skip = True
            continue
        if any(arg.startswith(flag + "=") for flag in _OUTPUT_FLAGS):
            continue
        parts.append(arg)
    digest = hashlib.sha1(json.dumps(parts).encode()).hexdigest()[:12]
    return f"{area}:{engine or '-'}:{digest}"


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _write_integrity(run_dir: Path) -> int:
    files = []
    for path in sorted(run_dir.rglob("*")):
        rel = path.relative_to(run_dir).as_posix()
        if not path.is_file() or rel.split("/")[0] == "history" or rel in (
                "manifest.json", "integrity.json") or path.name.startswith("."):
            continue
        files.append({"path": rel, "bytes": path.stat().st_size, "sha256": _sha256(path)})
    (run_dir / "integrity.json").write_text(json.dumps(
        {"algorithm": "sha256", "files": files}, indent=2) + "\n")
    return len(files)


def _freeze(run_dir: Path) -> None:
    """Archived evidence becomes read-only; only history/ stays writable."""
    ro_file = stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH
    ro_dir = ro_file | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    for dirpath, _dirs, files in os.walk(run_dir, topdown=False):
        d = Path(dirpath)
        if d.relative_to(run_dir).parts[:1] == ("history",):
            continue
        for name in files:
            os.chmod(d / name, ro_file)
        if d != run_dir:
            os.chmod(d, ro_dir)


def _thaw(run_dir: Path) -> None:
    for dirpath, _dirs, files in os.walk(run_dir):
        os.chmod(dirpath, 0o755)
        for name in files:
            os.chmod(Path(dirpath) / name, 0o644)


def _write_manifest(run_dir: Path, manifest: dict) -> None:
    errors = check_manifest(manifest)
    if errors:
        raise ValueError("invalid run manifest: " + "; ".join(errors))
    tmp = run_dir / ".manifest.json.tmp"
    tmp.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(run_dir / "manifest.json")


def archive(
    area: str,
    source: Path | str,
    *,
    engine: str | None = None,
    argv: list[str] | None = None,
    reports: list[Path | str] | None = None,
    status: str = "completed",
    notes: str | None = None,
    runs_root: Path | None = None,
    lineage: str | None = None,
) -> Path:
    """Copies `source` into a new immutable run directory for `area`.

    Returns the run directory. Raises when the source does not exist, the
    status is unknown or the manifest would not validate; in that case
    nothing is published (a partial directory is removed).
    """
    if status not in STATUS_VALUES:
        raise ValueError(f"unknown status {status!r}; expected one of {STATUS_VALUES}")
    source = Path(source)
    if not source.is_dir():
        raise FileNotFoundError(f"run evidence not found: {source}")

    root = _runs_root(runs_root)
    area_root = root / area
    area_root.mkdir(parents=True, exist_ok=True)
    run_dir = _new_run_dir(area_root, git_revision())
    evidence = run_dir / "evidence"
    try:
        shutil.copytree(source, evidence)
        files, total = _evidence_stats(evidence)
        copied_reports = []
        for report in reports or []:
            report = Path(report)
            if not report.is_file():
                continue
            target_dir = run_dir / "reports"
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / report.name
            if target.exists():
                target = target_dir / f"{run_dir.name}-{report.name}"
            shutil.copy2(report, target)
            copied_reports.append(f"reports/{target.name}")
        key = lineage or lineage_key(area, engine, argv)
        previous = next((r.name for r in runs(area, root) if r != run_dir
                         and (load_manifest(r) or {}).get("lineage_key") == key), None)
        (run_dir / "history").mkdir()
        integrity_files = _write_integrity(run_dir)
        manifest = {
            "schema_version": SCHEMA_VERSION,
            "run_id": run_dir.name,
            "area": area,
            "engine": engine,
            "status": status,
            "archived_at": now_iso(),
            "git_revision": git_revision(),
            "argv": [str(part) for part in (argv or [])],
            "source": str(source),
            "evidence": {"files": files, "bytes": total},
            "reports": copied_reports,
            "notes": notes,
            "lineage_key": key,
            "previous_run": previous,
            "integrity": {"algorithm": "sha256", "file": "integrity.json",
                          "files": integrity_files},
        }
        _write_manifest(run_dir, manifest)
        _freeze(run_dir)
    except Exception:
        if run_dir.exists():
            _thaw(run_dir)
        shutil.rmtree(run_dir, ignore_errors=True)
        raise
    if previous:
        append_history(root / area / previous, "superseded_by", {"next_run": run_dir.name},
                       author="debug/logic/storage.py", refs=[run_dir.name])
    return run_dir


def append_history(run_dir: Path | str, kind: str, data: dict, *, author: str,
                   refs: list[str] | None = None) -> Path:
    """Adds one entry under history/; existing entries are never rewritten."""
    run_dir = Path(run_dir)
    if kind not in HISTORY_KINDS:
        raise ValueError(f"unknown history kind {kind!r}; expected one of {HISTORY_KINDS}")
    entry = {"schema_version": "1.0", "kind": kind, "created_at": now_iso(), "author": author,
             "run_id": run_dir.name, "refs": list(refs or []), "data": data}
    errors = validate(entry, json.loads(HISTORY_SCHEMA_PATH.read_text()))
    if errors:
        raise ValueError("invalid history entry: " + "; ".join(errors))
    hdir = run_dir / "history"
    hdir.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    for seq in range(1000):
        target = hdir / f"{stamp}-{seq:03d}-{kind}.json"
        try:
            with target.open("x") as fh:
                fh.write(json.dumps(entry, indent=2, ensure_ascii=False) + "\n")
        except FileExistsError:
            continue
        os.chmod(target, stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)
        return target
    raise RuntimeError("could not allocate a history entry")


def history(run_dir: Path | str) -> list[dict]:
    """History entries oldest first; unreadable entries are reported, not skipped."""
    out = []
    hdir = Path(run_dir) / "history"
    for path in sorted(hdir.glob("*.json")) if hdir.is_dir() else []:
        try:
            out.append({"file": path.name, **json.loads(path.read_text())})
        except (OSError, json.JSONDecodeError) as error:
            out.append({"file": path.name, "error": f"unreadable history entry: {error}"})
    return out


def verify(run_dir: Path | str) -> list[str]:
    """Problems with an archived run: invalid manifest, missing or changed
    evidence. Version 1.0 runs carry no hashes; that is stated, not hidden."""
    run_dir = Path(run_dir)
    try:
        manifest = json.loads((run_dir / "manifest.json").read_text())
    except (OSError, json.JSONDecodeError) as error:
        return [f"manifest.json unreadable: {error}"]
    problems = [f"manifest: {e}" for e in check_manifest(manifest)]
    if manifest.get("schema_version") == "1.0":
        return problems + ["schema 1.0 run: no integrity hashes recorded, evidence cannot be verified"]
    try:
        integrity = json.loads((run_dir / "integrity.json").read_text())
    except (OSError, json.JSONDecodeError) as error:
        return problems + [f"integrity.json unreadable: {error}"]
    for f in integrity.get("files") or []:
        path = run_dir / f["path"]
        if not path.is_file():
            problems.append(f"missing: {f['path']}")
        elif path.stat().st_size != f["bytes"] or _sha256(path) != f["sha256"]:
            problems.append(f"changed after archiving: {f['path']}")
    return problems


def runs(area: str, runs_root: Path | None = None) -> list[Path]:
    """Run directories of `area`, newest first (run ids sort by time)."""
    area_root = _runs_root(runs_root) / area
    if not area_root.is_dir():
        return []
    entries = [p for p in area_root.iterdir() if p.is_dir() and not p.name.startswith(".")]
    return sorted(entries, key=lambda p: p.name, reverse=True)


def latest_run(area: str, runs_root: Path | None = None) -> Path | None:
    candidates = runs(area, runs_root)
    return candidates[0] if candidates else None


def load_manifest(run_dir: Path | str) -> dict | None:
    """The manifest of a run, or None when missing or invalid."""
    try:
        data = json.loads((Path(run_dir) / "manifest.json").read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return data if not check_manifest(data) else None


def prune(area: str, keep: int, runs_root: Path | None = None) -> list[Path]:
    """Deletes all but the newest `keep` runs of `area`. Returns the removed
    directories. Never called automatically: evidence is only lost on
    request."""
    if keep < 0:
        raise ValueError("keep must be >= 0")
    entries = runs(area, runs_root)
    removed = entries[keep:]
    for run_dir in removed:
        _thaw(run_dir)
        shutil.rmtree(run_dir, ignore_errors=True)
    return removed


def main(argv: list[str] | None = None) -> int:
    """`python3 debug/logic/storage.py <area>` lists runs newest first."""
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] in ("-h", "--help"):
        print("usage: storage.py <area>   # list runs, newest first")
        return 0 if args else 64
    entries = runs(args[0])
    if not entries:
        print(f"no runs for area {args[0]!r}")
        return 1
    for run_dir in entries:
        manifest = load_manifest(run_dir)
        if manifest is None:
            print(f"{run_dir.name}\tINVALID manifest")
        else:
            print(f"{run_dir.name}\t{manifest['status']}\t{manifest['engine']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

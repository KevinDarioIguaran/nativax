#!/usr/bin/env python3
"""Compact, provenance-preserving context for coding agents.

The repository already stores canonical evidence: run manifests, conformance
JSONL/summaries, reports and Markdown sources. This module derives bounded,
machine-readable indexes from that evidence instead of asking a model to read
whole directories.

Commands (also available as ``python3 debug/run.py context ...``):

    python3 debug/logic/context.py inventory [--json]
    python3 debug/logic/context.py runs [--all] [--limit N] [--area NAME]
    python3 debug/logic/context.py conformance [--all]
    python3 debug/logic/context.py docs [--limit N]
    python3 debug/logic/context.py brief [--budget TOKENS]
    python3 debug/logic/context.py measure PATH...
    python3 debug/logic/context.py index

``index`` writes ``debug/artifacts/index/{runs,conformance,docs}.jsonl``;
queries read those derived files when present and rebuild from canonical
evidence otherwise. Every record carries a schema id, and every derived record
carries the relative path of its source.

Token counts use ``tiktoken`` when the package is installed (the tokenizer name
is reported); otherwise they are explicitly labelled UTF-8 byte estimates
(``ceil(bytes / 4)``). This machine has no tokenizer installed, so the
measurements in the report are estimates, not exact tokens.
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from functools import lru_cache
from pathlib import Path
from typing import Iterable

_LOGIC = Path(__file__).resolve().parent
if str(_LOGIC) not in sys.path:
    sys.path.insert(0, str(_LOGIC))

import storage  # noqa: E402

ROOT = _LOGIC.parent.parent
INDEX_ROOT = ROOT / "debug" / "artifacts" / "index"
BENCHMARKS_ROOT = ROOT / "debug" / "benchmarks"
ARCHIVE_ROOT = ROOT / "debug" / "artifacts" / "runs"
CONFORMANCE_RESULTS = ROOT / "debug" / "artifacts" / "conformance" / "results"

RUN_SCHEMA = "nativax.run.v1"
CONFORMANCE_SCHEMA = "nativax.conformance.run.v1"
DOC_SCHEMA = "nativax.doc.v1"
INVENTORY_SCHEMA = "nativax.inventory.v1"
BRIEF_SCHEMA = "nativax.context.brief.v1"
MEASURE_SCHEMA = "nativax.context.measure.v1"

_SKIP_DIRS = {".git", ".dart_tool", "build", "node_modules", "__pycache__"}
_SKIP_PREFIXES = ("debug/artifacts/",)
_DOC_ROOTS = ("docs", "progress", "AGENTS.md", "CLAUDE.md", ".agents")


# --------------------------------------------------------------------------
# token accounting


@lru_cache(maxsize=1)
def _tiktoken_encoder():
    try:
        import tiktoken  # type: ignore
    except Exception:
        return None, None
    try:
        return tiktoken.get_encoding("cl100k_base"), f"tiktoken cl100k_base {tiktoken.__version__}"
    except Exception:
        return None, None


def count_tokens(text: str):
    """(tokens, tokenizer label). Falls back to a labelled estimate."""
    encoder, label = _tiktoken_encoder()
    if encoder is not None:
        return len(encoder.encode(text)), label
    return math.ceil(len(text.encode("utf-8")) / 4), "estimate:utf8_bytes/4"


def _json(value) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _finite(value: float) -> float:
    """Stable float precision for reports (no binary noise)."""
    return round(float(value), 6)


# --------------------------------------------------------------------------
# inventory


def _git_files(root: Path) -> list[Path]:
    try:
        out = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=str(root),
            capture_output=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if out.returncode != 0:
        return []
    return [root / name for name in out.stdout.decode("utf-8", "replace").split("\0") if name]


def _walk_files(root: Path) -> list[Path]:
    found: list[Path] = []
    for path in root.rglob("*"):
        rel = path.relative_to(root).as_posix()
        if any(part in _SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        if any(rel.startswith(prefix) for prefix in _SKIP_PREFIXES):
            continue
        if path.is_file():
            found.append(path)
    return found


def _rel(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def inventory(root: Path | str = ROOT) -> dict:
    """Tracked-file inventory grouped by top-level directory and extension."""
    root = Path(root)
    files = _git_files(root)
    tracked = bool(files)
    if not tracked:
        files = _walk_files(root)
    by_top: dict[str, dict] = {}
    by_ext: dict[str, dict] = {}
    total = 0
    counted = 0
    missing = []
    for path in files:
        try:
            size = path.stat().st_size
        except OSError:
            missing.append(_rel(path, root))
            continue
        rel = _rel(path, root)
        top = rel.split("/", 1)[0] if "/" in rel else "(root)"
        ext = path.suffix.lower() or "(none)"
        for bucket, key in ((by_top, top), (by_ext, ext)):
            entry = bucket.setdefault(key, {"files": 0, "bytes": 0})
            entry["files"] += 1
            entry["bytes"] += size
        total += size
        counted += 1
    return {
        "schema": INVENTORY_SCHEMA,
        "root": ".",
        "tracked": tracked,
        "files": counted,
        "bytes": total,
        "missing": len(missing),
        "missingPaths": missing[:10],
        "byTop": [
            {"name": key, **value}
            for key, value in sorted(by_top.items(), key=lambda kv: (-kv[1]["bytes"], kv[0]))
        ],
        "byExtension": [
            {"name": key, **value}
            for key, value in sorted(by_ext.items(), key=lambda kv: (-kv[1]["bytes"], kv[0]))[:24]
        ],
    }


# --------------------------------------------------------------------------
# runs


def _manifest_paths(root: Path) -> list[tuple[Path, str]]:
    paths = [(path, "benchmark") for path in sorted((root / "debug" / "benchmarks").glob("*/*/manifest.json"))]
    paths += [(path, "archive") for path in sorted((root / "debug" / "artifacts" / "runs").glob("*/*/manifest.json"))]
    return paths


def scan_runs(root: Path | str = ROOT) -> list[dict]:
    """One compact record per benchmark/archive run, newest run id first."""
    root = Path(root)
    records: list[dict] = []
    for path, kind in _manifest_paths(root):
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if storage.check_manifest(data):
            continue
        evidence = data.get("evidence") or {}
        records.append({
            "schema": RUN_SCHEMA,
            "runId": data["run_id"],
            "area": data["area"],
            "kind": kind,
            "status": data["status"],
            "engine": data.get("engine"),
            "revision": data.get("git_revision"),
            "archivedAt": data["archived_at"],
            "files": evidence.get("files"),
            "bytes": evidence.get("bytes"),
            "source": data.get("source"),
            "path": _rel(path.parent, root),
        })
    records.sort(key=lambda item: item["runId"], reverse=True)
    return records


# --------------------------------------------------------------------------
# conformance


def _summary_metadata(path: Path, root: Path) -> dict | None:
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    counts = data.get("counts") or {}
    total = data.get("total")
    if not isinstance(total, int):
        total = sum(v for v in counts.values() if isinstance(v, int))
    suite = data.get("suite") or path.name.split("-")[0]
    command = data.get("command")
    return {
        "schema": CONFORMANCE_SCHEMA,
        "suite": suite,
        "runKey": f"{suite}:{command}" if command else suite,
        "startedAt": data.get("startedAt"),
        "durationMs": data.get("durationMs"),
        "counts": {key: counts.get(key, 0) for key in ("PASS", "FAIL", "SKIP", "ERROR")},
        "total": total,
        "passRate": _finite(data.get("passRate") or 0),
        "command": command,
        "resultsFile": data.get("resultsFile"),
        "bytes": path.stat().st_size,
        "path": _rel(path, root),
    }


def scan_conformance(
    results_dir: Path | str = CONFORMANCE_RESULTS,
    root: Path | str = ROOT,
) -> list[dict]:
    """Metadata for every summary, newest first. Full results stay in JSONL."""
    results_dir = Path(results_dir)
    root = Path(root)
    if not results_dir.is_dir():
        return []
    records = []
    for path in results_dir.glob("*.summary.json"):
        record = _summary_metadata(path, root)
        if record:
            records.append(record)
    records.sort(key=lambda item: (item.get("startedAt") or "", item["path"]), reverse=True)
    return records


def latest_by_suite(records: Iterable[dict], min_total: int = 0) -> list[dict]:
    """Newest record per suite *and command* (WPT runs different directories).

    ``min_total`` hides exploratory smoke runs (a two-test WPT slice is not a
    suite baseline). Pass 0 to include them.
    """
    latest: dict[str, dict] = {}
    for record in records:
        if (record.get("total") or 0) < min_total:
            continue
        latest.setdefault(record.get("runKey") or record["suite"], record)
    return sorted(latest.values(), key=lambda item: item.get("startedAt") or "", reverse=True)


# --------------------------------------------------------------------------
# documentation index


def _headings(text: str, limit: int = 12) -> tuple[str | None, list[str]]:
    title = None
    headings: list[str] = []
    for line in text.splitlines():
        if not line.startswith("#"):
            continue
        level = len(line) - len(line.lstrip("#"))
        label = line[level:].strip()
        if not label:
            continue
        if level == 1 and title is None:
            title = label
        elif level == 2 and len(headings) < limit:
            headings.append(label)
    return title, headings


def scan_docs(root: Path | str = ROOT) -> list[dict]:
    """Path, title, size and H2 outline of maintained Markdown."""
    root = Path(root)
    paths: list[Path] = []
    for name in ("AGENTS.md", "CLAUDE.md"):
        if (root / name).is_file():
            paths.append(root / name)
    for directory in ("docs", "progress", ".agents"):
        base = root / directory
        if base.is_dir():
            paths.extend(sorted(base.rglob("*.md")))
    records = []
    seen = set()
    for path in paths:
        rel = _rel(path, root)
        if rel in seen:
            continue
        seen.add(rel)
        if "__pycache__" in path.parts:
            continue
        try:
            text = path.read_text()
        except OSError:
            continue
        title, headings = _headings(text)
        records.append({
            "schema": DOC_SCHEMA,
            "path": rel,
            "title": title,
            "headings": headings,
            "bytes": len(text.encode("utf-8")),
            "lines": text.count("\n") + (0 if text.endswith("\n") else 1),
        })
    records.sort(key=lambda item: item["path"])
    return records


# --------------------------------------------------------------------------
# indexes and briefs


def write_indexes(root: Path | str = ROOT) -> dict[str, str]:
    root = Path(root)
    out = root / "debug" / "artifacts" / "index"
    out.mkdir(parents=True, exist_ok=True)
    written = {}
    for name, records in (
        ("runs", scan_runs(root)),
        ("conformance", scan_conformance(
            root / "debug" / "artifacts" / "conformance" / "results", root
        )),
        ("docs", scan_docs(root)),
    ):
        path = out / f"{name}.jsonl"
        path.write_text("".join(_json(record) + "\n" for record in records))
        written[name] = _rel(path, root)
    return written


def _read_index(name: str, root: Path) -> list[dict] | None:
    path = root / "debug" / "artifacts" / "index" / f"{name}.jsonl"
    if not path.is_file():
        return None
    records = []
    for line in path.read_text().splitlines():
        if line.strip():
            records.append(json.loads(line))
    return records


def _newest_mtime(paths: Iterable[Path]) -> float:
    newest = 0.0
    for path in paths:
        try:
            newest = max(newest, path.stat().st_mtime)
        except OSError:
            continue
    return newest


def _fresh_index(name: str, root: Path, sources: Iterable[Path]) -> list[dict] | None:
    """An index is usable only when it is newer than every canonical source."""
    path = root / "debug" / "artifacts" / "index" / f"{name}.jsonl"
    try:
        if path.stat().st_mtime < _newest_mtime(sources):
            return None
    except OSError:
        return None
    return _read_index(name, root)


def _runs(root: Path, use_index: bool = True) -> list[dict]:
    if use_index:
        indexed = _fresh_index("runs", root, (path for path, _ in _manifest_paths(root)))
        if indexed is not None:
            return indexed
    return scan_runs(root)


def _conformance(root: Path, use_index: bool = True) -> list[dict]:
    results = root / "debug" / "artifacts" / "conformance" / "results"
    if use_index:
        indexed = _fresh_index("conformance", root, results.glob("*.summary.json"))
        if indexed is not None:
            return indexed
    return scan_conformance(results, root)


def _docs(root: Path, use_index: bool = True) -> list[dict]:
    if use_index:
        sources = list((root / "docs").rglob("*.md")) if (root / "docs").is_dir() else []
        sources += list((root / "progress").rglob("*.md")) if (root / "progress").is_dir() else []
        sources += list((root / ".agents").rglob("*.md")) if (root / ".agents").is_dir() else []
        sources += [path for path in (root / "AGENTS.md", root / "CLAUDE.md") if path.is_file()]
        indexed = _fresh_index("docs", root, sources)
        if indexed is not None:
            return indexed
    return scan_docs(root)


def brief(root: Path | str = ROOT, budget: int = 2000) -> dict:
    """Bounded overview: inventory, newest runs, latest conformance, doc index.

    Lists are truncated to fit ``budget`` estimated tokens and the number of
    omitted records is reported explicitly.
    """
    root = Path(root)
    inv = inventory(root)
    runs = _runs(root)
    conformance = latest_by_suite(_conformance(root), min_total=100)
    docs = _docs(root)
    payload = {
        "schema": BRIEF_SCHEMA,
        "repo": {
            "files": inv["files"],
            "bytes": inv["bytes"],
            "top": inv["byTop"][:6],
        },
        "runs": runs[:8],
        "conformance": conformance,
        "docs": docs[:16],
    }
    # Reserve room for the envelope added below so the final object fits.
    effective = max(64, budget - 64)
    tokens, label = count_tokens(_json(payload))
    truncations = {}
    while tokens > effective:
        largest = max(
            ("runs", payload["runs"]), ("conformance", payload["conformance"]), ("docs", payload["docs"]),
            key=lambda item: len(item[1]),
        )
        if not largest[1]:
            break
        largest[1].pop()
        truncations[largest[0]] = truncations.get(largest[0], 0) + 1
        tokens, label = count_tokens(_json(payload))
    payload["truncated"] = truncations
    payload["tokenizer"] = label
    tokens, _ = count_tokens(_json(payload))
    payload["estimatedTokens"] = tokens
    return payload


# --------------------------------------------------------------------------
# measurements


def measure(paths: Iterable[Path | str], root: Path | str = ROOT) -> dict:
    root = Path(root)
    rows = []
    total_bytes = 0
    total_tokens = 0
    label = None
    for raw in paths:
        path = Path(raw)
        if not path.is_absolute():
            path = root / path
        try:
            text = path.read_text()
        except (OSError, UnicodeDecodeError) as exc:
            rows.append({"path": _rel(path, root), "error": str(exc)})
            continue
        tokens, label = count_tokens(text)
        size = len(text.encode("utf-8"))
        total_bytes += size
        total_tokens += tokens
        rows.append({
            "path": _rel(path, root),
            "bytes": size,
            "lines": text.count("\n") + (0 if text.endswith("\n") else 1),
            "tokens": tokens,
        })
    return {
        "schema": MEASURE_SCHEMA,
        "tokenizer": label,
        "totalBytes": total_bytes,
        "totalTokens": total_tokens,
        "files": rows,
    }


# --------------------------------------------------------------------------
# CLI


def _print(value, compact: bool = False) -> None:
    if compact:
        print(_json(value))
    else:
        print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p_inv = sub.add_parser("inventory", help="tracked file counts and sizes")
    p_inv.add_argument("--json", action="store_true", help="one-line JSON")

    p_runs = sub.add_parser("runs", help="benchmark/archive run records")
    p_runs.add_argument("--all", action="store_true", help="include every run")
    p_runs.add_argument("--limit", type=int, default=20)
    p_runs.add_argument("--area")
    p_runs.add_argument("--json", action="store_true")

    p_conf = sub.add_parser("conformance", help="conformance run metadata")
    p_conf.add_argument("--all", action="store_true")
    p_conf.add_argument("--limit", type=int, default=20)
    p_conf.add_argument("--min-total", type=int, default=100,
                        help="hide smoke runs smaller than N tests (default 100)")
    p_conf.add_argument("--json", action="store_true")

    p_docs = sub.add_parser("docs", help="Markdown index")
    p_docs.add_argument("--limit", type=int, default=40)
    p_docs.add_argument("--json", action="store_true")

    p_brief = sub.add_parser("brief", help="bounded repository brief")
    p_brief.add_argument("--budget", type=int, default=2000, help="estimated tokens")
    p_brief.add_argument("--json", action="store_true")

    p_measure = sub.add_parser("measure", help="bytes/lines/token counts")
    p_measure.add_argument("paths", nargs="+")
    p_measure.add_argument("--json", action="store_true")

    p_index = sub.add_parser("index", help="write derived JSONL indexes")
    p_index.add_argument("--json", action="store_true")

    args = parser.parse_args(argv)
    root = ROOT
    if args.command == "inventory":
        result = inventory(root)
    elif args.command == "runs":
        records = _runs(root)
        if args.area:
            records = [row for row in records if row["area"] == args.area]
        result = records if args.all else records[: max(0, args.limit)]
    elif args.command == "conformance":
        records = _conformance(root)
        result = records if args.all else latest_by_suite(
            records, 0 if args.all else args.min_total
        )[: max(0, args.limit)]
    elif args.command == "docs":
        result = _docs(root)[: max(0, args.limit)]
    elif args.command == "brief":
        result = brief(root, args.budget)
    elif args.command == "measure":
        result = measure(args.paths, root)
    elif args.command == "index":
        result = write_indexes(root)
        result = {"schema": "nativax.context.index.v1", "written": result}
    else:  # pragma: no cover - argparse enforces the choices
        return 64
    _print(result, compact=args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())

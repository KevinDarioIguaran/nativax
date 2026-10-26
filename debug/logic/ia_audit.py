#!/usr/bin/env python3
"""Reproducible measurements for the information-architecture audit.

    python3 debug/logic/ia_audit.py
    python3 debug/logic/ia_audit.py --out progress/reports/information-architecture-latest.json

The report reads canonical files only. "Before" values come from the current
git revision for tracked files and from the latest legacy conformance summary
for the run-format comparison; nothing is invented. Token counts use
``context.count_tokens`` and report whether they are exact or estimated.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

_LOGIC = Path(__file__).resolve().parent
if str(_LOGIC) not in sys.path:
    sys.path.insert(0, str(_LOGIC))

import context  # noqa: E402

ROOT = _LOGIC.parent.parent


def _bytes(path: Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


def _stats(path: Path) -> dict:
    try:
        text = path.read_text()
    except OSError:
        return {"path": context._rel(path, ROOT), "bytes": 0, "tokens": 0, "lines": 0}
    tokens, _ = context.count_tokens(text)
    return {
        "path": context._rel(path, ROOT),
        "bytes": len(text.encode("utf-8")),
        "tokens": tokens,
        "lines": text.count("\n") + (0 if text.endswith("\n") else 1),
    }


def _text_stats(text: str) -> dict:
    tokens, _ = context.count_tokens(text)
    return {
        "bytes": len(text.encode("utf-8")),
        "tokens": tokens,
        "lines": text.count("\n") + (0 if text.endswith("\n") else 1),
    }


def _git_text(root: Path, path: str) -> str | None:
    try:
        out = subprocess.run(
            ["git", "show", f"HEAD:{path}"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout if out.returncode == 0 else None


def _summary_preview(path: Path) -> dict:
    """What the same run's summary would cost as metadata-only."""
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    total = data.get("total")
    if not isinstance(total, int):
        total = sum(v for v in (data.get("counts") or {}).values() if isinstance(v, int))
    meta = {key: value for key, value in data.items() if key != "results"}
    meta["total"] = total
    meta["resultsFile"] = path.name.replace(".summary.json", ".jsonl")
    text = json.dumps(meta, ensure_ascii=False, indent=2)
    return {"bytes": len(text.encode("utf-8")), **_text_stats(text)}


def _conformance_compare(root: Path) -> dict:
    results = root / "debug" / "artifacts" / "conformance" / "results"
    summaries = sorted(results.glob("*.summary.json"))
    legacy = []
    compact = []
    for path in summaries:
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        (legacy if isinstance(data.get("results"), list) else compact).append((path, data))
    url_legacy = max(
        (item for item in legacy if (item[1].get("command") or "").startswith("run_url")),
        key=lambda item: item[1].get("startedAt") or "",
        default=None,
    )
    url_compact = max(
        (item for item in compact if (item[1].get("command") or "").startswith("run_url")),
        key=lambda item: item[1].get("startedAt") or "",
        default=None,
    )
    out: dict = {
        "legacyRuns": len(legacy),
        "compactRuns": len(compact),
    }
    if url_legacy and url_compact:
        old_summary = url_legacy[0]
        new_summary = url_compact[0]
        old_jsonl = old_summary.with_name(
            old_summary.name.replace(".summary.json", ".jsonl")
        )
        new_jsonl = new_summary.with_name(
            new_summary.name.replace(".summary.json", ".jsonl")
        )
        old = _stats(old_summary)
        new = _stats(new_summary)
        old_pair = old["bytes"] + _bytes(old_jsonl)
        new_pair = new["bytes"] + _bytes(new_jsonl)
        out["url"] = {
            "legacy": {**old, "jsonlBytes": _bytes(old_jsonl), "pairBytes": old_pair},
            "compact": {**new, "jsonlBytes": _bytes(new_jsonl), "pairBytes": new_pair},
            "summarySavingsBytes": old["bytes"] - new["bytes"],
            "summarySavingsPct": round(
                (old["bytes"] - new["bytes"]) / old["bytes"] * 100, 1
            ) if old["bytes"] else 0,
            "pairSavingsPct": round((old_pair - new_pair) / old_pair * 100, 1)
            if old_pair else 0,
        }
    if legacy:
        largest = max(legacy, key=lambda item: _bytes(item[0]))
        preview = _summary_preview(largest[0])
        out["largestLegacyPreview"] = {
            "source": context._rel(largest[0], root),
            "currentBytes": _bytes(largest[0]),
            "compactBytes": preview.get("bytes"),
            "summarySavingsPct": round(
                (_bytes(largest[0]) - preview.get("bytes", 0)) / _bytes(largest[0]) * 100, 1
            ) if _bytes(largest[0]) else 0,
            "note": "historical file is unchanged; this is what a new run of the same suite writes",
        }
    return out


def _artifact_sizes(root: Path) -> dict:
    artifacts = root / "debug" / "artifacts"
    out = {}
    if not artifacts.is_dir():
        return out
    for child in sorted(artifacts.iterdir()):
        if not child.is_dir():
            continue
        total = 0
        for path in child.rglob("*"):
            if path.is_file():
                total += _bytes(path)
        out[child.name] = total
    return out


def audit(root: Path | str = ROOT) -> dict:
    root = Path(root)
    started = time.perf_counter()
    index_written = context.write_indexes(root)
    index_ms = round((time.perf_counter() - started) * 1000, 1)
    brief = context.brief(root, budget=2000)
    index_sizes = {
        name: _bytes(root / "debug" / "artifacts" / "index" / f"{name}.jsonl")
        for name in ("runs", "conformance", "docs")
    }
    history_path = root / "progress" / "history" / "status-2026-10-25.md"
    old_status = history_path.read_text() if history_path.is_file() else _git_text(root, "progress/status.md")
    old_agents = _git_text(root, ".agents/README.md")
    current_status = _stats(root / "progress/status.md")
    current_agents = _stats(root / ".agents" / "README.md")
    docs = context.scan_docs(root)
    return {
        "schema": "nativax.ia.audit.v1",
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "tokenizer": context.count_tokens("x")[1],
        "repo": context.inventory(root),
        "trackedDocs": {
            "files": len(docs),
            "bytes": sum(row["bytes"] for row in docs),
            "indexBytes": index_sizes["docs"],
        },
        "artifacts": _artifact_sizes(root),
        "context": {
            "indexWritten": index_written,
            "indexBytes": index_sizes,
            "indexBuildMs": index_ms,
            "brief": {
                "bytes": len(context._json(brief).encode("utf-8")),
                "estimatedTokens": brief["estimatedTokens"],
                "budget": 2000,
                "truncated": brief["truncated"],
            },
        },
        "conformance": _conformance_compare(root),
        "agents": {
            "before": {"path": ".agents/README.md", **_text_stats(old_agents or "")},
            "after": current_agents,
            "savingsPct": round(
                (len((old_agents or "").encode()) - current_agents["bytes"]) /
                len((old_agents or "").encode()) * 100, 1
            ) if old_agents else None,
        },
        "status": {
            "before": {"path": "progress/status.md (HEAD)", **_text_stats(old_status or "")},
            "after": current_status,
            "savingsPct": round(
                (len((old_status or "").encode()) - current_status["bytes"]) /
                len((old_status or "").encode()) * 100, 1
            ) if old_status else None,
            "history": _stats(history_path),
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default="progress/reports/information-architecture-latest.json")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    report = audit(ROOT)
    out = Path(args.out)
    if not out.is_absolute():
        out = ROOT / out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    if args.json:
        print(context._json(report))
    else:
        print(f"wrote {out.relative_to(ROOT)}")
        print(f"tracked: {report['repo']['files']} files, {report['repo']['bytes']} bytes")
        print(f"context index: {sum(report['context']['indexBytes'].values())} bytes "
              f"({report['context']['indexBuildMs']} ms)")
        print(f"brief: {report['context']['brief']['estimatedTokens']} estimated tokens")
        print(f"status: {report['status']['before']['bytes']} -> "
              f"{report['status']['after']['bytes']} bytes "
              f"({report['status']['savingsPct']}% saved)")
        print(f"agents: {report['agents']['before']['bytes']} -> "
              f"{report['agents']['after']['bytes']} bytes "
              f"({report['agents']['savingsPct']}% saved)")
        url = report["conformance"].get("url")
        if url:
            print(f"conformance summary: {url['legacy']['bytes']} -> "
                  f"{url['compact']['bytes']} bytes "
                  f"({url['summarySavingsPct']}% summary, "
                  f"{url['pairSavingsPct']}% with JSONL)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

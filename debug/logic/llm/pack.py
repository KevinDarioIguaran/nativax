#!/usr/bin/env python3
"""Builds the LLM debug pack: pre-analyzed, ranked, minified evidence.

    python3 debug/run.py llm                  # all areas -> debug/artifacts/llm/
    python3 debug/run.py llm --budget 1500    # index.json budget (estimated tokens)
    python3 debug/run.py llm --area visual --visual path/to/results.json

Output (minified JSON, for models only; humans use the UI):

    debug/artifacts/llm/legend.json     meaning of every short key (read once)
    debug/artifacts/llm/index.json      area summaries, patterns and ranked items
                                        [id,priority,area,trend,headline,file,est.tokens],
                                        changes vs the previous pack
    debug/artifacts/llm/items/<id>.json one problem with every measured detail

A model reads index.json first and opens only the item files it needs.
Nothing here calls a model; every value comes from engine evidence whose
path is in the item's "src".
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from llm import areas as A  # noqa: E402
from llm import patterns as PAT  # noqa: E402
from llm.core import PRIORITY_RULES, ROOT, dumps, load_json, tokens, token_method  # noqa: E402

OUT = ROOT / "debug" / "artifacts" / "llm"
SCHEMA = "nativax.llm.pack.v1"
ITEM_MAX = 1500      # estimated tokens per item file


def _git():
    def run(*a):
        try:
            return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, timeout=20).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return ""
    return {"commit": run("rev-parse", "--short", "HEAD") or None,
            "dirty": bool(run("status", "--porcelain", "--", "packages", "debug", "examples"))}


def _shrink(doc: dict, limit: int) -> dict:
    """Halves the longest list in the document until it fits, recording how
    many entries were dropped under "o" (never silently)."""
    dropped = 0
    while tokens(doc) > limit:
        lists = [(len(v), k) for k, v in doc.items() if isinstance(v, list) and len(v) > 1]
        if not lists:
            break
        _, key = max(lists)
        keep = len(doc[key]) // 2
        dropped += len(doc[key]) - keep
        doc[key] = doc[key][:keep]
    if dropped:
        doc["o"] = (doc.get("o") or 0) + dropped
    return doc


def _changes(prev: set, cur: set) -> dict:
    """New/resolved item ids vs the previous pack; ids only when few, so a
    first build or a large shift costs a handful of tokens."""
    if not prev:
        return {"first_pack": True}
    new, gone = sorted(cur - prev), sorted(prev - cur)
    out = {"new": len(new), "resolved": len(gone)}
    if len(new) <= 30:
        out["new_ids"] = new
    if len(gone) <= 30:
        out["resolved_ids"] = gone
    return out


def build(selected=None, *, budget=2500, out: Path = OUT, overrides=None) -> dict:
    overrides = overrides or {}
    out.mkdir(parents=True, exist_ok=True)
    (out / "items").mkdir(exist_ok=True)
    # Every item of the previous pack (not only those listed in its index).
    prev_ids = {p.stem for p in (out / "items").glob("*.json")} if (out / "index.json").exists() else set()
    summaries, items = {}, []
    for name, fn in A.DIGESTERS.items():
        if selected and name not in selected:
            continue
        arg = overrides.get(name)
        summary, found = fn(Path(arg)) if arg else fn()
        summaries[name] = summary
        items += found
    # Patterns first: one line that explains many items saves the most reading.
    items = PAT.build(items) + items
    items.sort(key=lambda i: (i.priority, 0 if i.area == "pattern" else 1, -i.impact, i.area, i.id))
    written = set()
    rows = []
    for item in items:
        doc = {"id": item.id, "a": item.area, "p": item.priority, "t": item.trend, "h": item.headline,
               "src": item.sources, "cmd": item.commands, **item.detail}
        doc = {k: v for k, v in doc.items() if v not in (None, [], {})}
        doc = _shrink(doc, ITEM_MAX)
        name = f"{item.id}.json"
        text = dumps(doc)
        tmp = out / "items" / f".{name}.tmp"
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, out / "items" / name)
        written.add(name)
        headline = " ".join(item.headline.split())[:170]
        rows.append([item.id, item.priority, item.area, item.trend, headline, tokens(text)])
    for other in sorted((out / "items").glob("*.json")):
        if other.name in written:
            continue
        doc = load_json(other) or {}
        area = doc.get("a")
        own = area in (selected or A.DIGESTERS) or (area == "pattern" and not selected)
        if own:
            other.unlink()                      # stale item of an area rebuilt now
        else:                                   # partial build: other areas stay as they were
            rows.append([doc.get("id"), doc.get("p"), area, doc.get("t"), doc.get("h"), tokens(other.read_text())])
    if selected:
        prev_index = load_json(out / "index.json") or {}
        summaries = {**(prev_index.get("areas") or {}), **summaries}
        rows.sort(key=lambda r: (r[1] or 9, 0 if r[2] == "pattern" else 1, r[2] or "", r[0] or ""))
    index = {
        "schema": SCHEMA,
        "gen": datetime.now().astimezone().isoformat(timespec="seconds"),
        **_git(),
        "tok": token_method(),
        "use": "read this index; open items/<id>.json only for items you act on; src has the raw evidence",
        "prio": PRIORITY_RULES,
        "legend": "legend.json",
        "areas": summaries,
        "counts": {f"p{p}": sum(1 for r in rows if r[1] == p) for p in (1, 2, 3)},
        "changes": _changes(prev_ids, {r[0] for r in rows}),
        "items": [],
        "o": 0,
    }
    base_cost = tokens(index)
    kept, used = [], base_cost
    for row in rows:
        cost = tokens(row) + 1
        if used + cost > budget:
            break
        kept.append(row)
        used += cost
    index["items"] = kept
    index["o"] = len(rows) - len(kept)
    if index["o"]:
        index["more"] = "items beyond the budget are still in items/; rerun with a larger --budget to list them"
    legend = dumps({"schema": SCHEMA + ".legend", "keys": A.LEGEND, "prio": PRIORITY_RULES,
                    "item_row": ["id", "priority", "area", "trend", "headline", "estimated tokens of items/<id>.json"]})
    (out / "legend.json").write_text(legend, encoding="utf-8")
    text = dumps(index)
    tmp = out / ".index.json.tmp"
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, out / "index.json")
    return {"index": str(out / "index.json"), "items": len(rows), "listed": len(kept),
            "index_tokens": tokens(text), "item_tokens_max": max((r[5] for r in rows), default=0),
            "item_tokens_total": sum(r[5] for r in rows), "method": token_method()}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--area", action="append", choices=sorted(A.DIGESTERS), help="limit to areas (repeatable)")
    p.add_argument("--budget", type=int, default=2500, help="estimated tokens for index.json")
    p.add_argument("--out", default=str(OUT))
    for name in ("visual", "perf"):
        p.add_argument(f"--{name}", help=f"explicit {name} results.json instead of the automatic choice")
    p.add_argument("--audit", help="explicit audit run directory")
    args = p.parse_args(argv)
    overrides = {k: getattr(args, k) for k in ("visual", "perf", "audit") if getattr(args, k)}
    result = build(args.area, budget=args.budget, out=Path(args.out), overrides=overrides)
    print(dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())

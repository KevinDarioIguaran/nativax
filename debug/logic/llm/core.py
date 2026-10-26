"""Core of the LLM debug pack: items, budgets, grouping and code references.

Everything here is deterministic. The pack pre-digests evidence so a model
reads conclusions with their numbers instead of raw files:

  * an Item is one problem with a stable id, a priority, a one-line headline
    for the index and a dense detail object loaded only on demand;
  * pack files are minified JSON (no indentation, no spaces, short keys
    explained once in index.json "legend"): they are read by models, not
    people. Human-readable reports stay in the UI;
  * token cost is estimated with debug/logic/context.count_tokens (tiktoken
    when installed, otherwise ceil(bytes/4), labelled as an estimate);
  * every number states its source file so it can be checked.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

_LOGIC = Path(__file__).resolve().parents[1]
if str(_LOGIC) not in sys.path:
    sys.path.insert(0, str(_LOGIC))

import context  # noqa: E402  (token estimator shared with the context index)

ROOT = _LOGIC.parents[1]

PRIORITY_RULES = {
    1: "crash, critical/high security failure, proven leak, INVALID run, or a regression beyond noise",
    2: "failure against the reference or target (visual FAIL, perf FAIL, failing conformance group)",
    3: "warning or a known persistent gap",
}


@dataclass
class Item:
    id: str
    area: str
    priority: int
    headline: str                     # one line for INDEX.md, numbers included
    detail: dict = field(default_factory=dict)   # dense facts, loaded on demand
    impact: float = 0.0               # sort key inside a priority (bigger first)
    sources: list = field(default_factory=list)
    commands: list = field(default_factory=list)
    trend: str | None = None          # "regressed", "improved", "new", "unchanged", None
    data: dict = field(default_factory=dict)   # compact machine-readable facts

    def record(self) -> dict:
        return {"id": self.id, "area": self.area, "p": self.priority, "h": self.headline,
                "trend": self.trend, "data": self.data, "src": self.sources, "cmd": self.commands}


def dumps(value) -> str:
    """Minified JSON: the smallest faithful encoding for a model to read."""
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)


def tokens(value) -> int:
    text = value if isinstance(value, str) else dumps(value)
    return context.count_tokens(text)[0]


def r1(v, digits=1):
    """Rounds floats so long decimals do not cost tokens; keeps None."""
    if isinstance(v, float):
        return round(v, digits)
    return v


def compact(d: dict) -> dict:
    """Drops None, empty strings and empty collections (absent = not measured,
    stated once in the legend)."""
    return {k: v for k, v in d.items() if v is not None and v != "" and v != [] and v != {}}


def token_method() -> str:
    return context.count_tokens("x")[1]


def stable_id(prefix: str, key: str, length: int = 0) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", key).strip("-")
    if length and len(slug) > length:
        slug = slug[:length] + "-" + hashlib.sha1(key.encode()).hexdigest()[:6]
    return f"{prefix}-{slug}"


def rel(path) -> str:
    try:
        return str(Path(path).resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def fit(rows: list, budget: int) -> tuple[list, int]:
    """Keeps rows in order until the estimated budget is used. Returns the
    kept rows and how many were left out (reported, never silent)."""
    out, used = [], 0
    for i, row in enumerate(rows):
        cost = tokens(row) + 1
        if used + cost > budget:
            return out, len(rows) - i
        out.append(row)
        used += cost
    return out, 0


_QUOTED = re.compile(r'"[^"]*"|\'[^\']*\'|`[^`]*`')
_NUMBER = re.compile(r"\b\d+(?:\.\d+)?\b")
# Unquoted values after comparison words ("expected foo.com, got %20foo.com").
_VALUE = re.compile(r"\b(expected|got|actual|received|but got|but was|instead of)\b:?\s*[^,;)]+", re.I)
_HEX = re.compile(r"#[0-9a-f]{5,}\b|0x[0-9a-f]+")


def normalize_reason(text: str) -> str:
    """Failure messages with literals replaced, so equal causes group."""
    t = str(text or "").strip().split("\n")[0]
    t = _QUOTED.sub("‹s›", t)
    t = _VALUE.sub(lambda m: f"{m.group(1)} ‹v›", t)
    t = _HEX.sub("‹h›", t)
    t = _NUMBER.sub("‹n›", t)
    return re.sub(r"\s+", " ", t)[:160]


@lru_cache(maxsize=1024)
def code_refs(term: str, paths: tuple[str, ...], limit: int = 4) -> tuple[str, ...]:
    """`git grep -n -F` hits as 'file:line' strings (search hits, not causes)."""
    existing = [p for p in paths if (ROOT / p).exists()]
    if not term or not existing:
        return ()
    try:
        out = subprocess.run(["git", "grep", "-n", "-F", term, "--", *existing], cwd=ROOT,
                             capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ()
    hits = []
    for line in out.splitlines()[:limit]:
        file, ln, _ = line.split(":", 2)
        hits.append(f"{file}:{ln}")
    return tuple(hits)


def load_json(path: Path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def history_runs(area: str) -> list[dict]:
    """Recorded runs of an area (debug/logic/history), oldest first."""
    sys.path.insert(0, str(_LOGIC / "history"))
    try:
        import history  # noqa: E402
        return history.list_runs(area)
    except Exception:  # noqa: BLE001 - no history is a valid state
        return []


def previous_comparable(area: str, count_key: str, count) -> dict | None:
    """The newest recorded run before the latest that measured the same
    number of items (the same rule as the dashboard's history page)."""
    runs = [r for r in history_runs(area) if (r.get("summary") or {}).get(count_key) == count]
    if len(runs) < 2:
        return None
    data = load_json(Path(runs[-2]["file"]))
    return {"run": runs[-2], "data": data} if data else None

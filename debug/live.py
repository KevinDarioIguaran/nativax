#!/usr/bin/env python3
"""Live progress snapshots shared by the lab runners and the dashboard.

Both ``run_lab.py`` and ``chrome_compare.py`` can write a small JSON snapshot
with ``--progress PATH``.  The dashboard polls it to show what is happening
*while* the tests run: which case is executing, which section it belongs to,
and (for visual comparisons) which stage of the Chrome -> NativaX -> diff
pipeline has finished.

The file is written atomically so a reader never sees a half-written JSON.
Nothing here fabricates results: every event comes from a real case result or
a real render/compare step.
"""
from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any

MAX_EVENTS = 300


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _write_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
            fh.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


class Progress:
    """A single run's live state, persisted as JSON after every event."""

    def __init__(self, path: str | Path, kind: str, title: str,
                 *, total: int = 0, sections: dict[str, int] | None = None,
                 standards: dict[str, Any] | None = None,
                 command: str | None = None):
        self.path = Path(path)
        self.seq = 0
        self.data: dict[str, Any] = {
            "kind": kind,
            "title": title,
            "command": command or "",
            "pid": os.getpid(),
            "started_at": now(),
            "updated_at": now(),
            "running": True,
            "stage": "starting",
            "total": int(total),
            "done": 0,
            "pass": 0,
            "fail": 0,
            "blocked": 0,
            "error": 0,
            "warn": 0,
            "current": None,
            "case": None,
            "sections": {
                str(k): {"total": int(v), "done": 0, "pass": 0, "fail": 0,
                         "blocked": 0, "error": 0}
                for k, v in (sections or {}).items()
            },
            "events": [],
            "summary": None,
            "standards": standards or {},
        }
        self.write()

    # -- persistence -----------------------------------------------------
    def write(self) -> None:
        self.data["updated_at"] = now()
        _write_atomic(self.path, self.data)

    def update(self, **fields: Any) -> None:
        self.data.update(fields)
        self.write()

    # -- events ----------------------------------------------------------
    def event(self, kind: str, **fields: Any) -> dict[str, Any]:
        self.seq += 1
        event = {"seq": self.seq, "at": now(), "type": kind, **fields}
        events = self.data.setdefault("events", [])
        events.append(event)
        if len(events) > MAX_EVENTS:
            del events[:-MAX_EVENTS]
        self.write()
        return event

    # -- convenience -----------------------------------------------------
    def set_sections(self, totals: dict[str, int]) -> None:
        self.data["sections"] = {
            str(k): {"total": int(v), "done": 0, "pass": 0, "fail": 0,
                     "blocked": 0, "error": 0, "warn": 0}
            for k, v in totals.items()
        }
        self.data["total"] = int(sum(totals.values()))
        self.write()

    def section_started(self, section: int, total: int) -> None:
        row = self.data["sections"].setdefault(
            str(section), {"total": total, "done": 0, "pass": 0, "fail": 0,
                           "blocked": 0, "error": 0, "warn": 0})
        row["total"] = total
        self.data.update(stage="section", current=None)
        self.event("section_start", section=section, total=total)

    def case_started(self, cid: str, name: str, section: int,
                     index: int, total: int) -> None:
        self.data["current"] = {
            "id": cid, "name": name, "section": section,
            "index": index, "total": total, "stage": "running",
        }
        self.data["stage"] = "case"
        self.event("case_start", id=cid, name=name, section=section,
                   index=index, total=total)

    def case_done(self, result: dict[str, Any]) -> None:
        status = result.get("status", "error")
        if status not in ("pass", "fail", "blocked", "error", "warn", "skip"):
            status = "error"
        self.data[status] = int(self.data.get(status, 0)) + 1
        self.data["done"] = int(self.data.get("done", 0)) + 1
        section = str(result.get("section", ""))
        row = self.data["sections"].setdefault(
            section, {"total": 0, "done": 0, "pass": 0, "fail": 0,
                      "blocked": 0, "error": 0, "warn": 0})
        row["total"] = max(int(row.get("total", 0)), int(row.get("done", 0)) + 1)
        row["done"] = int(row.get("done", 0)) + 1
        row[status] = int(row.get(status, 0)) + 1
        cid = result.get("id", "")
        self.data["current"] = {
            "id": cid, "name": result.get("name", ""),
            "section": result.get("section"), "status": status,
            "message": result.get("message", ""),
            "duration_ms": result.get("duration_ms", 0),
            "stage": "done",
        }
        self.event("case_done", id=cid, section=result.get("section"),
                   status=status, message=result.get("message", "")[:400],
                   duration_ms=result.get("duration_ms", 0))

    def section_done(self, section: int, summary: dict[str, Any]) -> None:
        row = self.data["sections"].setdefault(str(section), {})
        row.update({"done": summary.get("total", row.get("done", 0)),
                    "pass": summary.get("pass", 0),
                    "fail": summary.get("fail", 0),
                    "blocked": summary.get("blocked", 0),
                    "error": summary.get("error", 0)})
        self.event("section_done", section=section, **{
            k: summary.get(k, 0) for k in ("total", "pass", "fail", "blocked", "error")
        })

    def stage(self, stage: str, **fields: Any) -> None:
        self.data["stage"] = stage
        if fields:
            self.event("stage", stage=stage, **fields)

    def finish(self, summary: dict[str, Any], *, exit_code: int = 0) -> None:
        self.data["running"] = False
        self.data["stage"] = "done"
        self.data["current"] = None
        self.data["summary"] = summary
        self.data["exit_code"] = exit_code
        self.data["elapsed_seconds"] = summary.get("elapsed_seconds")
        self.event("finish", exit_code=exit_code, **{
            k: summary.get(k) for k in ("total", "pass", "fail", "blocked",
                                        "error", "warn", "comparisons")
            if k in summary
        })

    def fail(self, message: str) -> None:
        self.data["running"] = False
        self.data["stage"] = "error"
        self.data["error_message"] = message
        self.event("error", message=message)

"""Application state shared by pages: the report catalog, the open report
and user preferences. It calls services only; it computes nothing itself."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
for p in (ROOT, ROOT / "debug" / "logic"):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

import catalog  # noqa: E402  (debug/logic)

PREFS = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "nativax-debug-app.json"


class AppState:
    def __init__(self):
        self.refs: list[catalog.ReportRef] = []
        self.current: catalog.ReportRef | None = None
        self.listeners = []
        self.prefs = self._load_prefs()

    def _load_prefs(self) -> dict:
        try:
            return json.loads(PREFS.read_text())
        except (OSError, ValueError):
            return {}

    def save_prefs(self):
        try:
            PREFS.parent.mkdir(parents=True, exist_ok=True)
            PREFS.write_text(json.dumps(self.prefs, indent=2))
        except OSError:
            pass

    def reload(self):
        self.refs = catalog.discover()
        if self.current is not None:
            self.current = next((r for r in self.refs if r.path == self.current.path), None)

    def find(self, path: str):
        return next((r for r in self.refs if r.path == path), None)

    def open(self, ref):
        self.current = ref
        self.prefs["last_report"] = ref.path if ref else None
        self.save_prefs()

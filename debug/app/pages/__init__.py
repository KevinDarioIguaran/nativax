"""Page registry. Each page module exposes `Page(frame, app)` with `refresh()`."""
from __future__ import annotations

import importlib

MODULES = {
    "overview": "debug.app.pages.overview",
    "explorer": "debug.app.pages.explorer",
    "report": "debug.app.pages.report",
    "compare": "debug.app.pages.compare",
    "run": "debug.app.pages.run",
}


def create(key, frame, app):
    return importlib.import_module(MODULES[key]).Page(frame, app)

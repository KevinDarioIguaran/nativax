#!/usr/bin/env python3
"""Open the NativaX Debug Lab dashboard in the default browser."""
from __future__ import annotations

import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DASHBOARD = ROOT / "debug" / "dashboard.html"

if __name__ == "__main__":
    if not DASHBOARD.exists():
        print(f"dashboard not found: {DASHBOARD}", file=__import__("sys").stderr)
        raise SystemExit(1)
    webbrowser.open(DASHBOARD.as_uri())
    print(f"opened {DASHBOARD}")
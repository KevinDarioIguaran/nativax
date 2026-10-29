#!/usr/bin/env python3
"""Open the NativaX dashboard in a dedicated application window."""
from __future__ import annotations

import shutil
import subprocess
import sys
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEBUG = ROOT / "debug"
DASHBOARD = DEBUG / "dashboard.html"
DATA_SCRIPT = DEBUG / "tools" / "build_dashboard_data.py"

def ensure_data():
    if DATA_SCRIPT.exists():
        subprocess.run([sys.executable, str(DATA_SCRIPT)], cwd=ROOT, stdout=subprocess.DEVNULL)


def try_webview() -> bool:
    try:
        import webview  # type: ignore
    except Exception:
        return False
    if not DASHBOARD.exists():
        return False
    webview.create_window("NativaX Debug Lab", DASHBOARD.as_uri(), width=1280, height=820)
    webview.start()
    return True


def try_app_window() -> bool:
    if not DASHBOARD.exists():
        return False
    uri = DASHBOARD.as_uri()
    # Chromium/Edge/Chrome support an app-like window.
    for binary in ("google-chrome", "google-chrome-stable", "chromium",
                   "chromium-browser", "msedge", "chrome"):
        path = shutil.which(binary)
        if path:
            subprocess.Popen([path, f"--app={uri}", "--window-size=1280,820"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
    # Firefox opens a normal new window.
    for binary in ("firefox", "firefox-esr"):
        path = shutil.which(binary)
        if path:
            subprocess.Popen([path, "--new-window", str(DASHBOARD)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
    return False


def main() -> int:
    ensure_data()
    if try_webview():
        return 0
    if try_app_window():
        return 0
    if DASHBOARD.exists():
        webbrowser.open(DASHBOARD.as_uri())
        print(f"opened {DASHBOARD}")
        return 0
    print(f"dashboard not found: {DASHBOARD}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
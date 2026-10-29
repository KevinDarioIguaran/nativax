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
SERVER_SCRIPT = DEBUG / "tools" / "dashboard_server.py"


def ensure_data():
    if DATA_SCRIPT.exists():
        subprocess.run([sys.executable, str(DATA_SCRIPT)], cwd=ROOT, stdout=subprocess.DEVNULL)


def start_server():
    sys.path.insert(0, str(DEBUG / "tools"))
    import dashboard_server  # type: ignore
    return dashboard_server.start_server()


def try_webview(url: str) -> bool:
    try:
        import webview  # type: ignore
    except Exception:
        return False
    webview.create_window("NativaX Debug Lab", url, width=1380, height=900)
    webview.start()
    return True


def try_app_window(url: str) -> bool:
    for binary in ("google-chrome", "google-chrome-stable", "chromium",
                   "chromium-browser", "msedge", "chrome"):
        path = shutil.which(binary)
        if path:
            subprocess.Popen([path, f"--app={url}", "--window-size=1380,900"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
    for binary in ("firefox", "firefox-esr"):
        path = shutil.which(binary)
        if path:
            subprocess.Popen([path, "--new-window", url],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
    return False


def main() -> int:
    ensure_data()
    try:
        httpd, port, url = start_server()
    except Exception as exc:
        print(f"server failed: {exc}", file=sys.stderr)
        url = DASHBOARD.as_uri()
        httpd = None
    if try_webview(url):
        return 0
    if try_app_window(url):
        return 0
    webbrowser.open(url)
    print(f"opened {url}")
    if httpd is not None:
        try:
            while True:
                import time
                time.sleep(1)
        except KeyboardInterrupt:
            httpd.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

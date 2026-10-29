#!/usr/bin/env python3
"""Native (pywebview) GUI for the NativaX debug laboratory."""
from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEBUG = ROOT / "debug"
LAB = DEBUG / "lab"
RUNNER = LAB / "run_lab.py"
DATA_SCRIPT = DEBUG / "tools" / "build_dashboard_data.py"
DASHBOARD_HTML = DEBUG / "dashboard" / "index.html"


def run_build() -> None:
    subprocess.run([sys.executable, str(DATA_SCRIPT)], cwd=ROOT,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def load_data() -> dict:
    run_build()
    path = DEBUG / "dashboard" / "dashboard_data.js"
    text = path.read_text(encoding="utf-8")
    prefix = "window.DASHBOARD_DATA = "
    return json.loads(text[len(prefix):].rstrip().rstrip(";"))


class Api:
    def __init__(self):
        self.running = False
        self.log = []
        self.exit_code = None
        self.lock = threading.Lock()

    def run_tests(self, scope="all", section=1, responsive=False):
        with self.lock:
            if self.running:
                return {"started": False, "error": "already running"}
            self.running = True
            self.log = []
            self.exit_code = None
        cmd = [sys.executable, str(RUNNER)]
        if scope == "all":
            cmd.append("--all")
        else:
            cmd += ["--section", str(section)]
        if not responsive:
            cmd.append("--no-responsive")

        def worker():
            try:
                proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, bufsize=1)
                for line in proc.stdout:
                    with self.lock:
                        self.log.append(line.rstrip("\n"))
                        if len(self.log) > 2000:
                            self.log = self.log[-2000:]
                proc.wait()
                with self.lock:
                    self.exit_code = proc.returncode
                    self.log.append(f"[exit {proc.returncode}]")
            except Exception as exc:
                with self.lock:
                    self.exit_code = -1
                    self.log.append(f"ERROR: {exc}")
            finally:
                with self.lock:
                    self.running = False
                run_build()

        threading.Thread(target=worker, daemon=True).start()
        return {"started": True}

    def get_status(self):
        with self.lock:
            return {
                "running": self.running,
                "exit_code": self.exit_code,
                "log": list(self.log[-80:]),
            }

    def reload_data(self):
        return load_data()

    def get_artifacts(self):
        out = []
        for p in sorted(DEBUG.rglob("*")):
            if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg"}:
                out.append({"path": str(p.relative_to(DEBUG)), "size": p.stat().st_size,
                            "url": p.as_uri()})
        return out[:200]


def _system_python() -> str | None:
    for cand in ("/usr/bin/python3", "/usr/bin/python3.12", "/usr/bin/python3.11"):
        if Path(cand).exists():
            return cand
    return None


def _ensure_webview():
    try:
        import webview  # type: ignore
        return webview
    except Exception:
        pass
    sp = _system_python()
    if sp and sp != sys.executable:
        # Re-exec with the system interpreter, which has GTK bindings.
        os.execv(sp, [sp, str(Path(__file__).resolve())] + sys.argv[1:])
    # Try to install pywebview into the current interpreter.
    try:
        subprocess.run([sys.executable, "-m", "pip", "install", "pywebview",
                        "--break-system-packages"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import webview  # type: ignore
        return webview
    except Exception:
        return None


def main() -> int:
    run_build()
    webview = _ensure_webview()

    if webview is not None:
        api = Api()
        webview.create_window("NativaX Debug Lab", DASHBOARD_HTML.as_uri(),
                              js_api=api, width=1380, height=900)
        webview.start()
        return 0

    # Fallback: open the static dashboard in the default browser.
    webbrowser.open(DASHBOARD_HTML.as_uri())
    print(f"opened {DASHBOARD_HTML} (read-only; install pywebview for interactive mode)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

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
VISUAL_RUNNER = DEBUG / "judges" / "visual" / "chrome_compare.py"
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

    def _start(self, cmd: list[str]) -> dict:
        with self.lock:
            if self.running:
                return {"started": False, "error": "already running"}
            self.running = True
            self.log = []
            self.exit_code = None

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

    def run_tests(self, scope="all", section=1, responsive=False):
        cmd = [sys.executable, str(RUNNER)]
        if scope == "all":
            cmd.append("--all")
        else:
            cmd += ["--section", str(section)]
        if not responsive:
            cmd.append("--no-responsive")
        return self._start(cmd)

    def run_visual(self, scope="case", case="", section=1, widths="1024"):
        """Render Chrome + NativaX and store the comparison report."""
        cmd = [_venv_python(), str(VISUAL_RUNNER), "--widths", widths]
        if scope == "all":
            cmd.append("--all")
        elif scope == "section":
            cmd += ["--section", str(section)]
        elif case:
            cmd += ["--case", case]
        else:
            return {"started": False, "error": "no case selected"}
        return self._start(cmd)

    def get_status(self):
        with self.lock:
            return {
                "running": self.running,
                "exit_code": self.exit_code,
                "log": list(self.log[-80:]),
            }

    def reload_data(self):
        return load_data()

    def get_latest_report(self):
        p = DEBUG / "reports" / "lab" / "latest.json"
        if not p.exists():
            return None
        try:
            return json.loads(p.read_text())
        except Exception:
            return None

    def get_section_reports(self):
        out = []
        base = DEBUG / "reports" / "lab"
        for p in sorted(base.glob("section-*.json")):
            try:
                d = json.loads(p.read_text())
                out.append({"file": p.name, "label": d.get("label"), "summary": d.get("summary", {})})
            except Exception:
                continue
        return out

    def get_history_index(self):
        p = DEBUG / "history" / "index.json"
        if not p.exists():
            return []
        try:
            return json.loads(p.read_text())
        except Exception:
            return []

    def get_history_run(self, path):
        p = DEBUG / path
        if not p.exists() or not p.is_file():
            return None
        try:
            return json.loads(p.read_text())
        except Exception:
            return None

    def get_smoke_summary(self):
        p = DEBUG / "artifacts" / "bootstrap-smoke" / "summary.json"
        if not p.exists():
            return None
        try:
            return json.loads(p.read_text())
        except Exception:
            return None

    def get_artifacts(self):
        out = []
        for root in (DEBUG / "artifacts", DEBUG / "tests" / "goldens"):
            if not root.exists():
                continue
            for p in sorted(root.rglob("*")):
                if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg"}:
                    out.append({"path": str(p.relative_to(DEBUG)),
                                "size": p.stat().st_size, "url": p.as_uri()})
        return out[:600]


def _venv_python() -> str:
    """Interpreter that has numpy/pillow/playwright for visual comparisons."""
    py = DEBUG / ".venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    return str(py) if py.exists() else sys.executable


def _system_python() -> str | None:
    for cand in ("/usr/bin/python3", "/usr/bin/python3.12", "/usr/bin/python3.11"):
        if Path(cand).exists():
            return cand
    return None


def _has_gui_backend(python: str | None = None) -> bool:
    """True when GTK/WebKit or Qt is importable (pywebview needs one)."""
    probe = (
        "import gi\n"
        "for v in ('4.1', '4.0'):\n"
        "    try:\n"
        "        gi.require_version('WebKit2', v); break\n"
        "    except ValueError: pass\n"
        "gi.require_version('Gtk', '3.0')\n"
        "from gi.repository import Gtk, WebKit2\n"
    )
    cmd = [python or sys.executable, "-c", probe]
    if subprocess.run(cmd, stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode == 0:
        return True
    qt = subprocess.run(
        [python or sys.executable, "-c", "import qtpy"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return qt.returncode == 0


def _ensure_webview():
    # pywebview itself imports without a GUI backend, but webview.start()
    # then crashes. Check the backend too, and use the system interpreter
    # when the venv was built without Python 3 GI bindings.
    try:
        import webview  # type: ignore
    except Exception:
        webview = None
    if webview is not None and _has_gui_backend():
        return webview

    sp = _system_python()
    same = sp and Path(sp).resolve() == Path(sys.executable).resolve()
    if sp and not same and _has_gui_backend(sp) \
            and os.environ.get("NATIVAX_GUI_REEXEC") != "1":
        os.environ["NATIVAX_GUI_REEXEC"] = "1"
        os.execv(sp, [sp, str(Path(__file__).resolve())] + sys.argv[1:])

    if not _has_gui_backend():
        return None

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

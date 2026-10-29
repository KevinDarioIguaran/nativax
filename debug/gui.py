#!/usr/bin/env python3
"""Native window for the NativaX debug laboratory.

There is no HTTP server and no port. The dashboard is a local HTML file opened
directly by the window; the Python side feeds it live data through the window
bridge:

* pywebview: ``window.pywebview.api`` (interactive).
* GTK/WebKit: a ``nativax://`` navigation hook plus a timer that pushes the
  live progress JSON into the page (interactive).
* A normal browser: static, read-only. It shows the data embedded in
  ``dashboard_data.js`` and the user reloads after a run.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
DEBUG = ROOT / "debug"
LAB = DEBUG / "lab"
RUNNER = LAB / "run_lab.py"
VISUAL_RUNNER = DEBUG / "judges" / "visual" / "chrome_compare.py"
DATA_SCRIPT = DEBUG / "tools" / "build_dashboard_data.py"
DASHBOARD_HTML = DEBUG / "dashboard" / "index.html"
PROGRESS = DEBUG / "reports" / "live.json"
DASHBOARD_DATA = DEBUG / "dashboard" / "dashboard_data.js"


def log(msg: str) -> None:
    """Progress/diagnostics always go to stderr, never silently swallowed."""
    print(f"[nativax-gui] {msg}", file=sys.stderr, flush=True)


def run_build() -> bool:
    r = subprocess.run([sys.executable, str(DATA_SCRIPT)], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode != 0:
        log(f"could not generate dashboard_data.js (exit {r.returncode})")
        detail = ((r.stdout or "") + (r.stderr or "")).strip()
        if detail:
            log(detail[-800:])
        return False
    return True


def load_data() -> dict:
    run_build()
    if not DASHBOARD_DATA.exists():
        log(f"falta {DASHBOARD_DATA}; el dashboard se abrirá vacío")
        return {}
    text = DASHBOARD_DATA.read_text(encoding="utf-8")
    prefix = "window.DASHBOARD_DATA = "
    return json.loads(text[len(prefix):].rstrip().rstrip(";"))


def read_progress() -> dict | None:
    if not PROGRESS.exists():
        return None
    try:
        return json.loads(PROGRESS.read_text(encoding="utf-8"))
    except Exception:
        return None


def _venv_python() -> str:
    """Interpreter that may have numpy/pillow/playwright."""
    for base in (DEBUG / ".venv", ROOT / ".venv"):
        py = base / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
        if py.exists():
            return str(py)
    return sys.executable


def _visual_python() -> str | None:
    """Interpreter that can actually run the visual comparison, or None."""
    probe = ("import numpy, PIL, playwright.sync_api;"
             "print('ok')")
    for py in (_venv_python(), sys.executable, _system_python()):
        if not py:
            continue
        try:
            r = subprocess.run([py, "-c", probe], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
        except OSError:
            continue
        if r.returncode == 0:
            return py
    return None


class Runner:
    """One subprocess at a time, with a live JSON snapshot for the window."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.proc: subprocess.Popen | None = None
        self.mode = ""
        self.command: list[str] = []
        self.started_at: float | None = None
        self.exit_code: int | None = None
        self.log: list[str] = []

    @property
    def running(self) -> bool:
        with self.lock:
            return self.proc is not None and self.proc.poll() is None

    def start(self, mode: str, cmd: list[str]) -> dict:
        with self.lock:
            if self.proc is not None and self.proc.poll() is None:
                return {"started": False, "error": "a run is already in progress"}
            PROGRESS.unlink(missing_ok=True)
            self.mode = mode
            self.command = list(cmd)
            self.started_at = time.time()
            self.exit_code = None
            self.log = []
            try:
                proc = subprocess.Popen(
                    cmd, cwd=ROOT, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, text=True, bufsize=1)
            except OSError as exc:
                self.exit_code = -1
                return {"started": False, "error": f"could not start: {exc}"}
            self.proc = proc

        def worker() -> None:
            assert proc.stdout is not None
            for line in proc.stdout:
                with self.lock:
                    self.log.append(line.rstrip("\n"))
                    del self.log[:-2000]
            proc.wait()
            with self.lock:
                self.exit_code = proc.returncode
                self.log.append(f"[exit {proc.returncode}]")
            # Keep dashboard_data.js in sync for the static/browser path.
            run_build()

        threading.Thread(target=worker, daemon=True).start()
        return {"started": True, "mode": mode}

    def stop(self) -> dict:
        with self.lock:
            proc = self.proc
        if proc is None or proc.poll() is not None:
            return {"stopped": False, "error": "no active run"}
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        return {"stopped": True}

    def status(self) -> dict:
        with self.lock:
            running = self.proc is not None and self.proc.poll() is None
            progress = read_progress()
            if not running and progress and progress.get("running"):
                # The process died without finishing its snapshot.
                progress = dict(progress)
                progress["running"] = False
                progress["stale"] = True
            return {
                "running": running,
                "mode": self.mode,
                "started_at": self.started_at,
                "exit_code": self.exit_code,
                "command": self.command,
                "log": list(self.log[-160:]),
                "progress": progress,
            }


class Api:
    """pywebview JS API (window.pywebview.api)."""

    def __init__(self, runner: Runner | None = None) -> None:
        self.runner = runner or Runner()

    # -- data ------------------------------------------------------------
    def get_data(self) -> dict:
        return load_data()

    def get_live(self) -> dict:
        return self.runner.status()

    def reload_data(self) -> dict:
        return load_data()

    def get_artifacts(self) -> list[dict]:
        out: list[dict] = []
        for root in (DEBUG / "artifacts", DEBUG / "tests" / "goldens"):
            if not root.exists():
                continue
            for p in sorted(root.rglob("*")):
                if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg"}:
                    rel = os.path.relpath(p, DEBUG / "dashboard")
                    out.append({"path": str(p.relative_to(DEBUG)),
                                "size": p.stat().st_size,
                                "url": rel.replace(os.sep, "/")})
        return out[:600]

    # -- execution -------------------------------------------------------
    def run_tests(self, scope: str = "all", section: int = 1,
                  responsive: bool = True, filt: str = "") -> dict:
        cmd = [sys.executable, str(RUNNER), "--progress", str(PROGRESS)]
        if scope == "all":
            cmd.append("--all")
        else:
            cmd += ["--section", str(section)]
        if not responsive:
            cmd.append("--no-responsive")
        if filt:
            cmd += ["--filter", filt]
        cmd += ["--label", "Tests funcionales" if not responsive else
                "Laboratorio + responsive"]
        return self.runner.start("lab", cmd)

    def run_visual(self, scope: str = "case", case: str = "", section: int = 1,
                   widths: str = "1024") -> dict:
        py = _visual_python()
        if not py:
            return {"started": False,
                    "error": "faltan numpy/pillow/playwright; instala "
                             "debug/requirements.txt y ejecuta "
                             "python -m playwright install chromium"}
        cmd = [py, str(VISUAL_RUNNER), "--progress", str(PROGRESS),
               "--widths", widths or "1024"]
        if scope == "all":
            cmd.append("--all")
        elif scope == "section":
            cmd += ["--section", str(section)]
        elif case:
            cmd += ["--case", case]
        else:
            return {"started": False, "error": "no hay caso seleccionado"}
        cmd += ["--label", "Chrome vs NativaX"]
        return self.runner.start("visual", cmd)

    def stop_run(self) -> dict:
        return self.runner.stop()

    # Kept for older dashboards / scripts.
    def get_status(self) -> dict:
        return self.runner.status()


def _system_python() -> str | None:
    for cand in ("/usr/bin/python3", "/usr/bin/python3.12", "/usr/bin/python3.11"):
        if Path(cand).exists():
            return cand
    return None


def _has_gtk(python: str | None = None) -> bool:
    """True when GTK 3 + WebKit2 (4.1/4.0) are importable."""
    probe = (
        "import gi\n"
        "gi.require_version('Gtk', '3.0')\n"
        "for v in ('4.1', '4.0'):\n"
        "    try:\n"
        "        gi.require_version('WebKit2', v); break\n"
        "    except ValueError: pass\n"
        "from gi.repository import Gtk, WebKit2\n"
    )
    return subprocess.run([python or sys.executable, "-c", probe],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def _has_qt(python: str | None = None) -> bool:
    """True only when a real Qt binding exists (qtpy alone is not enough)."""
    probe = (
        "import importlib.util as u\n"
        "mods = ('PyQt6', 'PySide6', 'PyQt5', 'PySide2')\n"
        "raise SystemExit(0 if any(u.find_spec(m) for m in mods) else 1)\n"
    )
    return subprocess.run([python or sys.executable, "-c", probe],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def _has_qtwebengine(python: str | None = None) -> bool:
    """True when PyQt6 + QtWebEngine can render the dashboard window."""
    probe = (
        "from PyQt6.QtWebEngineWidgets import QWebEngineView\n"
        "from PyQt6.QtWebChannel import QWebChannel\n"
        "from PyQt6.QtWidgets import QApplication\n"
    )
    return subprocess.run([python or sys.executable, "-c", probe],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def _has_gui_backend(python: str | None = None) -> bool:
    """True when pywebview can actually start (GTK or a real Qt binding)."""
    return _has_gtk(python) or _has_qt(python)


def _ensure_webview():
    """Return an importable pywebview with a real backend, or None."""
    try:
        import webview  # type: ignore
    except Exception as exc:
        log(f"pywebview is not installed in {sys.executable}: {exc}")
        webview = None
    if webview is not None and _has_gui_backend():
        return webview
    if webview is not None:
        log("pywebview existe pero no hay backend GTK/Qt real en este intérprete")

    sp = _system_python()
    same = sp and Path(sp).resolve() == Path(sys.executable).resolve()
    if sp and not same and _has_gui_backend(sp) \
            and os.environ.get("NATIVAX_GUI_REEXEC") != "1":
        log(f"retrying with the system Python: {sp}")
        os.environ["NATIVAX_GUI_REEXEC"] = "1"
        os.execv(sp, [sp, str(Path(__file__).resolve())] + sys.argv[1:])

    if not _has_gui_backend():
        log("no GTK/WebKit or Qt backend available")
        return None

    log("pywebview is unavailable; using the GTK/WebKit window")
    return None


def _handle_bridge(uri: str, api: Api) -> None:
    """Handle nativax://run?... clicks sent by the GTK/WebKit dashboard."""
    parts = urlsplit(uri)
    query = {k: v[-1] for k, v in parse_qs(parts.query).items()}
    kind = query.get("kind", "lab")
    if kind == "stop":
        api.runner.stop()
        return
    if kind == "visual":
        api.run_visual(
            scope=query.get("scope", "case"),
            case=query.get("case", ""),
            section=int(query.get("section", "1") or 1),
            widths=query.get("widths", "1024"))
        return
    api.run_tests(
        scope=query.get("scope", "all"),
        section=int(query.get("section", "1") or 1),
        responsive=query.get("responsive", "1") not in ("0", "false", ""),
        filt=query.get("filter", ""))


def _run_qt(api: Api) -> int:
    """PyQt6 + QtWebEngine window with a QWebChannel bridge (no HTTP)."""
    import json as _json

    from PyQt6.QtCore import QFile, QIODevice, QObject, QTimer, QUrl, pyqtSlot
    from PyQt6.QtWebChannel import QWebChannel
    from PyQt6.QtWebEngineCore import QWebEnginePage, QWebEngineScript, QWebEngineSettings
    from PyQt6.QtWebEngineWidgets import QWebEngineView
    from PyQt6.QtWidgets import QApplication, QMainWindow

    app = QApplication(sys.argv[:1])
    app.setApplicationName("NativaX Debug Lab")

    class Bridge(QObject):
        @pyqtSlot(result=str)
        def get_data(self) -> str:
            return _json.dumps(api.get_data())

        @pyqtSlot(result=str)
        def get_live(self) -> str:
            return _json.dumps(api.get_live())

        @pyqtSlot(result=str)
        def get_artifacts(self) -> str:
            return _json.dumps(api.get_artifacts())

        @pyqtSlot(str, int, bool, str, result=str)
        def run_tests(self, scope: str, section: int, responsive: bool,
                      filt: str) -> str:
            return _json.dumps(api.run_tests(scope, section, responsive, filt))

        @pyqtSlot(str, str, int, str, result=str)
        def run_visual(self, scope: str, case: str, section: int,
                       widths: str) -> str:
            return _json.dumps(api.run_visual(scope, case, section, widths))

        @pyqtSlot(result=str)
        def stop_run(self) -> str:
            return _json.dumps(api.stop_run())

    class ConsolePage(QWebEnginePage):
        def javaScriptConsoleMessage(self, level, message, line, source):
            log(f"JS: {message} ({source}:{line})")

    window = QMainWindow()
    window.setWindowTitle("NativaX Debug Lab")
    window.resize(1440, 920)
    view = QWebEngineView(window)
    page = ConsolePage(view)
    view.setPage(page)
    window.setCentralWidget(view)

    settings = page.settings()
    settings.setAttribute(
        QWebEngineSettings.WebAttribute.LocalContentCanAccessFileUrls, True)
    settings.setAttribute(
        QWebEngineSettings.WebAttribute.JavascriptEnabled, True)

    channel = QWebChannel(page)
    bridge = Bridge()
    channel.registerObject("nativax", bridge)
    page.setWebChannel(channel)

    # QWebChannel needs its JS half. Read it from the Qt resource and inject it
    # before any page script, so dashboard.js can open the channel.
    qwc = QFile(":/qtwebchannel/qwebchannel.js")
    if qwc.open(QIODevice.OpenModeFlag.ReadOnly):
        source = bytes(qwc.readAll()).decode("utf-8")
        qwc.close()
        script = QWebEngineScript()
        script.setName("qwebchannel.js")
        script.setSourceCode(source)
        script.setInjectionPoint(
            QWebEngineScript.InjectionPoint.DocumentCreation)
        script.setWorldId(QWebEngineScript.ScriptWorldId.MainWorld)
        page.scripts().insert(script)
    else:
        log("could not read qwebchannel.js from Qt resources")

    # Build dashboard_data.js in the background so the window appears immediately.
    import threading as _threading
    pending_data = {"value": None}

    def _refresh_data() -> None:
        try:
            run_build()
            pending_data["value"] = load_data()
        except Exception as exc:  # noqa: BLE001
            log(f"background build failed: {exc}")

    _threading.Thread(target=_refresh_data, daemon=True).start()

    previous = {"running": False}

    def push() -> None:
        status = api.runner.status()
        finished = previous["running"] and not status["running"]
        previous["running"] = status["running"]
        payload = {"status": status}
        if pending_data["value"] is not None:
            payload["data"] = pending_data["value"]
            pending_data["value"] = None
        if finished:
            try:
                payload["data"] = api.get_data()
            except Exception:
                pass
        page.runJavaScript(
            "window.NATIVAX_PUSH && window.NATIVAX_PUSH(%s);"
            % _json.dumps(payload))

    timer = QTimer(window)
    timer.setInterval(1000)
    timer.timeout.connect(push)
    timer.start()
    page.loadFinished.connect(lambda _ok: push())

    view.setUrl(QUrl.fromLocalFile(str(DASHBOARD_HTML)))
    window.show()
    code = app.exec()
    timer.stop()
    return code


def _run_gtk(api: Api) -> int:
    """GTK 3 + WebKit2 window with a bridge to Python (no HTTP server)."""
    import gi
    gi.require_version("Gtk", "3.0")
    for ver in ("4.1", "4.0"):
        try:
            gi.require_version("WebKit2", ver)
            break
        except ValueError:
            continue
    from gi.repository import GLib, Gtk, WebKit2

    window = Gtk.Window(title="NativaX Debug Lab")
    window.set_default_size(1440, 920)
    window.set_position(Gtk.WindowPosition.CENTER)
    view = WebKit2.WebView()
    view.load_uri(DASHBOARD_HTML.as_uri())
    window.add(view)
    window.connect("destroy", Gtk.main_quit)

    def run_js(script: str) -> None:
        try:
            if hasattr(view, "evaluate_javascript"):
                view.evaluate_javascript(script, -1, None, None, None, None)
            else:
                view.run_javascript(script, None, None, None)
        except Exception as exc:  # noqa: BLE001 - never kill the window
            log(f"JS bridge: {exc}")

    def on_decide(_view, decision, decision_type):
        if decision_type == WebKit2.PolicyDecisionType.NAVIGATION_ACTION:
            uri = decision.get_navigation_action().get_request().get_uri()
            if uri.startswith("nativax://"):
                decision.ignore()
                _handle_bridge(uri, api)
                return True
        return False

    view.connect("decide-policy", on_decide)

    previous = {"running": False}

    def tick():
        status = api.runner.status()
        finished = previous["running"] and not status["running"]
        previous["running"] = status["running"]
        payload = {"status": status}
        if finished:
            payload["data"] = load_data()
        run_js("window.NATIVAX_PUSH && window.NATIVAX_PUSH(%s);"
               % json.dumps(payload))
        return True

    def on_load(_view, event):
        if event == WebKit2.LoadEvent.FINISHED:
            run_js("window.NATIVAX_BRIDGE = 'gtk';")
            tick()

    view.connect("load-changed", on_load)
    GLib.timeout_add(1000, tick)
    window.show_all()
    Gtk.main()
    return 0


def _open_dashboard(url: str | None = None) -> bool:
    """Open the static (read-only) dashboard in the user's browser."""
    uri = url or DASHBOARD_HTML.as_uri()
    try:
        if webbrowser.open(uri):
            log(f"dashboard opened in the browser: {uri}")
            return True
    except Exception as exc:  # noqa: BLE001
        log(f"webbrowser.open failed: {exc}")
    for opener in ("xdg-open", "gio", "sensible-browser"):
        exe = shutil.which(opener)
        if not exe:
            continue
        cmd = [exe, "open", uri] if opener == "gio" else [exe, uri]
        try:
            if subprocess.run(cmd, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0:
                log(f"dashboard abierto con {opener}: {uri}")
                return True
        except Exception:  # noqa: BLE001
            continue
    return False


def _check() -> int:
    """Print why the window would or would not open. Exit 0 when usable."""
    log(f"python: {sys.executable} ({sys.version.split()[0]})")
    log(f"DISPLAY={os.environ.get('DISPLAY', '(sin definir)')} "
        f"WAYLAND_DISPLAY={os.environ.get('WAYLAND_DISPLAY', '(sin definir)')}")
    ok = True
    for name, path in (("dashboard", DASHBOARD_HTML), ("datos", DATA_SCRIPT),
                       ("runner", RUNNER), ("visual", VISUAL_RUNNER)):
        exists = Path(path).exists()
        log(f"{name}: {'ok' if exists else 'FALTA'} {path}")
        ok &= exists
    if not run_build():
        ok = False

    def probe(python: str, label: str) -> bool:
        gtk = _has_gtk(python)
        qt = _has_qt(python)
        qtweb = _has_qtwebengine(python)
        try:
            has_webview = subprocess.run(
                [python, "-c", "import webview"], stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL).returncode == 0
        except OSError:
            has_webview = False
        log(f"{label}: QtWebEngine={'sí' if qtweb else 'no'} "
            f"GTK/WebKit={'sí' if gtk else 'no'} "
            f"Qt={'sí' if qt else 'no'} "
            f"pywebview={'sí' if has_webview else 'no'}")
        return qtweb or gtk or qt

    current_backend = probe(sys.executable, "intérprete actual")
    sp = _system_python()
    other_backend = False
    if sp and Path(sp).resolve() != Path(sys.executable).resolve():
        other_backend = probe(sp, "python del sistema")

    visual_py = _visual_python()
    log(f"visual (numpy/pillow/playwright): "
        f"{visual_py if visual_py else 'FALTA'}")

    if not (current_backend or other_backend):
        log("no QtWebEngine or GTK/WebKit. Install:")
        log("  pip install PyQt6 PyQt6-WebEngine")
        log("  (or on Debian/MX: sudo apt install python3-gi gir1.2-gtk-3.0 "
            "gir1.2-webkit2-4.1)")
        ok = False
    else:
        log("the native window can be opened")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--check" in argv:
        return _check()
    if "--browser" in argv:
        run_build()
        if _open_dashboard():
            log("browser mode: read-only; run from the native window")
            return 0
        log(f"could not open the browser. Open manually: "
            f"{DASHBOARD_HTML.as_uri()}")
        return 1

    if not DASHBOARD_DATA.exists():
        run_build()
    if not DASHBOARD_HTML.exists():
        log(f"dashboard does not exist: {DASHBOARD_HTML}")
        return 1

    api = Api()

    # PyQt6-WebEngine is the preferred window. If only the system Python has
    # it, re-exec there before opening anything.
    if not _has_qtwebengine() and os.environ.get("NATIVAX_GUI_REEXEC") != "1":
        sp = _system_python()
        if sp and Path(sp).resolve() != Path(sys.executable).resolve() \
                and _has_qtwebengine(sp):
            log(f"reintentando con el Python del sistema (QtWebEngine): {sp}")
            os.environ["NATIVAX_GUI_REEXEC"] = "1"
            os.execv(sp, [sp, str(Path(__file__).resolve())] + sys.argv[1:])

    if _has_qtwebengine():
        log(f"opening PyQt6-WebEngine window ({sys.executable})")
        return _run_qt(api)

    webview = _ensure_webview()

    if webview is not None:
        log(f"opening native window with pywebview ({sys.executable})")
        webview.create_window("NativaX Debug Lab", DASHBOARD_HTML.as_uri(),
                              js_api=api, width=1440, height=920)
        webview.start()
        return 0

    if _has_gtk():
        log(f"opening GTK/WebKit window ({sys.executable})")
        return _run_gtk(api)

    # No native backend: the dashboard still opens, but read-only.
    if _open_dashboard():
        log("browser mode: read-only; run from the native window")
        return 0
    log("could not open a window or the browser automatically.")
    log("missing GTK/WebKit libraries. On MX Linux / Debian:")
    log("  sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1")
    log(f"or open this file manually: {DASHBOARD_HTML.as_uri()}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

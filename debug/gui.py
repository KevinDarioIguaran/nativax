#!/usr/bin/env python3
"""Native (pywebview) GUI for the NativaX debug laboratory."""
from __future__ import annotations

import json
import os
import queue
import shutil
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


def log(msg: str) -> None:
    """Progress/diagnostics always go to stderr, never silently swallowed."""
    print(f"[nativax-gui] {msg}", file=sys.stderr, flush=True)


def run_build() -> bool:
    r = subprocess.run([sys.executable, str(DATA_SCRIPT)], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode != 0:
        log(f"no se pudo generar dashboard_data.js (exit {r.returncode})")
        detail = ((r.stdout or "") + (r.stderr or "")).strip()
        if detail:
            log(detail[-800:])
        return False
    return True


def load_data() -> dict:
    run_build()
    path = DEBUG / "dashboard" / "dashboard_data.js"
    if not path.exists():
        log(f"falta {path}; el dashboard se abrirá vacío")
        return {}
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
    candidates = [
        DEBUG / ".venv",
        ROOT / ".venv",
    ]
    for base in candidates:
        py = base / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
        if py.exists():
            return str(py)
    return sys.executable


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


GTK_WINDOW = r'''
import sys
try:
    import gi
    gi.require_version("Gtk", "3.0")
    for ver in ("4.1", "4.0"):
        try:
            gi.require_version("WebKit2", ver)
            break
        except ValueError:
            continue
    from gi.repository import Gtk, WebKit2
except Exception as exc:  # noqa: BLE001
    print(f"[nativax-gui] GTK/WebKit no disponible: {exc}", file=sys.stderr)
    raise SystemExit(3)

uri = sys.argv[1]
window = Gtk.Window(title="NativaX Debug Lab")
window.set_default_size(1380, 900)
window.set_position(Gtk.WindowPosition.CENTER)
view = WebKit2.WebView()
view.load_uri(uri)
window.add(view)
window.connect("destroy", Gtk.main_quit)
window.show_all()
Gtk.main()
'''


def _gtk_python() -> str | None:
    """Interpreter that can open a real GTK/WebKit window."""
    for py in (sys.executable, _system_python()):
        if py and _has_gtk(py):
            return py
    return None


def _launch_gtk() -> bool:
    """Open the dashboard in a native GTK/WebKit window (no pywebview).

    This is the reliable path on Linux: it only needs the distro packages
    python3-gi, gir1.2-gtk-3.0 and gir1.2-webkit2-4.1. The page is read-only
    (no pywebview JS bridge), but it is a real native window.
    """
    py = _gtk_python()
    if not py:
        return False
    log(f"abriendo ventana GTK/WebKit con {py} (modo lectura)")
    try:
        return subprocess.run(
            [py, "-c", GTK_WINDOW, DASHBOARD_HTML.as_uri()]).returncode == 0
    except OSError as exc:
        log(f"no pude lanzar GTK/WebKit: {exc}")
        return False


def _ensure_webview():
    # pywebview itself imports without a GUI backend, but webview.start()
    # then crashes. Check the backend too, and use the system interpreter
    # when the venv was built without Python 3 GI bindings.
    try:
        import webview  # type: ignore
    except Exception as exc:
        log(f"pywebview no está instalado en {sys.executable}: {exc}")
        webview = None
    if webview is not None and _has_gui_backend():
        return webview
    if webview is not None:
        log("pywebview existe pero no hay backend GTK/Qt en este intérprete")

    sp = _system_python()
    same = sp and Path(sp).resolve() == Path(sys.executable).resolve()
    if sp and not same and _has_gui_backend(sp) \
            and os.environ.get("NATIVAX_GUI_REEXEC") != "1":
        log(f"reintentando con el Python del sistema: {sp}")
        os.environ["NATIVAX_GUI_REEXEC"] = "1"
        os.execv(sp, [sp, str(Path(__file__).resolve())] + sys.argv[1:])

    if not _has_gui_backend():
        log("no hay backend GTK/WebKit ni Qt disponible")
        return None

    # Do not block the user with a pip install here: the GTK fallback opens
    # the window immediately. pywebview only adds the interactive JS bridge.
    log("pywebview no está disponible; se usará la ventana GTK/WebKit")
    return None


def _open_dashboard() -> bool:
    """Open the dashboard in the user's browser (fallback path)."""
    uri = DASHBOARD_HTML.as_uri()
    try:
        if webbrowser.open(uri):
            log(f"dashboard abierto en el navegador: {uri}")
            return True
    except Exception as exc:  # noqa: BLE001
        log(f"webbrowser.open falló: {exc}")
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
    """Print why the GUI would or would not open. Exit 0 when usable."""
    log(f"python: {sys.executable} ({sys.version.split()[0]})")
    log(f"DISPLAY={os.environ.get('DISPLAY', '(sin definir)')} "
        f"WAYLAND_DISPLAY={os.environ.get('WAYLAND_DISPLAY', '(sin definir)')}")
    ok = True
    for name, path in (("dashboard", DASHBOARD_HTML), ("datos", DATA_SCRIPT)):
        exists = Path(path).exists()
        log(f"{name}: {'ok' if exists else 'FALTA'} {path}")
        ok &= exists
    if not run_build():
        ok = False

    def probe(python: str, label: str) -> bool:
        backend = _has_gui_backend(python)
        gtk = _has_gtk(python)
        try:
            has_webview = subprocess.run(
                [python, "-c", "import webview"], stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL).returncode == 0
        except OSError:
            has_webview = False
        log(f"{label}: GTK/WebKit={'sí' if gtk else 'no'} "
            f"backend={'sí' if backend else 'no'} "
            f"pywebview={'sí' if has_webview else 'no'}")
        return backend

    current_backend = probe(sys.executable, "intérprete actual")
    sp = _system_python()
    other_backend = False
    if sp and Path(sp).resolve() != Path(sys.executable).resolve():
        other_backend = probe(sp, "python del sistema")

    if not (current_backend or other_backend):
        log("no hay backend GTK/WebKit ni Qt: instala python3-gi, "
            "gir1.2-gtk-3.0 y gir1.2-webkit2-4.1")
        ok = False
    else:
        log("la ventana nativa se abrirá con GTK/WebKit "
            "(pywebview solo añade los botones interactivos)")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    force_browser = "--browser" in argv
    if "--check" in argv:
        return _check()

    run_build()
    if not DASHBOARD_HTML.exists():
        log(f"no existe el dashboard: {DASHBOARD_HTML}")
        return 1

    if force_browser:
        if _open_dashboard():
            return 0
        log(f"no pude abrir el navegador. Abre manualmente: {DASHBOARD_HTML.as_uri()}")
        return 1

    webview = _ensure_webview()

    if webview is not None:
        api = Api()
        log(f"abriendo ventana nativa con pywebview ({sys.executable})")
        webview.create_window("NativaX Debug Lab", DASHBOARD_HTML.as_uri(),
                              js_api=api, width=1380, height=900)
        webview.start()
        return 0

    # Native window without pywebview: only needs distro GTK/WebKit packages.
    if _launch_gtk():
        return 0

    # Last resort: open the static dashboard in the default browser.
    if _open_dashboard():
        print(f"dashboard abierto en el navegador: {DASHBOARD_HTML} "
              f"(modo lectura; instala pywebview para el modo interactivo)")
        return 0
    log("no pude abrir una ventana ni el navegador automáticamente.")
    log("faltan las librerías GTK/WebKit. En MX Linux / Debian:")
    log("  sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1")
    log(f"o abre este archivo a mano: {DASHBOARD_HTML.as_uri()}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

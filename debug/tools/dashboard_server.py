#!/usr/bin/env python3
"""Small local backend for the NativaX visual dashboard."""
from __future__ import annotations

import json
import mimetypes
import subprocess
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parents[2]
DEBUG = ROOT / "debug"
LAB = DEBUG / "lab"
RUNNER = LAB / "run_lab.py"
BUILD = DEBUG / "tools" / "build_dashboard_data.py"

STATE = {
    "running": False,
    "started_at": None,
    "finished_at": None,
    "exit_code": None,
    "log": [],
    "proc": None,
    "scope": None,
}
LOCK = threading.Lock()


def run_build() -> None:
    subprocess.run([sys.executable, str(BUILD)], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def start_run(scope: str, section: int | None, responsive: bool) -> bool:
    with LOCK:
        if STATE["running"]:
            return False
        STATE["running"] = True
        STATE["started_at"] = time.time()
        STATE["finished_at"] = None
        STATE["exit_code"] = None
        STATE["log"] = []
        STATE["scope"] = scope
        cmd = [sys.executable, str(RUNNER)]
        if scope == "all":
            cmd.append("--all")
        else:
            cmd += ["--section", str(section or 1)]
        if not responsive:
            cmd.append("--no-responsive")
        STATE["proc"] = subprocess.Popen(
            cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
        )

    def worker():
        proc = STATE["proc"]
        for line in proc.stdout:
            with LOCK:
                STATE["log"].append(line.rstrip("\n"))
                if len(STATE["log"]) > 2000:
                    STATE["log"] = STATE["log"][-2000:]
        proc.wait()
        with LOCK:
            STATE["running"] = False
            STATE["exit_code"] = proc.returncode
            STATE["finished_at"] = time.time()
        run_build()

    threading.Thread(target=worker, daemon=True).start()
    return True


def dashboard_json() -> dict:
    run_build()
    path = DEBUG / "dashboard_data.js"
    text = path.read_text(encoding="utf-8")
    prefix = "window.DASHBOARD_DATA = "
    return json.loads(text[len(prefix):].rstrip().rstrip(";"))


def list_artifacts() -> list[dict]:
    out = []
    for base in (DEBUG / "judge" / "captures", DEBUG / "artifacts"):
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".json"}:
                out.append({"path": str(p.relative_to(DEBUG)), "size": p.stat().st_size})
    return out[:200]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, status=200, body=b"", content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/api/health":
            self._send(200, json.dumps({"ok": True}).encode())
            return
        if path == "/api/run/status":
            with LOCK:
                payload = {
                    "running": STATE["running"],
                    "started_at": STATE["started_at"],
                    "finished_at": STATE["finished_at"],
                    "exit_code": STATE["exit_code"],
                    "scope": STATE["scope"],
                    "log": STATE["log"][-80:],
                }
            self._send(200, json.dumps(payload).encode())
            return
        if path == "/api/dashboard-data":
            try:
                data = dashboard_json()
                self._send(200, json.dumps(data).encode())
            except Exception as exc:
                self._send(500, json.dumps({"error": str(exc)}).encode())
            return
        if path == "/api/report":
            report = DEBUG / "reports" / "lab" / "latest.json"
            if report.exists():
                self._send(200, report.read_bytes(), "application/json")
            else:
                self._send(404, json.dumps({"error": "no report"}).encode())
            return
        if path == "/api/history":
            idx = DEBUG / "history" / "index.json"
            if idx.exists():
                self._send(200, idx.read_bytes(), "application/json")
            else:
                self._send(404, json.dumps({"error": "no history"}).encode())
            return
        if path == "/api/artifacts":
            self._send(200, json.dumps(list_artifacts()).encode())
            return
        # static
        rel = path.lstrip("/") or "dashboard.html"
        if ".." in rel.split("/"):
            self._send(403, b"forbidden")
            return
        target = DEBUG / rel
        if target.is_dir():
            target = target / "index.html"
        if not target.exists() or not target.is_file():
            self._send(404, b"not found")
            return
        ctype = mimetypes.guess_type(str(target))[0] or "application/octet-stream"
        self._send(200, target.read_bytes(), ctype)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/run":
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length) if length else b"{}"
            try:
                body = json.loads(raw.decode() or "{}")
            except Exception:
                body = {}
            scope = body.get("scope", "all")
            section = body.get("section")
            responsive = bool(body.get("responsive", False))
            ok = start_run(scope, section, responsive)
            if not ok:
                self._send(409, json.dumps({"error": "run already in progress"}).encode())
            else:
                self._send(200, json.dumps({"started": True}).encode())
            return
        self._send(404, b"not found")


def start_server():
    for p in range(8765, 8790):
        try:
            httpd = ThreadingHTTPServer(("127.0.0.1", p), Handler)
            port = p
            break
        except OSError:
            continue
    else:
        raise RuntimeError("no free port")
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    return httpd, port, f"http://127.0.0.1:{port}/dashboard.html"


def main() -> int:
    httpd, port, url = start_server()
    print(f"dashboard server: {url}")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

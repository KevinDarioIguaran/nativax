"""Run engines: starts the real engine commands, streams their output live,
and archives the finished run as an immutable report (debug/logic/storage)."""
from __future__ import annotations

import os
import queue
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

from debug.app.components.basic import button, combo, entry, frame, label, text_area
from debug.styles import theme as t

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "debug" / "logic"))
import storage  # noqa: E402

# name -> (area for archiving, command builder(out_dir, filter) -> argv, help)
ENGINES = {
    "Visual comparison": ("visual", lambda out, only: [
        "dart", "run", "debug/engines/visual_comparison/bin/visual_check.dart", "--suite", "50projects50days",
        *(["--only", only] if only else []), "--out", out], "50projects50days pages vs Chromium"),
    "Performance": ("perf", lambda out, only: [
        "dart", "run", "debug/engines/performance/bin/perf.dart", "run",
        *(["--only", only] if only else []), "--out", out], "scenario catalog vs Chromium"),
    "Memory (quick)": ("leaks", lambda out, only: [
        "dart", "run", "debug/engines/memory/bin/leaks.dart", "run", "--profile", "quick",
        *(["--only", only] if only else []), "--out", out], "leak and lifecycle cases"),
    "Security": ("security", lambda out, only: [
        "dart", "run", "debug/engines/security/bin/security.dart", "run",
        *(["--only", only] if only else []), "--out", out], "bridge and host-API attack cases"),
}
PROGRESS = re.compile(r"\[\s*(\d+)\s*/\s*(\d+)\s*\]")


class Page:
    def __init__(self, frm, app):
        self.app, self.frm = app, frm
        self.proc = None
        self.lines: queue.Queue = queue.Queue()
        bar = frame(frm)
        bar.pack(fill="x")
        label(bar, "Run engines", role="title", fg="text-primary").pack(side="left")
        label(bar, "runs the real engine; when it finishes the output is archived as a new immutable report").pack(
            side="left", padx=t.space("lg"))
        form = frame(frm)
        form.pack(fill="x", pady=t.space("sm"))
        label(form, "Engine").pack(side="left")
        self.engine = combo(form, list(ENGINES), width=22)
        self.engine.pack(side="left", padx=t.space("sm"))
        label(form, "Only (regex, optional)").pack(side="left")
        self.only = entry(form, 30)
        self.only.pack(side="left", padx=t.space("sm"))
        self.start_btn = button(form, "▶ Run", self.start, primary=True)
        self.start_btn.pack(side="left", padx=t.space("sm"))
        self.stop_btn = button(form, "■ Stop", self.stop)
        self.stop_btn.pack(side="left")
        self.state = label(frm, "idle", role="label", fg="text-primary", anchor="w")
        self.state.pack(fill="x")
        holder = frame(frm)
        holder.pack(fill="both", expand=True)
        self.log = text_area(holder, height=30, surface="surface-sunken")
        self.log.pack(fill="both", expand=True)
        self.frm.after(100, self._drain)

    def refresh(self):
        pass

    def start(self):
        if self.proc is not None:
            return
        name = self.engine.get()
        area, build, _ = ENGINES[name]
        self.out = Path(tempfile.mkdtemp(prefix=f"nxdebug-{area}-"))
        self.argv = build(str(self.out), self.only.get().strip())
        self.area, self.name = area, name
        self.started = time.monotonic()
        self.log.delete("1.0", "end")
        self.log.insert("end", "$ " + " ".join(self.argv) + "\n")
        try:
            self.proc = subprocess.Popen(self.argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                         text=True, bufsize=1, start_new_session=True)
        except OSError as error:
            self.state.configure(text=f"could not start: {error}", fg=t.color("status-error"))
            self.proc = None
            return
        self.stopped = False
        self.state.configure(text=f"running {name} …", fg=t.color("status-info"))

        def reader(proc):
            for line in proc.stdout:
                self.lines.put(line)
            proc.wait()
            self.lines.put(None)
        threading.Thread(target=reader, args=(self.proc,), daemon=True).start()

    def stop(self):
        if self.proc is not None:
            self.stopped = True
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
            except OSError:
                pass

    def _drain(self):
        try:
            while True:
                line = self.lines.get_nowait()
                if line is None:
                    self._finished()
                    break
                self.log.insert("end", line)
                self.log.see("end")
                m = PROGRESS.findall(line)
                if m:
                    done, total = m[-1]
                    self.state.configure(text=f"running {self.name}: {done}/{total} · "
                                              f"{time.monotonic() - self.started:.0f} s")
        except queue.Empty:
            pass
        self.frm.after(100, self._drain)

    def _finished(self):
        code = self.proc.returncode
        self.proc = None
        status = "aborted" if self.stopped else ("completed" if code == 0 else "failed")
        try:
            run_dir = storage.archive(self.area, self.out, engine=self.argv[2] if len(self.argv) > 2 else None,
                                      argv=self.argv, status=status,
                                      notes=f"started from the debug app; exit code {code}")
            self.log.insert("end", f"\n[archived as {run_dir}]\n")
            self.state.configure(text=f"{self.name} {status} (exit {code}); archived as {run_dir.name}",
                                 fg=t.status_color(status))
        except Exception as error:  # noqa: BLE001 - the run output stays in the temp dir
            self.log.insert("end", f"\n[not archived: {error}; output left in {self.out}]\n")
            self.state.configure(text=f"{self.name} {status}; archive failed: {error}", fg=t.color("status-error"))
        self.app.reload()

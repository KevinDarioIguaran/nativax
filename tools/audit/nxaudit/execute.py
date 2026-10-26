"""Executors: NativaX (system under test) and Chromium (reference).

Both run a whole batch per process start. NativaX goes through
`examples/web-challenge/test/audit_batch_test.dart` (one flutter_tester for
the batch); Chromium loads one parent page that runs every scenario in a
same-origin `srcdoc` iframe sized to the scenario viewport.

Isolation: the NativaX harness writes `begin`/`result` lines; a scenario
that hangs or kills the process is the last unmatched `begin`, it is
recorded as `timeout`/`crash`, and the batch resumes after it.
"""
from __future__ import annotations

import html
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

from .compile import compile_screen
from .probe import probe_source

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "examples" / "web-challenge"
V8_LIB = ROOT / "tools" / "v8-spike" / "target" / "release" / "libnx_v8.so"

CHROME_FLAGS = [
    "--headless=new", "--disable-gpu", "--hide-scrollbars",
    "--force-device-scale-factor=1", "--no-first-run",
    "--no-default-browser-check", "--disable-background-networking",
    "--disable-sync", "--disable-extensions", "--disable-dev-shm-usage",
    "--disable-lcd-text", "--host-resolver-rules=MAP * ~NOTFOUND",
]


def _job(scenario: dict, html_path: Path) -> dict:
    env = scenario.get("environment") or {}
    return {
        "id": scenario["scenario_id"],
        "html": str(html_path),
        "width": env.get("viewport_width", 360),
        "height": env.get("viewport_height", 640),
        "wait_ms": env.get("wait_ms", 300),
        "actions": scenario.get("actions") or [],
    }


def _run(cmd, cwd, env, timeout):
    """Runs a process group; returns (code, stdout, stderr, timed_out)."""
    proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True,
                            start_new_session=True)
    try:
        out, err = proc.communicate(timeout=timeout)
        return proc.returncode, out, err, False
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        out, err = proc.communicate()
        return -9, out or "", err or "", True


def run_nativa(scenarios: list[dict], work: Path, *, per_scenario_s: float = 12.0,
               log=print) -> dict[str, dict]:
    """Runs scenarios in NativaX; returns {scenario_id: observation}."""
    work.mkdir(parents=True, exist_ok=True)
    pages = work / "pages"
    pages.mkdir(exist_ok=True)
    jobs = []
    for scenario in scenarios:
        path = pages / f"{_safe(scenario['scenario_id'])}.html"
        path.write_text(compile_screen(scenario))
        jobs.append(_job(scenario, path))
    results: dict[str, dict] = {}
    pending = jobs
    attempt = 0
    env = dict(os.environ)
    if "NATIVAX_V8_LIB" not in env and V8_LIB.exists():
        env["NATIVAX_V8_LIB"] = str(V8_LIB)
    while pending and attempt < len(jobs) + 1:
        attempt += 1
        out = work / f"nativa-{attempt}.jsonl"
        manifest = work / f"manifest-{attempt}.json"
        manifest.write_text(json.dumps({"out": str(out),
                                        "probe_js": probe_source(),
                                        "scenarios": pending}))
        env["NATIVAX_AUDIT_MANIFEST"] = str(manifest)
        started = time.monotonic()
        code, stdout, stderr, timed_out = _run(
            ["flutter", "test", "test/audit_batch_test.dart", "--no-pub",
             "--reporter=compact"],
            HARNESS, env, 90 + per_scenario_s * len(pending))
        lines = []
        if out.exists():
            for raw in out.read_text().splitlines():
                try:
                    lines.append(json.loads(raw))
                except ValueError:
                    pass
        began = [l["id"] for l in lines if l.get("kind") == "begin"]
        for line in lines:
            if line.get("kind") == "result":
                line["wall_batch_s"] = round(time.monotonic() - started, 2)
                results[line["id"]] = line
        unfinished = [i for i in began if i not in results]
        if unfinished:
            bad = unfinished[-1]
            results[bad] = {
                "id": bad, "status": "timeout" if timed_out else "crash",
                "stage": "harness",
                "error": ("batch timed out" if timed_out else
                          f"flutter test exited {code}") + ": " + _tail(stdout + stderr),
                "states": [], "flutter_errors": [], "script_errors": [],
            }
            log(f"[nativa] {bad}: {results[bad]['status']}; resuming after it")
        elif not began:
            # Harness never started (build error): report every job, stop.
            for job in pending:
                results[job["id"]] = {
                    "id": job["id"], "status": "harness_error", "stage": "harness",
                    "error": _tail(stdout + stderr, 20), "states": [],
                    "flutter_errors": [], "script_errors": []}
            break
        pending = [j for j in pending if j["id"] not in results]
    return results


_CHROME_DRIVER = r"""
(function () {
  var JOBS = __JOBS__;
  var PROBE = __PROBE__;
  var out = [];
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  function load(frame, html) {
    return new Promise(function (resolve) { frame.onload = resolve; frame.srcdoc = html; });
  }
  function rectOf(state, id) {
    var els = (state && state.elements) || [];
    for (var i = 0; i < els.length; i++) if (els[i].id === id) return els[i].rect;
    return null;
  }
  function probe(w) {
    try { return JSON.parse(w.__nxProbe()); } catch (e) { return null; }
  }
  function focusable(el) {
    for (var n = el; n; n = n.parentElement) {
      var t = n.tagName;
      if ((t === 'BUTTON' || t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT' || t === 'A') && !n.disabled) return n;
      if (n.hasAttribute && n.hasAttribute('tabindex')) return n;
    }
    return null;
  }
  function tabOrder(doc) {
    var all = doc.querySelectorAll('a[href],button,input,textarea,select,[tabindex]');
    var list = [];
    for (var i = 0; i < all.length; i++) {
      var e = all[i];
      var ti = e.hasAttribute('tabindex') ? parseInt(e.getAttribute('tabindex'), 10) : 0;
      if (e.disabled || ti < 0) continue;
      var r = e.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      list.push({ el: e, ti: ti, i: i });
    }
    list.sort(function (a, b) {
      var ka = a.ti === 0 ? 1e9 : a.ti, kb = b.ti === 0 ? 1e9 : b.ti;
      return ka - kb || a.i - b.i;
    });
    return list.map(function (x) { return x.el; });
  }
  async function run(job) {
    var t0 = performance.now();
    var frame = document.createElement('iframe');
    frame.style.cssText = 'border:0;display:block;width:' + job.width + 'px;height:' + job.height + 'px';
    document.body.appendChild(frame);
    async function boot() {
      await load(frame, job.html);
      try { frame.contentWindow.eval(PROBE); } catch (e) {}
      await sleep(job.wait_ms);
    }
    await boot();
    var w = frame.contentWindow;
    var states = [{ after: 'initial', probe: probe(w) }];
    var results = [];
    for (var i = 0; i < job.actions.length; i++) {
      var a = job.actions[i], ok = true, note = null;
      var doc = frame.contentDocument;
      var cur = states[states.length - 1].probe;
      try {
        if (a.op === 'click' || a.op === 'type') {
          var r = rectOf(cur, a.target);
          if (!r) { ok = false; note = 'target not measured'; }
          else {
            var x = r[0] + r[2] / 2, y = r[1] + r[3] / 2;
            var el = doc.elementFromPoint(x, y);
            if (!el) { ok = false; note = 'no element at point'; }
            else {
              var opt = { bubbles: true, cancelable: true, clientX: x, clientY: y, view: w };
              el.dispatchEvent(new w.PointerEvent('pointerdown', opt));
              el.dispatchEvent(new w.MouseEvent('mousedown', opt));
              var f = focusable(el); if (f) f.focus();
              el.dispatchEvent(new w.PointerEvent('pointerup', opt));
              el.dispatchEvent(new w.MouseEvent('mouseup', opt));
              el.dispatchEvent(new w.MouseEvent('click', opt));
              if (a.op === 'type') {
                var t = doc.activeElement;
                if (t && 'value' in t) {
                  t.value = a.text || '';
                  t.dispatchEvent(new w.InputEvent('input', { bubbles: true, data: a.text || '' }));
                } else { ok = false; note = 'no text input focused'; }
              }
            }
          }
        } else if (a.op === 'key') {
          if (a.key === 'Tab') {
            var order = tabOrder(doc);
            var idx = order.indexOf(doc.activeElement);
            var next = order[(idx + 1) % order.length];
            if (next) next.focus();
            note = 'reference: focus traversal model';
          } else { ok = false; note = 'reference cannot synthesize key ' + a.key; }
        } else if (a.op === 'resize') {
          frame.style.width = a.width + 'px'; frame.style.height = a.height + 'px';
        } else if (a.op === 'rebuild') {
          await boot(); w = frame.contentWindow;
        } else if (a.op === 'script') {
          w.eval(a.js || '');
        } else if (a.op !== 'wait') { ok = false; note = 'unknown op ' + a.op; }
      } catch (e) { ok = false; note = String(e); }
      await sleep(a.wait_ms || job.wait_ms);
      states.push({ after: 'action:' + i + ':' + a.op, probe: probe(w) });
      results.push({ index: i, op: a.op, ok: ok, note: note });
    }
    out.push({ kind: 'result', id: job.id, status: 'ok', engine: 'chromium',
               states: states, action_results: results,
               timings: { total_ms: Math.round(performance.now() - t0) } });
    frame.remove();
  }
  (async function () {
    for (var i = 0; i < JOBS.length; i++) {
      try { await run(JOBS[i]); }
      catch (e) { out.push({ kind: 'result', id: JOBS[i].id, status: 'error', error: String(e), states: [] }); }
    }
    var pre = document.createElement('pre');
    pre.id = '__nxout';
    pre.textContent = JSON.stringify(out);
    document.body.appendChild(pre);
  })();
})();
"""


def run_chrome(scenarios: list[dict], work: Path, *, executable: str = "google-chrome",
               chunk: int = 60, log=print) -> dict[str, dict]:
    """Runs scenarios in headless Chromium; returns {scenario_id: observation}."""
    work.mkdir(parents=True, exist_ok=True)
    results: dict[str, dict] = {}
    probe = probe_source()
    for start in range(0, len(scenarios), chunk):
        part = scenarios[start:start + chunk]
        jobs = []
        budget = 2000
        for scenario in part:
            job = _job(scenario, Path("-"))
            job["html"] = compile_screen(scenario)
            jobs.append(job)
            budget += 600 + job["wait_ms"] * (2 + 2 * len(job["actions"]))
        driver = (_CHROME_DRIVER.replace("__JOBS__", json.dumps(jobs).replace("</", "<\\/"))
                  .replace("__PROBE__", json.dumps(probe).replace("</", "<\\/")))
        page = work / f"chrome-{start // chunk}.html"
        page.write_text("<!doctype html><html><head><meta charset='utf-8'></head>"
                        f"<body style='margin:0'><script>{driver}</script></body></html>")
        profile = Path(tempfile.mkdtemp(prefix="nxaudit-chrome-"))
        try:
            code, stdout, stderr, timed_out = _run(
                [executable, *CHROME_FLAGS, f"--user-data-dir={profile}",
                 "--window-size=1400,1000", f"--virtual-time-budget={budget}",
                 "--dump-dom", page.as_uri()],
                ROOT, None, 60 + budget / 1000 * 2)
        finally:
            shutil.rmtree(profile, ignore_errors=True)
        match = re.search(r'<pre id="__nxout">([\s\S]*?)</pre>', stdout)
        parsed = []
        if match:
            try:
                parsed = json.loads(html.unescape(match.group(1)))
            except ValueError as error:
                log(f"[chrome] bad output: {error}")
        for line in parsed:
            results[line["id"]] = line
        for scenario in part:
            sid = scenario["scenario_id"]
            if sid not in results:
                results[sid] = {"id": sid, "status": "reference_error",
                                "error": ("timed out" if timed_out else f"exit {code}")
                                + ": " + _tail(stderr), "states": []}
    return results


def _safe(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value)[:120]


def _tail(text: str, lines: int = 8) -> str:
    parts = [l for l in (text or "").strip().splitlines() if l.strip()]
    return "\n".join(parts[-lines:])

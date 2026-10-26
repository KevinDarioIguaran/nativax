"""Bug-detection workspace (JSON interface audit runs): issues ordered as the
engine orders them, the detail of one issue in six panels (summary,
location, reproduction, evidence, root cause, fix & regression), and the
executed scenarios. Data comes from debug/logic/audit_store (read-only)."""
from __future__ import annotations

import json
import sys
import tkinter as tk
from pathlib import Path
from tkinter import ttk

from debug.app.components.basic import (KeyValue, bullet_list, button, copy, frame, label, scroll_frame,
                                        section, text_area)
from debug.app.components.json_views import JsonText, JsonTree
from debug.app.components.table import Table
from debug.styles import theme as t

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "debug" / "logic"))
import audit_store  # noqa: E402


class Workspace:
    def __init__(self, nb, app, ref, focus=None):
        self.app, self.nb = app, nb
        self.unit = audit_store.Unit(Path(ref.path))
        self._issues_tab()
        self._detail_tab()
        self._scenarios_tab()
        rows = self.unit.issue_rows()
        if rows:
            self.open_issue(focus or rows[0]["issue_id"], switch=False)

    # --------------------------------------------------------------- issues
    def _issues_tab(self):
        tab = frame(self.nb)
        self.nb.add(tab, text="Issues")
        label(tab, "Order used by the engine: severity, then occurrences. The engine computes no other priority. "
                   "“Confirmed” causes require an exception stack; everything else is a hypothesis.",
              role="caption", anchor="w", justify="left", wraplength=1300).pack(fill="x")
        rows = []
        for r in self.unit.issue_rows():
            if "error" in r:
                rows.append({"issue_id": r["issue_id"], "message": f"unreadable report: {r['error']}"})
            else:
                rows.append(r)
        self.issues = Table(tab, [
            ("issue_id", "Issue", 110, "w"), ("severity", "Severity", 70, "w"), ("status", "Status", 110, "w"),
            ("root_cause", "Cause", 90, "w"), ("kind", "Oracle", 90, "w"), ("subsystem", "Subsystem", 120, "w"),
            ("component", "Component", 150, "w"), ("property", "Property", 140, "w"), ("count", "Occurrences", 84, "e"),
            ("reproducible", "Reproduced", 80, "c"), ("minimized", "Minimized", 76, "c"),
            ("confidence", "Certainty", 70, "w"), ("novelty", "Novelty", 80, "w"),
            ("message", "Description (deterministic)", 460, "w")],
            status_key="severity", on_open=lambda r: self.open_issue(r["issue_id"]))
        self.issues.set_rows(rows)
        self.issues.pack(fill="both", expand=True)

    # --------------------------------------------------------------- detail
    def _detail_tab(self):
        self.detail = frame(self.nb)
        self.nb.add(self.detail, text="Issue detail")
        self.detail_title = label(self.detail, "no issue selected", role="heading", fg="text-primary", anchor="w")
        self.detail_title.pack(fill="x")
        self.detail_nb = ttk.Notebook(self.detail)
        self.detail_nb.pack(fill="both", expand=True)

    def open_issue(self, issue_id, switch=True):
        got = self.unit.issues().get(issue_id)
        for tab in self.detail_nb.tabs():
            self.detail_nb.forget(tab)
        if got is None or not got.ok:
            self.detail_title.configure(text=f"{issue_id}: {got.error if got else 'not in this report'}")
            return
        r = got.value
        c, loc, rep = r.get("classification") or {}, r.get("location") or {}, r.get("reproduction") or {}
        ev, rc, inv, ver = (r.get("evidence") or {}, r.get("root_cause") or {}, r.get("investigation") or {},
                            r.get("verification") or {})
        self.detail_title.configure(text=f"{issue_id} — {ev.get('message')}  ({got.source})")

        def panel(title):
            holder = frame(self.detail_nb, "surface-raised")
            self.detail_nb.add(holder, text=title)
            return scroll_frame(holder)

        inner = panel("A · Summary")
        kv = KeyValue(inner)
        kv.set([("What failed", ev.get("message")), ("Expected (reference)", json.dumps(r.get("expected"))),
                ("Observed (NativaX)", json.dumps(r.get("actual"))), ("Difference", json.dumps(r.get("difference"))),
                ("Status", r.get("status")), ("Severity", r.get("severity")), ("Novelty", r.get("novelty")),
                ("Certainty", (r.get("confidence") or {}).get("level")),
                ("Classification method", (r.get("confidence") or {}).get("basis")),
                ("Oracle", c.get("kind")), ("Subsystem", c.get("subsystem")), ("Stage", c.get("stage")),
                ("Component types", c.get("component_types")), ("Property", c.get("property")),
                ("Fingerprint", r.get("fingerprint")), ("Occurrences", (r.get("occurrences") or {}).get("count"))])
        kv.pack(fill="x")

        inner = panel("B · Location")
        kv = KeyValue(inner)
        kv.set([("Screen", loc.get("screen_id")), ("Scenario", r.get("scenario_id")), ("Element", loc.get("element_id")),
                ("JSON path", loc.get("json_path")), ("JSON path in the minimal case", loc.get("minimal_json_path")),
                ("Source file", loc.get("source_file")), ("Symbol", loc.get("symbol")), ("Line", loc.get("line")),
                ("Column", None),
                ("Basis", loc.get("basis") or "no stack trace: the engine confirms no file or line")])
        kv.pack(fill="x")
        if loc.get("json_path"):
            button(inner, "Copy JSON path", lambda: copy(inner, loc["json_path"])).pack(anchor="w", padx=t.space("md"))
        section(inner, "Files to inspect (basis in the last column; a grep hit is not a cause)")
        files = Table(inner, [("file", "File", 420, "w"), ("line", "Line", 60, "e"), ("basis", "Basis", 260, "w"),
                              ("match", "Match", 380, "w")], height=8)
        files.set_rows(inv.get("files_to_inspect") or [])
        files.pack(fill="x", padx=t.space("sm"))

        inner = panel("C · Reproduction")
        scen = rep.get("scenario") or {}
        kv = KeyValue(inner)
        kv.set([("Seed", rep.get("seed")), ("Family", rep.get("family")),
                ("Environment", json.dumps(scen.get("environment")) if scen else None),
                ("Preconditions", scen.get("preconditions") or None), ("Failed assertion", ev.get("assertion_id")),
                ("Reproduced on re-run", rep.get("reproducible")), ("Minimized", rep.get("minimized")),
                ("Command", rep.get("command"))])
        kv.pack(fill="x")
        if rep.get("command"):
            button(inner, "Copy command", lambda: copy(inner, rep["command"])).pack(anchor="w", padx=t.space("md"))
        section(inner, "Steps")
        bullet_list(inner, rep.get("steps") or [])
        mini = rep.get("minimization") or {}
        section(inner, "Minimization")
        kv = KeyValue(inner)
        kv.set([(k, json.dumps(v) if isinstance(v, (list, dict)) else v) for k, v in mini.items()] or
               [("minimization record", None)])
        kv.pack(fill="x")
        if rep.get("minimal_scenario"):
            section(inner, "Minimal scenario")
            jt = JsonText(inner, height=16)
            jt.pack(fill="x", padx=t.space("sm"))
            jt.show(rep["minimal_scenario"], rep["minimal_scenario"].get("scenario_id", ""))

        holder = frame(self.detail_nb)
        self.detail_nb.add(holder, text="D · Evidence")
        tree = JsonTree(holder)
        tree.pack(fill="both", expand=True)
        tree.show({"finding": ev.get("finding"), "stack": ev.get("stack"), "artifacts": ev.get("artifacts"),
                   "consequential_findings": ev.get("consequential_findings")}, [])

        inner = panel("E · Root cause")
        finding = ev.get("finding") or {}
        section(inner, "Observed facts (measured)")
        bullet_list(inner, [f"state {finding.get('state')}: expected {json.dumps(finding.get('expected'))}",
                            f"observed {json.dumps(finding.get('actual'))}",
                            f"element {finding.get('element_id')} at {finding.get('json_path')}"])
        section(inner, "Algorithm inferences (deterministic rules)")
        bullet_list(inner, [f"stage “{c.get('stage')}” from oracle “{c.get('kind')}”",
                            f"primary (first divergence): {finding.get('primary')}",
                            *[f"ruled out as consequence: {x}" for x in finding.get("consequence_of") or []]])
        for status, title, tone in (("confirmed", "Confirmed causes (with a stack trace)", "status-error"),
                                    ("unconfirmed", "Unconfirmed hypotheses", "status-estimate"),
                                    ("rejected", "Rejected hypotheses", "status-unknown")):
            hyps = [h for h in rc.get("hypotheses") or [] if h.get("status") == status]
            label(inner, f"{title} ({len(hyps)})", role="heading", fg=tone, surface="surface-raised").pack(
                anchor="w", padx=t.space("md"), pady=(t.space("md"), 0))
            for h in hyps:
                bullet_list(inner, [h.get("statement")])
                bullet_list(inner, [f"for: {e}" for e in h.get("evidence_for") or []], fg="status-ok", empty="no evidence for")
                bullet_list(inner, [f"against: {e}" for e in h.get("evidence_against") or []], fg="status-error",
                            empty="no evidence against")
        section(inner, "Pending checks")
        bullet_list(inner, (inv.get("next_checks") or []) + [f"rule out: {x}" for x in rc.get("alternatives_to_rule_out") or []])

        inner = panel("F · Fix and regression")
        kv = KeyValue(inner)
        kv.set([("Fix applied", ver.get("fix_applied")), ("Reproduction after fix", ver.get("reproduction_passed")),
                ("Regression suite", ver.get("regression_passed")), ("Verified at", ver.get("verified_at")),
                ("Associated code changes", None)])
        kv.pack(fill="x")
        label(inner, "The engine does not record which code change fixed an issue; only the verify result.",
              role="caption", surface="surface-raised").pack(anchor="w", padx=t.space("md"))
        for title, key in (("Fix requirements", "fix_requirements"), ("Constraints", "constraints"),
                           ("Regression tests", "regression_tests"), ("Acceptance criteria", "acceptance_criteria")):
            section(inner, title)
            bullet_list(inner, r.get(key) or [])
        if switch:
            self.nb.select(self.detail)

    # ------------------------------------------------------------ scenarios
    def _scenarios_tab(self):
        tab = frame(self.nb)
        self.nb.add(tab, text="Scenarios")
        panes = tk.PanedWindow(tab, orient="vertical", bg=t.color("surface"), sashwidth=t.space("sm"))
        panes.pack(fill="both", expand=True)
        viewer = JsonText(panes, height=16)
        table = Table(panes, [
            ("order", "#", 50, "e"), ("scenario_id", "Scenario", 300, "w"), ("family", "Family", 100, "w"),
            ("category", "Category", 110, "w"), ("status", "Result", 90, "w"), ("total_ms", "ms", 70, "e"),
            ("seed", "Seed", 80, "e"), ("findings", "Findings", 70, "e"), ("primary", "Primary", 64, "e"),
            ("issues", "Issues", 260, "w")],
            status_key="status",
            on_select=lambda r: viewer.show((self.unit.scenario(r["scenario_id"]) or {}).get("scenario"),
                                            r["scenario_id"]))
        table.set_rows(self.unit.rows())
        panes.add(table, height=360)
        panes.add(viewer)

"""Issue reports (JSON contract + LLM investigation brief) and the aggregate
summary. Everything written here is derived from recorded observations; no
field is filled with a guess (unknown -> null, empty collection -> [])."""
from __future__ import annotations

import json
from pathlib import Path

from .compile import compile_screen
from .schema import REPORT_VERSION, check_report

CONSTRAINTS = [
    "Keep rendering inside HTML -> DOM -> CSS -> nativa_render -> Flutter widgets; no WebView/browser fallback.",
    "Do not change the audit oracle, tolerances or the reference to make the case pass.",
    "Preserve stable defaults: DPR 1.0, backdrop-filter enabled, metrics opt-in.",
    "Touch only the subsystem named by the evidence; no unrelated refactors in the same commit.",
    "Do not modify game code or examples/game-player/assets/game/**.",
]


def build_issue_report(issue: dict, diagnosis: dict, *, run_id: str, scenarios: dict, system: dict,
                       minimization: dict | None, novelty: str, reproducible: bool | None) -> dict:
    first = issue["occurrences"][0]
    f = first["finding"]
    scenario = scenarios[first["scenario_id"]]
    minimal = (minimization or {}).get("scenario") if (minimization or {}).get("reproduced") else None
    loc = dict(diagnosis["location"])
    loc["minimal_json_path"] = _path_in(minimal, f.get("element_id")) if minimal else None
    replay = f"python3 debug/engines/bug_detection/audit.py replay debug/artifacts/audit/latest/issues/{issue['issue_id']}.json"
    hyps = diagnosis["hypotheses"]
    confirmed = any(h["status"] == "confirmed" for h in hyps)
    expected, actual = f.get("expected"), f.get("actual")
    report = {
        "report_version": REPORT_VERSION,
        "issue_id": issue["issue_id"],
        "run_id": run_id,
        "scenario_id": first["scenario_id"],
        "fingerprint": issue["fingerprint"],
        "status": "oracle_conflict" if issue["kind"] == "oracle_conflict" else "failed",
        "novelty": novelty,
        "severity": issue["severity"],
        "confidence": diagnosis["confidence"],
        "classification": {
            "kind": issue["kind"], "subsystem": issue["subsystem"],
            "component_type": f.get("component_type"),
            "component_types": sorted(issue["component_types"]),
            "property": issue.get("property"), "stage": issue["stage"],
        },
        "location": loc,
        "system": {**system, "reference": "Chromium headless (google-chrome), srcdoc iframe at the scenario viewport",
                   "environment": scenario.get("environment")},
        "expected": expected,
        "actual": actual,
        "difference": _difference(f),
        "reproduction": {
            "seed": scenario.get("seed"), "family": scenario.get("family"),
            "steps": _steps(minimal or scenario, f),
            "scenario": scenario, "minimal_scenario": minimal,
            "minimal_html": compile_screen(minimal) if minimal else None,
            "actions": (minimal or scenario).get("actions") or [],
            "command": replay, "minimized": minimal is not None,
            "minimization": None if not minimization else {
                k: minimization.get(k) for k in ("reproduced", "rounds", "start_size", "final_size",
                                                 "one_minimal", "removed", "necessary_conditions", "note")},
            "reproducible": reproducible,
        },
        "evidence": {
            "finding": {k: v for k, v in f.items() if k != "stack"},
            "assertion_id": f.get("assertion_id"),
            "message": f.get("message") or "",
            "consequential_findings": issue.get("consequential_findings", 0),
            "stack": f.get("stack") or [],
            "artifacts": [f"debug/artifacts/audit/latest/issues/{issue['issue_id']}.json",
                          f"debug/artifacts/audit/latest/issues/{issue['issue_id']}.md"],
        },
        "root_cause": {
            "status": "confirmed" if confirmed else "unconfirmed",
            "hypotheses": hyps,
            "alternatives_to_rule_out": [h["statement"] for h in hyps[1:]],
        },
        "investigation": {
            "first_target": _first_target(diagnosis),
            "next_checks": diagnosis["next_checks"],
            "files_to_inspect": diagnosis["files_to_inspect"],
        },
        "fix_requirements": [
            f"NativaX must produce {json.dumps(expected, ensure_ascii=False)[:200]} for "
            f"'{issue.get('property') or issue['kind']}' on {f.get('component_type') or 'the element'} "
            f"in state '{f.get('state')}', as the reference does.",
            "The fix must follow from the confirmed cause; do not special-case the audit ids or values.",
        ],
        "constraints": CONSTRAINTS,
        "regression_tests": [
            "Add the minimal scenario to debug/engines/bug_detection/regressions/ (audit.py promote) so every run replays it.",
            f"Add a package test in the {issue['subsystem']} package that reproduces the minimal case "
            "without Chromium.",
            "Run ./tools/test_all.sh and the visual judge suite.",
        ],
        "acceptance_criteria": [
            f"`{replay}` reports the fingerprint as absent.",
            "No new issue fingerprints in the other regression scenarios (audit.py run --family regression).",
            "Package tests and ./tools/test_all.sh pass.",
        ],
        "verification": {"fix_applied": False, "reproduction_passed": None, "regression_passed": None,
                         "verified_at": None, "command": replay},
        "occurrences": {"scenarios": issue["scenarios"][:200], "count": len(issue["occurrences"]),
                        "families": sorted(x for x in issue["families"] if x)},
    }
    errors = check_report(report)
    if errors:
        raise ValueError(f"report {issue['issue_id']} violates report.schema.json: {errors[:5]}")
    return report


def _path_in(scenario, element_id):
    from .compile import node_by_id
    if not scenario or not element_id:
        return None
    hit = node_by_id(scenario["screen"], element_id)
    return hit[0] if hit else None


def _difference(f):
    a = f.get("actual")
    if isinstance(a, dict) and "delta" in a:
        return {"rect_delta_px": dict(zip(["x", "y", "width", "height"], a["delta"]))}
    if f.get("first_difference"):
        return {"first_event_difference": f["first_difference"]}
    if f.get("expected") != a:
        return {"expected": f.get("expected"), "actual": a}
    return None


def _steps(scenario, f):
    env = scenario.get("environment") or {}
    steps = [f"Compile the scenario JSON to HTML (debug/engines/bug_detection/nxaudit/compile.py) and load it in NativaXView "
             f"at {env.get('viewport_width', 360)}x{env.get('viewport_height', 640)} CSS px, DPR 1",
             f"Wait {env.get('wait_ms', 300)} ms of pumped frames and run the shared probe (__nxProbe)"]
    for i, a in enumerate(scenario.get("actions") or []):
        steps.append(f"Action {i}: {json.dumps(a, ensure_ascii=False)}; wait and probe again")
    steps.append(f"Compare state '{f.get('state')}' of element '{f.get('element_id')}' "
                 f"({f.get('json_path')}) property '{f.get('property')}' with the Chromium probe")
    return steps


def _first_target(diagnosis):
    loc = diagnosis["location"]
    if loc.get("source_file"):
        return f"{loc['source_file']}:{loc['line']} ({loc.get('symbol')}), from the exception stack"
    files = diagnosis["files_to_inspect"]
    if files:
        f = files[0]
        return f"{f['file']}{':' + str(f['line']) if f.get('line') else ''} ({f['basis']}; not a confirmed cause)"
    return None


def llm_brief(report: dict) -> str:
    """Investigation instructions to hand to an LLM, built from the report."""
    c = report["classification"]
    loc = report["location"]
    rep = report["reproduction"]
    lines = [
        f"# {report['issue_id']} — {c['kind']} in {c['subsystem']} ({report['severity']})",
        "",
        f"Run `{report['run_id']}` · commit `{report['system']['git_commit']}`"
        f"{' (dirty tree)' if report['system']['git_dirty'] else ''} · novelty: **{report['novelty']}** · "
        f"confidence: **{report['confidence']['level']}** ({report['confidence']['basis']}).",
        "",
        "## Problem",
        "",
        f"{report['evidence']['message']}. Component `{c['component_type']}`, property `{c['property']}`, "
        f"stage `{c['stage']}`. Seen in {report['occurrences']['count']} occurrence(s) across "
        f"{len(report['occurrences']['scenarios'])} scenario(s); component types: "
        f"{', '.join(c.get('component_types') or []) or '—'}.",
        "",
        "## Initial location",
        "",
        f"- Element `{loc['element_id']}` at `{loc['json_path']}`"
        + (f" (minimal case: `{loc['minimal_json_path']}`)" if loc.get("minimal_json_path") else ""),
    ]
    if loc.get("source_file"):
        lines.append(f"- Code: `{loc['source_file']}:{loc['line']}` `{loc['symbol']}` — {loc['basis']}.")
    else:
        lines.append("- Code: not identified by a trace. Last confirmed stage: "
                     f"`{c['stage']}` (the differential isolated it). Files below are search hits only.")
    lines += ["", "## Reproduction", ""]
    lines += [f"{i + 1}. {s}" for i, s in enumerate(rep["steps"])]
    lines += ["", f"Command: `{rep['command']}`", ""]
    if rep.get("minimization"):
        m = rep["minimization"]
        lines.append(f"Minimized: {m.get('start_size')} → {m.get('final_size')} units in {m.get('rounds')} "
                     f"round(s); 1-minimal: {m.get('one_minimal')}.")
        if m.get("necessary_conditions"):
            lines.append("Necessary conditions (removing any one loses the defect):")
            lines += [f"- {n['description']}" for n in m["necessary_conditions"][:12]]
        lines.append("")
    lines += ["Minimal JSON:", "", "```json",
              json.dumps(rep["minimal_scenario"] or rep["scenario"], indent=2, ensure_ascii=False)[:6000],
              "```", ""]
    if rep.get("minimal_html"):
        lines += ["Compiled HTML:", "", "```html", rep["minimal_html"][:4000], "```", ""]
    lines += ["## Evidence", "",
              f"- Expected (reference): `{json.dumps(report['expected'], ensure_ascii=False)[:400]}`",
              f"- Observed (NativaX): `{json.dumps(report['actual'], ensure_ascii=False)[:400]}`",
              f"- Difference: `{json.dumps(report['difference'], ensure_ascii=False)[:400]}`",
              f"- Consequential findings attributed to this issue: {report['evidence']['consequential_findings']}",
              ""]
    if report["evidence"]["stack"]:
        lines += ["Stack (top frames):", "", "```", *report["evidence"]["stack"][:8], "```", ""]
    lines += ["## Investigation (in order)", ""]
    if report["investigation"]["first_target"]:
        lines.append(f"1. Start at {report['investigation']['first_target']}.")
    for i, check in enumerate(report["investigation"]["next_checks"], start=2):
        lines.append(f"{i}. {check}")
    if report["investigation"]["files_to_inspect"]:
        lines += ["", "Files to inspect (evidence basis in brackets):", ""]
        lines += [f"- `{f['file']}{':' + str(f['line']) if f.get('line') else ''}` [{f['basis']}]"
                  + (f" — `{f['match']}`" if f.get("match") else "")
                  for f in report["investigation"]["files_to_inspect"]]
    lines += ["", "## Hypotheses (ordered by evidence, none confirmed unless stated)", ""]
    for h in report["root_cause"]["hypotheses"]:
        lines.append(f"- **[{h['status']}]** {h['statement']}")
        lines += [f"  - for: {e}" for e in h["evidence_for"]]
        lines += [f"  - against: {e}" for e in h["evidence_against"]]
    lines += ["", "## Limits", ""] + [f"- {c}" for c in report["constraints"]]
    lines += ["", "## Fix", ""] + [f"- {r}" for r in report["fix_requirements"]]
    lines += ["", "## Validation", ""] + [f"- {a}" for a in report["acceptance_criteria"]]
    lines += ["", "## Regression", ""] + [f"- {r}" for r in report["regression_tests"]]
    lines.append("")
    return "\n".join(lines)


def summary_markdown(summary: dict, reports: list[dict]) -> str:
    m = summary["metrics"]
    lines = [
        "# NativaX — auditoría de interfaces JSON",
        "",
        f"**Run:** `{summary['run_id']}` · commit `{summary['system']['git_commit']}`"
        f"{' (árbol con cambios)' if summary['system']['git_dirty'] else ''} · "
        f"{summary['started_at']} → {summary['finished_at']}",
        "",
        "Pantallas JSON compiladas a HTML y ejecutadas en NativaX y en Chromium (referencia). "
        "Chromium es referencia, no verdad absoluta: los conflictos de oráculo no cuentan como defectos.",
        "",
        "## Resumen",
        "",
        "| Métrica | Valor |",
        "|---|---:|",
    ]
    for key, label in [("generated", "Generados"), ("rejected", "Rechazados por el esquema"),
                       ("rejected_expected", "…de ellos negativos deliberados"),
                       ("executed", "Ejecutados"), ("verified", "Verificados (ambos motores)"),
                       ("passed", "Sin defectos"), ("failed", "Con defectos"),
                       ("inconclusive", "No concluyentes"), ("unique_issues", "Defectos únicos"),
                       ("new_issues", "Nuevos"), ("regressions", "Regresiones"),
                       ("reproducible", "Reproducidos al re-ejecutar"),
                       ("minimized", "Minimizados"), ("findings", "Hallazgos brutos"),
                       ("duplicates_grouped", "Duplicados agrupados"),
                       ("oracle_conflicts", "Conflictos de oráculo")]:
        lines.append(f"| {label} | {m.get(key, 0)} |")
    lines += [f"| Tiempo total | {m.get('wall_s', 0):.1f} s |",
              f"| Defectos únicos por minuto | {m.get('issues_per_minute', 0):.2f} |",
              f"| RSS máx. del arnés NativaX | {m.get('max_rss_mb') or '—'} MB |", ""]
    cov = summary["coverage"]
    lines += ["## Cobertura", "", "| Dimensión | Generada | Ejecutada | Verificada | Universo |",
              "|---|---:|---:|---:|---:|"]
    for dim, row in cov.items():
        lines.append(f"| {dim} | {row['generated']} | {row['executed']} | {row['verified']} | {row.get('universe') or '—'} |")
    lines += ["", "## Estrategias (mismo presupuesto por ronda)", "",
              "| Familia | Ejecutados | ms medio | Defectos nuevos (primera vez) | Defectos/escenario |",
              "|---|---:|---:|---:|---:|"]
    for fam, row in sorted(summary["strategies"].items()):
        lines.append(f"| {fam} | {row['executed']} | {row['mean_ms']:.0f} | {row['first_found']} | "
                     f"{row['yield']:.3f} |")
    lines += ["", "## Defectos", "",
              "| Issue | Sev. | Tipo | Subsistema | Componente | Propiedad | Ocurr. | Min. | Repro | Novedad |",
              "|---|---|---|---|---|---|---:|---|---|---|"]
    for r in reports:
        c = r["classification"]
        rep = r["reproduction"]
        lines.append(f"| [{r['issue_id']}](issues/{r['issue_id']}.md) | {r['severity']} | {c['kind']} | "
                     f"{c['subsystem']} | {', '.join(c['component_types'][:3]) or '—'} | {c['property'] or '—'} | "
                     f"{r['occurrences']['count']} | {'sí' if rep['minimized'] else 'no'} | "
                     f"{'—' if rep['reproducible'] is None else 'sí' if rep['reproducible'] else 'no'} | "
                     f"{r['novelty']} |")
    if summary.get("limitations"):
        lines += ["", "## Limitaciones de esta ejecución", ""] + [f"- {x}" for x in summary["limitations"]]
    lines.append("")
    return "\n".join(lines)


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False, default=_default))
    tmp.replace(path)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)


def _default(value):
    if isinstance(value, set):
        return sorted(value)
    raise TypeError(type(value))

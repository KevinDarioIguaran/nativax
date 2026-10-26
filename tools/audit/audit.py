#!/usr/bin/env python3
"""NativaX JSON interface audit — command line.

  python3 tools/audit/audit.py run --budget 200 --batch 40 --seed 1
  python3 tools/audit/audit.py benchmark --budget 80      # deliberate faults
  python3 tools/audit/audit.py self-check --budget 40     # Chromium vs Chromium
  python3 tools/audit/audit.py reanalyze .audit/runs/<run>   # oracles only
  python3 tools/audit/audit.py generate --family random --count 20 --out DIR
  python3 tools/audit/audit.py validate FILE...
  python3 tools/audit/audit.py html SCENARIO.json
  python3 tools/audit/audit.py replay .audit/latest/issues/NX-XXXXXXXX.json
  python3 tools/audit/audit.py verify NX-XXXXXXXX
  python3 tools/audit/audit.py promote NX-XXXXXXXX
  python3 tools/audit/audit.py catalog

Outputs: .audit/runs/<run>/ (results.jsonl, summary.{json,md}, metrics.json,
coverage.json, issues/NX-*.{json,md}), copied to .audit/latest/, and
progress/reports/audit-latest.md.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from nxaudit import faults  # noqa: E402
from nxaudit import generate as gen  # noqa: E402
from nxaudit.catalog import catalog_document, css_support  # noqa: E402
from nxaudit.compile import compile_screen  # noqa: E402
from nxaudit.execute import run_chrome  # noqa: E402
from nxaudit.explore import AUDIT, LEDGER, ROOT, Explorer, Runner, git_state  # noqa: E402
from nxaudit.report import write_json, write_text  # noqa: E402
from nxaudit.schema import check_scenario  # noqa: E402


def log(text):
    print(text, flush=True)


def cmd_run(args):
    explorer = Explorer(budget=args.budget, batch=args.batch, seed=args.seed,
                        families=args.families.split(",") if args.families else None,
                        minimize_top=args.minimize_top, reproduce=not args.no_reproduce,
                        time_limit_s=args.time_limit, log=log)
    summary = explorer.run()
    m = summary["metrics"]
    log(json.dumps({k: m[k] for k in ("executed", "verified", "failed", "unique_issues", "minimized",
                                      "reproducible", "wall_s")}))
    return 0


def _fault_runner(work, lg):
    return Runner(work, lg, nativa_fn=faults.faulty_backend(run_chrome), chrome_fn=run_chrome)


def _self_runner(work, lg):
    return Runner(work, lg, nativa_fn=run_chrome, chrome_fn=run_chrome)


def cmd_benchmark(args, self_check=False):
    name = "self-check" if self_check else "benchmark"
    explorer = Explorer(budget=args.budget, batch=args.batch, seed=args.seed, log=log,
                        minimize_top=args.minimize_top, reproduce=True,
                        runner_factory=_self_runner if self_check else _fault_runner,
                        home=AUDIT / name, publish=False,
                        run_id=f"{name}-{datetime.now():%Y%m%dT%H%M%S}-s{args.seed}")
    summary = explorer.run()
    scores = faults.score(explorer.results)
    scores["issues_reported"] = summary["metrics"]["unique_issues"]
    scores["minimized"] = summary["metrics"]["minimized"]
    scores["run_id"] = explorer.run_id
    scores["mode"] = name
    write_json(explorer.out / f"{name}.json", scores)
    lines = [f"# NativaX audit — {name}", "", f"Run `{explorer.run_id}`, {summary['metrics']['executed']} "
             "scenarios. SUT = independent Chromium run" + ("" if self_check else " + injected faults") + ".", "",
             "| Fault | Injected | Detected | Localized / localizable |", "|---|---:|---:|---:|"]
    for fid, row in scores["faults"].items():
        lines.append(f"| {fid} — {faults.FAULTS[fid][0]} | {row['injected']} | {row['detected']} | {row['localized']}/{row['localizable']} |")
    lines += ["", f"- Detection rate: **{scores['detection_rate']}**",
              f"- Localization rate (of detected): **{scores['localization_rate']}**",
              f"- Clean scenarios with findings (false-positive scenario rate): "
              f"**{scores['clean_scenarios_with_findings']}/{scores['clean_scenarios']}** "
              f"({scores['false_positive_scenario_rate']})",
              f"- Unexpected primary findings: **{scores['unexpected_primary_findings']}**",
              f"- Issues reported: {scores['issues_reported']} · minimized: {scores['minimized']}", ""]
    write_text(explorer.out / f"{name}.md", "\n".join(lines))
    write_text(ROOT / "progress" / "reports" / f"audit-{name}-latest.md", "\n".join(lines))
    log(json.dumps({k: v for k, v in scores.items() if k != "faults"}))
    return 0


def cmd_reanalyze(args):
    run_dir = Path(args.run_dir)
    explorer = Explorer(budget=0, seed=0, minimize_top=args.minimize_top, reproduce=args.reproduce,
                        log=log, run_id=f"{run_dir.name}-re{datetime.now():%H%M%S}")
    explorer.reanalyze(run_dir)
    return 0


def cmd_generate(args):
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    written = 0
    for i in range(args.count):
        s = gen.regenerate(args.family, args.seed + i)
        errors = check_scenario(s)
        if errors and s["category"] != "schema_invalid":
            log(f"{s['scenario_id']}: {errors[:3]}")
            continue
        (out / f"{s['scenario_id']}.json").write_text(json.dumps(s, indent=2, ensure_ascii=False))
        written += 1
    log(f"{written} scenarios in {out}")
    return 0


def cmd_validate(args):
    bad = 0
    for name in args.files:
        data = json.loads(Path(name).read_text())
        errors = check_scenario(data)
        if errors:
            bad += 1
            log(f"INVALID {name}")
            for e in errors[:20]:
                log(f"  {e}")
        else:
            log(f"ok      {name}")
    return 1 if bad else 0


def cmd_html(args):
    print(compile_screen(json.loads(Path(args.file).read_text())))
    return 0


def _load_issue(ref: str) -> dict:
    path = Path(ref)
    if not path.exists():
        path = AUDIT / "latest" / "issues" / f"{ref}.json"
    return json.loads(path.read_text())


def _replay(report: dict, work_name: str):
    runner = Runner(AUDIT / "replay" / work_name, log)
    cases = [report["reproduction"]["scenario"]]
    if report["reproduction"].get("minimal_scenario"):
        cases.append(report["reproduction"]["minimal_scenario"])
    fps = runner.fingerprints(cases)
    return {s["scenario_id"]: report["fingerprint"] in fps.get(s["scenario_id"], set()) for s in cases}


def cmd_replay(args):
    report = _load_issue(args.issue)
    present = _replay(report, report["issue_id"])
    for sid, hit in present.items():
        log(f"{'PRESENT' if hit else 'absent '}  {report['fingerprint'][:80]}  in {sid}")
    return 1 if any(present.values()) else 0


def cmd_verify(args):
    path = AUDIT / "latest" / "issues" / f"{args.issue}.json"
    report = json.loads(path.read_text())
    present = _replay(report, f"verify-{args.issue}")
    reproduction_passed = not any(present.values())
    regression_passed = None
    regressions = gen.regressions()
    if regressions:
        runner = Runner(AUDIT / "replay" / f"verify-{args.issue}-regressions", log)
        fps = runner.fingerprints(regressions)
        ledger = json.loads(LEDGER.read_text()) if LEDGER.exists() else {}
        fixed = {v["fingerprint"] for k, v in ledger.items() if v.get("status") == "fixed"}
        reappeared = [sid for sid, f in fps.items() if f & fixed]
        regression_passed = not reappeared
        if reappeared:
            log(f"regressions: previously fixed fingerprints reappeared in {reappeared}")
    report["verification"] = {"fix_applied": reproduction_passed, "reproduction_passed": reproduction_passed,
                              "regression_passed": regression_passed,
                              "verified_at": datetime.now().isoformat(timespec="seconds"),
                              "command": report["verification"]["command"], **git_state()}
    write_json(path, report)
    if reproduction_passed and regression_passed is not False:
        ledger = json.loads(LEDGER.read_text()) if LEDGER.exists() else {}
        if args.issue in ledger:
            ledger[args.issue]["status"] = "fixed"
            ledger[args.issue]["fixed_at"] = report["verification"]["verified_at"]
            write_json(LEDGER, ledger)
    log(json.dumps(report["verification"]))
    return 0 if reproduction_passed and regression_passed is not False else 1


def cmd_promote(args):
    report = _load_issue(args.issue)
    case = report["reproduction"].get("minimal_scenario") or report["reproduction"]["scenario"]
    case = dict(case)
    case["family"] = "regression"
    case["source"] = {**case.get("source", {}), "kind": "regression"}
    case["objective"] = f"regression for {report['issue_id']}: {report['evidence']['message'][:160]}"
    dest = gen.REGRESSIONS / f"{report['issue_id']}.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    errors = check_scenario(case)
    if errors:
        log(f"cannot promote, scenario invalid: {errors[:3]}")
        return 1
    dest.write_text(json.dumps(case, indent=2, ensure_ascii=False) + "\n")
    log(f"regression scenario written: {dest.relative_to(ROOT)}")
    return 0


def cmd_catalog(_args):
    try:
        support = css_support()
    except Exception as error:  # noqa: BLE001 - report why the check could not run
        log(f"nativa_css support check unavailable: {error}")
        support = None
    doc = catalog_document(support)
    write_json(AUDIT / "catalog.json", doc)
    unparsed = [p for p, v in doc["properties"].items() if v["nativa_css_parses"] is False]
    log(f"{len(doc['components'])} components, {len(doc['properties'])} properties; "
        f"not parsed by nativa_css: {unparsed or 'none'} -> .audit/catalog.json")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--budget", type=int, default=200)
    r.add_argument("--batch", type=int, default=40)
    r.add_argument("--seed", type=int, default=1)
    r.add_argument("--families")
    r.add_argument("--minimize-top", type=int, default=5)
    r.add_argument("--time-limit", type=float)
    r.add_argument("--no-reproduce", action="store_true")
    for name in ("benchmark", "self-check"):
        b = sub.add_parser(name)
        b.add_argument("--budget", type=int, default=80)
        b.add_argument("--batch", type=int, default=40)
        b.add_argument("--seed", type=int, default=7)
        b.add_argument("--minimize-top", type=int, default=3)
    ra = sub.add_parser("reanalyze")
    ra.add_argument("run_dir")
    ra.add_argument("--minimize-top", type=int, default=0)
    ra.add_argument("--reproduce", action="store_true")
    g = sub.add_parser("generate")
    g.add_argument("--family", required=True, choices=sorted(gen.FAMILIES))
    g.add_argument("--count", type=int, default=10)
    g.add_argument("--seed", type=int, default=0)
    g.add_argument("--out", required=True)
    v = sub.add_parser("validate")
    v.add_argument("files", nargs="+")
    h = sub.add_parser("html")
    h.add_argument("file")
    for name in ("replay", "verify", "promote"):
        x = sub.add_parser(name)
        x.add_argument("issue")
    sub.add_parser("catalog")
    args = p.parse_args(argv)
    return {"run": cmd_run, "benchmark": cmd_benchmark,
            "self-check": lambda a: cmd_benchmark(a, self_check=True),
            "reanalyze": cmd_reanalyze, "generate": cmd_generate, "validate": cmd_validate, "html": cmd_html, "replay": cmd_replay,
            "verify": cmd_verify, "promote": cmd_promote, "catalog": cmd_catalog}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())

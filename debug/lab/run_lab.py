#!/usr/bin/env python3
"""Run the NativaX laboratory.

Examples::

    python3 debug/lab/run_lab.py --all
    python3 debug/lab/run_lab.py --section 1
    python3 debug/lab/run_lab.py --section 1 --filter html.00
    python3 debug/lab/run_lab.py --list
    python3 debug/lab/run_lab.py --all --strict --min-per-section 100

The runner bootstraps the environment automatically when binaries are missing
(disable with ``--no-bootstrap``). Results are written to
``debug/reports/lab/``; per-run artifacts stay in ``debug/artifacts/lab/``
(git-ignored).

Exit codes: 0 all cases passed (blocked allowed unless --strict),
1 assertion failures/errors, 2 environment/bootstrap failure,
3 a requested section has fewer cases than --min-per-section.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEBUG = HERE.parent
ROOT = DEBUG.parent
for path in (str(DEBUG), str(HERE)):
    if path not in sys.path:
        sys.path.insert(0, path)

import harness  # noqa: E402
from harness import Lab, registered, run_section, summarize, write_reports  # noqa: E402

HISTORY_DIR = DEBUG / "history"
if str(HISTORY_DIR) not in sys.path:
    sys.path.insert(0, str(HISTORY_DIR))
try:
    import history as history_mod  # noqa: E402
except Exception:  # pragma: no cover
    history_mod = None


def ensure_environment(auto: bool) -> bool:
    if (harness.BUILD / "nativax-debug").exists() and (harness.BUILD / "nativax-runtime").exists():
        return True
    if not auto:
        print("build/nativax-* missing; run python3 debug/bootstrap.py", file=sys.stderr)
        return False
    print("[lab] binaries missing, running debug/bootstrap.py ...", flush=True)
    r = subprocess.run([sys.executable, str(DEBUG / "bootstrap.py")])
    return r.returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="run every registered section")
    ap.add_argument("--section", type=int, action="append", default=[],
                    help="section number (repeatable)")
    ap.add_argument("--list", action="store_true", help="list sections and case counts")
    ap.add_argument("--filter", default="", help="substring filter on case id or name")
    ap.add_argument("--strict", action="store_true", help="treat blocked as failure")
    ap.add_argument("--min-per-section", type=int, default=0,
                    help="fail when a section has fewer registered cases than this")
    ap.add_argument("--json", action="store_true", help="print the summary JSON")
    ap.add_argument("--no-history", action="store_true", help="do not append a history snapshot")
    ap.add_argument("--no-report", action="store_true", help="do not write report files")
    ap.add_argument("--no-bootstrap", action="store_true",
                    help="never invoke bootstrap automatically")
    ap.add_argument("--verbose", action="store_true", help="print every case")
    ap.add_argument("--no-responsive", action="store_true",
                    help="skip the 50px responsive sweep (faster, debugging only)")
    ap.add_argument("--responsive-tolerance", type=float, default=1.0,
                    help="allowed overflow in pixels for the responsive sweep")
    args = ap.parse_args()

    harness.load_sections()

    if args.list:
        rows = []
        for sec in sorted(harness.REGISTRY):
            cases = registered(sec)
            rows.append({"section": sec,
                         "cases": len(cases),
                         "prefixes": sorted({c.cid.split(".")[0] for c in cases})})
        print(json.dumps(rows, indent=2))
        return 0

    if not args.all and not args.section:
        ap.error("choose --all or --section N")

    if not ensure_environment(not args.no_bootstrap):
        return 2

    sections = sorted(harness.REGISTRY) if args.all else sorted(set(args.section))
    if not sections:
        print("no sections registered", file=sys.stderr)
        return 2

    short = [(s, len(registered(s))) for s in sections
             if len(registered(s)) < args.min_per_section]
    if short:
        for s, n in short:
            print(f"[lab] section {s} has {n} cases, required {args.min_per_section}",
                  file=sys.stderr)
        return 3

    lab = Lab(jobs=1, responsive=not args.no_responsive)
    started = time.time()
    all_results = []
    for sec in sections:
        cases = registered(sec)
        if not cases:
            print(f"[lab] section {sec}: no cases registered", file=sys.stderr)
            continue
        print(f"[lab] section {sec}: {len(cases)} cases", flush=True)
        t0 = time.time()
        results = run_section(lab, sec, name_filter=args.filter)
        all_results.extend(results)
        s = summarize(results)
        print(f"[lab] section {sec}: pass={s['pass']} fail={s['fail']} "
              f"blocked={s['blocked']} error={s['error']} "
              f"({time.time() - t0:.1f}s)", flush=True)
        for r in results:
            if args.verbose or r.status != "pass":
                print(f"  {r.status.upper():7s} {r.cid} {r.name}"
                      + (f" — {r.message}" if r.message else ""))
        if not args.no_report:
            write_reports(results, label=f"section-{sec:02d}")

    total = summarize(all_results)
    elapsed = time.time() - started
    print(f"[lab] total: {total['total']} cases, pass={total['pass']} "
          f"fail={total['fail']} blocked={total['blocked']} "
          f"error={total['error']} in {elapsed:.1f}s", flush=True)
    if not args.no_report:
        write_reports(all_results, label="latest",
                      extra={"elapsed_seconds": round(elapsed, 2),
                             "sections": sections})
    if args.json:
        print(json.dumps({"summary": total, "elapsed_seconds": round(elapsed, 2)},
                         indent=2))

    if history_mod is not None and not args.no_history and all_results:
        try:
            cmd = " ".join(sys.argv)
            path = history_mod.save_run(
                all_results, sections=sections, elapsed=elapsed,
                command=cmd, label=f"section-{','.join(str(s) for s in sections)}")
            print(f"[lab] history snapshot: {path.relative_to(ROOT)}", flush=True)
            print(f"[lab] ai digest: {ROOT / 'debug' / 'history' / 'ai_digest.json'}", flush=True)
        except Exception as exc:  # noqa: BLE001
            print(f"[lab] history snapshot failed: {exc}", file=sys.stderr)

    if total["fail"] or total["error"]:
        return 1
    if args.strict and total["blocked"]:
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except harness.LabError as exc:
        print(f"[lab] environment error: {exc}", file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        sys.exit(130)

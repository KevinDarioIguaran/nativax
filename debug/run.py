#!/usr/bin/env python3
"""NativaX debug tooling — one entry point.

    python3 debug/run.py                    # every Python test under debug/
    python3 debug/run.py test storage       # only the tests matching "storage"
    python3 debug/run.py storage visual     # list the archived runs of an area
    python3 debug/run.py verify visual <run_id>        # integrity of an archived run
    python3 debug/run.py compare visual <old> <new>    # improved/regressed/... (--record)
    python3 debug/run.py llm                # pre-analyzed minified pack for LLMs -> debug/artifacts/llm
    python3 debug/run.py context brief      # compact AI context projection
    python3 debug/run.py gate --json        # engines receive their own flags
    python3 debug/run.py list               # known commands

The default command is `test`. Dart suites live in ./tools/test_all.sh.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEBUG = ROOT / "debug"

# Anything run through this launcher is invoked with its own arguments.
ENGINES = {
    "context": "logic/context.py",
    "compare": "logic/compare_runs.py",
    "llm": "logic/llm/pack.py",
    "gate": "engines/quality_gate/quality_gate.py",
    "audit": "engines/bug_detection/audit.py",
    "recommend": "engines/recommendations/recommend.py",
    "gui": "engines/performance/gui/perf_gui.py",
}


def _tests(pattern: str | None) -> list[Path]:
    found = sorted(p for p in DEBUG.rglob("test_*.py")
                   if "__pycache__" not in p.parts)
    if pattern:
        found = [p for p in found if pattern in str(p.relative_to(ROOT))]
    return found


def _cmd_test(pattern: str | None) -> int:
    files = _tests(pattern)
    if not files:
        print(f"no test file matches {pattern!r}")
        return 64
    failed = []
    for path in files:
        print(f"=== {path.relative_to(ROOT)} ===", flush=True)
        code = subprocess.run([sys.executable, str(path)], cwd=ROOT).returncode
        if code != 0:
            failed.append(path)
    print(f"{len(files) - len(failed)}/{len(files)} test files OK")
    for path in failed:
        print(f"FAILED {path.relative_to(ROOT)}")
    return 1 if failed else 0


def _cmd_list() -> int:
    print("tests:   python3 debug/run.py test [pattern]")
    print("storage: python3 debug/run.py storage <area>")
    print("verify:  python3 debug/run.py verify <area> <run_id>")
    print("context: python3 debug/run.py context [inventory|runs|conformance|docs|brief|measure|index]")
    for name in ENGINES:
        print(f"{name:<8} python3 debug/run.py {name} [args...]")
    return 0


def main(argv: list[str]) -> int:
    args = argv or ["test"]
    head, rest = args[0], args[1:]
    if head in ("-h", "--help"):
        print(__doc__)
        return 0
    if head == "list":
        return _cmd_list()
    if head == "test":
        return _cmd_test(rest[0] if rest else None)
    if head == "storage":
        if not rest:
            print("usage: run.py storage <area>")
            return 64
        sys.path.insert(0, str(DEBUG / "logic"))
        import storage
        return storage.main(rest[:1])
    if head == "verify":
        if len(rest) != 2:
            print("usage: run.py verify <area> <run_id>")
            return 64
        sys.path.insert(0, str(DEBUG / "logic"))
        import storage
        problems = storage.verify(storage.RUNS_ROOT / rest[0] / rest[1])
        for line in problems:
            print(line)
        print("OK: evidence matches integrity.json" if not problems else f"{len(problems)} problem(s)")
        return 1 if problems else 0
    script = ENGINES.get(head)
    if script is None:
        print(f"unknown command {head!r}; run `python3 debug/run.py list`",
              file=sys.stderr)
        return 64
    return subprocess.run([sys.executable, str(DEBUG / script), *rest]).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

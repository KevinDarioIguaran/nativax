#!/usr/bin/env python3
"""Native debug tooling tests: the SAME storage contract the Dart engines
use (debug/logic/storage.py) exercised end to end by the native runner.

Covers: archive -> manifest schema valid, integrity hashes verify, history
append, lineage superseding, prune. Uses a temp runs_root; the real
debug/artifacts/runs is never touched.
"""
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "debug" / "logic"))
import storage  # noqa: E402


def main() -> int:
    failures = 0

    def check(cond: bool, msg: str) -> None:
        nonlocal failures
        if not cond:
            failures += 1
            print(f"FAIL: {msg}")

    with tempfile.TemporaryDirectory() as tmp:
        runs_root = Path(tmp) / "runs"
        evidence = Path(tmp) / "evidence"
        evidence.mkdir()
        (evidence / "elements.json").write_text('{"children":[]}\n')
        (evidence / "results.json").write_text(
            json.dumps({"engine": "nativax-parse", "cases": 1, "passed": 1,
                        "failed": 0}) + "\n")

        run1 = storage.archive("conformance", evidence, engine="nativax-parse",
                               argv=["parse", "--dataset", "x"],
                               runs_root=runs_root)
        check(run1.is_dir(), "run dir created")
        m1 = storage.load_manifest(run1)
        check(m1 is not None, "manifest loads and validates")
        if m1:
            check(m1["area"] == "conformance" and m1["engine"] == "nativax-parse",
                  "area/engine recorded")
            check(m1["status"] == "completed", "status completed")
            check(m1["git_revision"] is not None, "git revision recorded")
            check(m1["evidence"]["files"] == 2, "both evidence files counted")
        check(storage.verify(run1) == [], "integrity verifies clean")

        # evidence is read-only after archiving
        frozen = run1 / "evidence" / "results.json"
        check(not (frozen.stat().st_mode & 0o222), "evidence frozen read-only")

        # history append stays writable
        h = storage.append_history(run1, "annotation",
                                   {"note": "native run"}, author="test")
        check(h.is_file(), "history entry written")
        entries = storage.history(run1)
        check(len(entries) == 1 and entries[0]["kind"] == "annotation",
              "history readable")

        # second run with the same lineage supersedes the first
        run2 = storage.archive("conformance", evidence, engine="nativax-parse",
                               argv=["parse", "--dataset", "x"],
                               runs_root=runs_root)
        m2 = storage.load_manifest(run2)
        check(m2 is not None and m2["previous_run"] == run1.name,
              "lineage links previous run")
        kinds = [e["kind"] for e in storage.history(run1)]
        check("superseded_by" in kinds, "previous run marked superseded")

        listing = storage.runs("conformance", runs_root)
        check([p.name for p in listing] == [run2.name, run1.name],
              "newest first listing")

        removed = storage.prune("conformance", 1, runs_root)
        check([run1.name] == [p.name for p in removed], "prune removes oldest")
        check(storage.verify(run2) == [], "surviving run still verifies")

    print(f"storage roundtrip: {'OK' if failures == 0 else f'{failures} FAILURES'}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""NativaX native debug tooling — the SAME entry point as debug/run.py.

    python3 native/debug/run.py                    # same default: test
    python3 native/debug/run.py test [pattern]
    python3 native/debug/run.py storage <area>
    python3 native/debug/run.py verify <area> <run_id>
    python3 native/debug/run.py compare <area> <old> <new>
    python3 native/debug/run.py context ...
    python3 native/debug/run.py llm | gate | audit | recommend | gui
    python3 native/debug/run.py parse [--dataset DIR] [--css F]...
    python3 native/debug/run.py list

Every command except `parse` and `test` is delegated verbatim to
`debug/run.py`, so the engines, storage, manifests, integrity, history,
llm pack and context behave identically. `test` runs the native tooling
tests + ctest and then the SAME shared debug suite. `parse` is the native
engine: it runs the C pipeline over the shared datasets and archives into
the SAME immutable storage (debug/artifacts/runs/<area>/<run_id>/) with
engine "nativax-parse".
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]   # repo root (this branch: repo root == native impl root)
DEBUG = ROOT / "debug"
NATIVE = ROOT                                # repo root contains src/, include/, assets/
SHARED = DEBUG / "run.py"
HERE = Path(__file__).resolve()
ARTIFACTS = DEBUG / "artifacts"
CASES_DEFAULT = DEBUG / "cases"              # WPT validation dataset absent on this branch


def _shared_exists() -> bool:
    """A distinct shared entry point (the pre-split layout) exists.

    On this branch the wrapper IS debug/run.py, so SHARED resolves to this
    very file: delegating used to re-run ourselves with the same arguments
    and `run.py test` recursed forever (one child process per level) instead
    of finishing. Skip delegation when the target is us.
    """
    return SHARED.exists() and SHARED.resolve() != HERE


def _delegate(argv: list[str]) -> int:
    """Run the shared debug entry point with the same arguments."""
    if not _shared_exists():
        print(f"shared debug entry point not present (or is this same file): {SHARED}",
              file=sys.stderr)
        return 127
    return subprocess.run([sys.executable, str(SHARED), *argv]).returncode


def ensure_binaries(build_dir: Path) -> Path:
    exe = build_dir / "nativax-debug"
    if not exe.exists():
        subprocess.run(["cmake", "-S", str(NATIVE), "-B", str(build_dir),
                        "-G", "Ninja", "-DCMAKE_BUILD_TYPE=RelWithDebInfo"],
                       check=True)
        subprocess.run(["cmake", "--build", str(build_dir), "-j"], check=True)
    return exe


def _cmd_test(pattern: str | None) -> int:
    failed: list[str] = []
    # native tooling tests, same test_*.py convention as debug/**
    files = sorted(p for p in (NATIVE / "debug").rglob("test_*.py")
                   if "__pycache__" not in p.parts)
    if pattern:
        files = [p for p in files if pattern in str(p.relative_to(ROOT))]
    for path in files:
        print(f"=== {path.relative_to(ROOT)} ===", flush=True)
        if subprocess.run([sys.executable, str(path)], cwd=ROOT).returncode != 0:
            failed.append(str(path.relative_to(ROOT)))
    # the C unit suite the native tooling depends on
    exe = ensure_binaries(NATIVE / "build")
    code = subprocess.run(["ctest", "--test-dir", str(exe.parent),
                           "--output-on-failure"]).returncode
    if code != 0:
        failed.append("native/build (ctest)")
    # the SAME shared suite debug/run.py test runs (when present on this branch)
    if _shared_exists():
        shared_code = _delegate(["test"] + ([pattern] if pattern else []))
        if shared_code not in (0, 64):  # 64 = no shared test matches the pattern
            failed.append("debug/ (shared suite)")
    total = len(files) + 1
    print(f"{total - len(failed)}/{total} test groups OK")
    for name in failed:
        print(f"FAILED {name}")
    return 1 if failed else 0


def _cmd_parse(args: list[str]) -> int:
    dataset = Path(CASES_DEFAULT)
    css_files: list[Path] = []
    archive = True
    it = iter(args)
    for a in it:
        if a == "--dataset":
            dataset = Path(next(it))
        elif a == "--css":
            css_files.append(Path(next(it)))
        elif a == "--no-archive":
            archive = False
        else:
            print(f"unknown flag {a!r}", file=sys.stderr)
            return 64
    if not dataset.is_absolute():
        dataset = ROOT / dataset
    exe = ensure_binaries(NATIVE / "build")

    evidence = ARTIFACTS / "native-parse" / "latest"
    if evidence.exists():
        import shutil
        shutil.rmtree(evidence)
    evidence.mkdir(parents=True)

    cases = sorted(dataset.rglob("*.html"))
    if not cases:
        print(f"no html cases under {dataset}", file=sys.stderr)
        return 64
    results = []
    for html in cases:
        rel = html.relative_to(dataset)
        out = evidence / rel.parent / rel.stem
        out.mkdir(parents=True, exist_ok=True)
        cmd = [str(exe), "--html", str(html), "--out", str(out)]
        page_css = css_files or sorted(html.parent.glob("*.css"))
        for c in page_css:
            cmd += ["--css", str(c)]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        ok = proc.returncode == 0
        entry = {"case": rel.as_posix(), "ok": ok,
                 "error": (proc.stderr.strip() or None) if not ok else None}
        if ok:
            summary = json.loads((out / "summary.json").read_text())
            (out / "elements.json").write_text(
                (out / "dom.json").read_text())  # same payload, Dart's name
            entry.update(summary)
        results.append(entry)
        print(f"{'ok  ' if ok else 'FAIL'} {rel.as_posix()}")
    passed = sum(1 for r in results if r["ok"])
    (evidence / "results.json").write_text(json.dumps(
        {"engine": "nativax-parse", "cases": len(results), "passed": passed,
         "failed": len(results) - passed, "results": results}, indent=2) + "\n")
    print(f"{passed}/{len(results)} cases parsed")
    if archive:
        try:
            import storage  # noqa: E402  (shared, unmodified)

            run_dir = storage.archive(
                "conformance", evidence, engine="nativax-parse",
                argv=sys.argv[1:],
                status="completed" if passed == len(results) else "failed",
                notes="native HTML/CSS parse of the shared WPT validation cases",
            )
            print(f"archived: {run_dir}")
        except ImportError as e:
            print(f"storage module unavailable on this branch: {e}")
            return 2


def _cmd_doctor() -> int:
    checks = []
    def check(name, ok):
        checks.append((name, ok))
        print(f"{'OK  ' if ok else 'FAIL'} {name}")
    import shutil
    check("cmake", shutil.which("cmake") is not None)
    check("ninja", shutil.which("ninja") is not None)
    check("python3", shutil.which("python3") is not None)
    check("docker", shutil.which("docker") is not None)
    check("pkg-config jsc", subprocess.run(
        ["pkg-config", "--exists", "javascriptcoregtk-4.1"]).returncode == 0)
    check("source tree", (NATIVE / "CMakeLists.txt").exists())
    check("build dir", (NATIVE / "build").exists())
    return 0 if all(ok for _, ok in checks) else 1


def _cmd_build() -> int:
    subprocess.run(["cmake", "-S", str(NATIVE), "-B", str(NATIVE / "build"),
                    "-G", "Ninja", "-DCMAKE_BUILD_TYPE=RelWithDebInfo"], check=True)
    return subprocess.run(["cmake", "--build", str(NATIVE / "build"), "-j"]).returncode


def _cmd_validate() -> int:
    required = [
        NATIVE / "CMakeLists.txt",
        NATIVE / "include" / "nativax" / "dom.h",
        NATIVE / "src" / "dom.c",
    ]
    ok = True
    for p in required:
        if not p.exists():
            print(f"MISSING {p}")
            ok = False
    print("validate: OK" if ok else "validate: FAILED")
    return 0 if ok else 1


def _cmd_certify_all() -> int:
    return subprocess.run([sys.executable, str(NATIVE / "debug" / "judges" / "quality_gate" / "gate.py")]).returncode


def _cmd_report() -> int:
    """Measured report: every number printed here is produced by running the
    tool right now (nothing is hardcoded — the previous version quoted
    results from commit 7637bc3 as if they were current)."""
    import time

    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=NATIVE,
                          capture_output=True, text=True)
    print(f"NativaX native baseline ({(head.stdout.strip() or 'unknown')})")

    build = NATIVE / "build"
    if not (build / "CTestTestfile.cmake").exists():
        print("ctest: build not configured (python3 debug/run.py build)")
        return 1
    t0 = time.time()
    proc = subprocess.run(["ctest", "--test-dir", str(build)],
                          capture_output=True, text=True)
    summary = [l.strip() for l in proc.stdout.splitlines() if "tests passed" in l]
    print(f"ctest RelWithDebInfo ({time.time() - t0:.1f}s): "
          f"{summary[-1] if summary else 'no summary'} (exit {proc.returncode})")

    files = sorted(p for p in (DEBUG).rglob("test_*.py")
                   if "__pycache__" not in p.parts)
    ok = 0
    for f in files:
        r = subprocess.run([sys.executable, str(f)], cwd=ROOT,
                           capture_output=True, text=True)
        if r.returncode == 0:
            ok += 1
    print(f"lab tests: {ok}/{len(files)} OK ({', '.join(f.name for f in files)})")

    reports = DEBUG / "reports"
    if reports.exists():
        for p in sorted(reports.rglob("*.json")):
            print(f"  report: {p.relative_to(DEBUG)} ({p.stat().st_size} bytes)")
    print("see debug/reports/phase1-report.md for the full diagnostics summary")
    return 0 if proc.returncode == 0 and ok == len(files) else 1


def main(argv: list[str]) -> int:
    args = argv or ["test"]  # same default as debug/run.py
    head, rest = args[0], args[1:]
    if head in ("-h", "--help"):
        print(__doc__)
        return 0
    if head == "doctor":
        return _cmd_doctor()
    if head == "build":
        return _cmd_build()
    if head == "validate":
        return _cmd_validate()
    if head == "report":
        return _cmd_report()
    if head == "docker-test":
        return subprocess.run([sys.executable, str(NATIVE / "debug" / "common" / "runner" / "run_container.py")]).returncode
    if head == "benchmark":
        return subprocess.run([sys.executable, str(NATIVE / "debug" / "benchmarks" / "workloads" / "parse_benchmark.py")]).returncode
    if head == "validate-manifest":
        return subprocess.run([sys.executable, str(NATIVE / "debug" / "common" / "validation" / "validate_manifest.py")]).returncode
    if head == "discover":
        import json
        m = json.loads((NATIVE / "debug" / "tests" / "manifest.json").read_text())
        print(json.dumps(m, indent=2))
        return 0
    if head == "upstream" and rest and rest[0] == "list":
        try:
            import tomllib
        except Exception:
            print("tomllib unavailable", file=sys.stderr)
            return 1
        data = tomllib.loads((NATIVE / "debug" / "config" / "upstream-suites.toml").read_text())
        for s in data.get("suite", []):
            print(f"{s['id']}: {s['repository']} @ {s.get('revision','latest')} ({s.get('status','unknown')})")
        return 0
    if head == "compare" and "--reference" in rest and "chromium" in rest:
        print("Use debug/common/chromium/capture.py and debug/judges/visual/compare.py")
        return 0
    if head == "compare-history":
        print("No historical baseline comparison implemented yet")
        return 0
    if head == "benchmark":
        return subprocess.run([sys.executable, str(NATIVE / "debug" / "benchmarks" / "workloads" / "parse_benchmark.py")]).returncode
    if head == "certify":
        return subprocess.run([sys.executable, str(NATIVE / "debug" / "judges" / "quality_gate" / "gate.py")]).returncode
    if head == "parse":
        return _cmd_parse(rest)
    if head == "test":
        if "--all" in rest:
            return _cmd_certify_all()
        if "--id" in rest:
            idx = rest.index("--id")
            if idx + 1 < len(rest):
                return _cmd_test_id(rest[idx + 1])
        pattern = None
        if "--suite" in rest:
            idx = rest.index("--suite")
            if idx + 1 < len(rest):
                pattern = rest[idx + 1]
        elif rest and not rest[0].startswith("--"):
            pattern = rest[0]
        return _cmd_test(pattern)
    if head == "list":
        code = _delegate(["list"])
        print("parse:   python3 native/debug/run.py parse "
              "[--dataset DIR] [--css F]... [--no-archive]")
        return code
    # storage, verify, compare, context, llm, gate, audit, recommend, gui:
    # the SAME command on the shared entry point.
    return _delegate(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

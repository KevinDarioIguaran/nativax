# Current task

Phase 1 — Audit and baseline.

Status: in progress

Inspected:
- Source tree: C11 modules under src/ and include/nativax/.
- Build system: CMake + Ninja.
- Tests: 7 CTest suites, 36 unit test functions.
- Debug tooling: debug/run.py launcher.

Changed:
- Created initial debug laboratory skeleton.
- Added configuration, progress, report, schema, and test directories.
- Added debug/README.md and debug/AGENTS.md.
- Added doctor, build, validate, and report commands to debug/run.py.
- Added debug/tests/manifest.json with the 7 verified CTest cases.

Next:
- Import a real upstream HTML parsing subset.
- Implement native screenshot capture and pixel comparison.
- Add performance benchmarks beyond parse smoke.
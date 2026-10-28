---
name: debug-lab-workflow
description: Step-by-step visual debugging workflow for the NativaX debug laboratory. Use when debugging NativaX conformance/lab tests, iterating sections to 100% compatibility, and running full regression checks.
---

# Debug Lab Workflow

## When to use
- Debugging NativaX lab sections or conformance cases.
- Iterating a section until 100% pass/blocked-as-documented.
- Verifying no regressions after a change.

## Steps
1. Run one section: `python3 debug/lab/run_lab.py --section N`.
2. Inspect failures and blockers; reproduce with `build/nativax-debug` and artifacts.
3. Fix the underlying C/JS code; rebuild with CMake.
4. Re-run the same section until 100%.
5. Move to the next section.
6. After 100%, run `python3 debug/lab/run_lab.py --all` and `python3 debug/judges/quality_gate/gate.py`.
7. Update `debug/progress/current-task.md` and commit evidence.

## Guardrails
- Do not weaken assertions or fake results.
- Keep blocked cases only for genuinely unsupported capabilities.
- Preserve historical evidence under `debug/reports/`.

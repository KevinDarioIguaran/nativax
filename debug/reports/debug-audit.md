# Debug laboratory audit

Branch: `native-c-sokol`. Date: 2026-10-28.

## Existing infrastructure

- `nativax-debug` CLI: dumps DOM (TXT/JSON), CSS, layout, display list, summary.json, optional render.png.
- `src/debug_dump.c/h`: DOM/CSS/layout/display-list dumps, stats.
- `src/log.c`: leveled logging.
- `src/platform.c`: crash reporter (backtrace on fatal signals).
- `debug/run.py`: orchestrator (test, parse, verify, compare, context, list, gate, audit, recommend, gui).
- `debug/judges/`: quality gate, visual compare.
- `debug/tests/`: storage roundtrip, screenshot determinism, golden rendering, visual judge.
- `debug/benchmarks/`: parse/render benchmarks, workloads.
- `debug/manifests/`, `debug/schemas/`: manifests and JSON schemas.
- `debug/artifacts/`: immutable runs (gitignored).
- `debug/upstream/`: html5lib tests imported.

## What works

- Dumps: DOM TXT/JSON, CSS, layout, display list, summary.json all generated.
- Crash reporter: backtrace on fatal signals.
- Logging: leveled.
- `debug/run.py`: delegates shared commands; `test` runs Python + ctest.
- Benchmarks: parse/render workloads, `nativax_perf`, `nativax_bench`.
- Visual comparison scripts exist (`debug/judges/visual/compare.py`).
- Golden test policy: missing golden created and must be committed.

## What is incomplete / pending

- Conformance: html5lib/WPT adapters not wired to the C parser; no published pass rates.
- Visual comparison: pixel-diff tooling exists but not integrated into CI as a gate.
- Dependency/license inventory exists (`dependency-map.md`) but not auto-validated.
- Platform builds (Windows/Android/iOS) not validated.
- Hardware-GL measurements not done (only llvmpipe/Xvfb).
- Leak detection dedicated (only ASan).
- FPS presented vs rendered distinction not measured.
- LLM interface evaluation harness not implemented.
- Quality gate does not yet aggregate all suites/artifacts into a single pass/fail.

## Recommendations (ordered)

1. Wire html5lib tokenizer adapter to `nx_html_parse` and publish pass rates.
2. Add pixel-diff gate to CI using existing `debug/judges/visual/compare.py`.
3. Add dedicated leak-detection tests (repeated teardown + RSS tracking).
4. Validate one additional platform (Windows) and document.
5. Measure on hardware GL and update `benchmarks/baseline.json`.

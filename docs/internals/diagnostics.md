# Diagnostics and tracing

NativaX diagnostics are opt-in and evidence-oriented. They are split between
runtime tracing (host environment variables and callbacks) and the external
debug engines (visual, performance, conformance, leaks, security).

## Runtime diagnostics

`NativaXRuntimeConfig` and `NativaXView` expose callbacks:

| Callback | Receives | Use |
|---|---|---|
| `onDiagnostic` | Human-readable host/render warnings | Resource denials, font/stylesheet failures, approximations |
| `onScriptError` | Script/evaluation errors | Page error reporting |
| `onConsole` | `ConsoleMessage` | `console.*`, no-op when omitted |
| `onEngineOverBudget` (runtime) | V8 post-startup heap stop | The view reloads on QuickJS |
| `NativaXDocumentView.onDiagnostic` | Renderer approximations | Unresolved images, paint approximations; deduplicated per mount |

The runtime records `parseErrors` and `scriptErrors` on the runtime object. The
renderer records diagnostics through `onDiagnostic`; it does not throw for a
denied image or an approximate border.

`NativaXView` displays a Flutter error string if creation throws and a spinner
while loading. It does not show a diagnostic panel.

## Environment switches

| Variable | Values | Effect |
|---|---|---|
| `NATIVAX_TRACE_HOST` | `1` | Trace host bridge calls (counts/timing in engines) |
| `NATIVAX_TRACE_JS` | `1` | Trace slow script evaluations; prints engine timing |
| `NATIVAX_TRACE_TIMERS` | `1` | Log timer scheduling/entry timing |
| `NATIVAX_TRACE_GC` | `1` | V8 GC trace |
| `NATIVAX_TRACE_DRAW` | `1` | Renderer draw trace; also enables layout profile |
| `NATIVAX_TRACE_RENDER` | `1` | Alias for draw trace |
| `NATIVAX_RENDER_PROFILE` | `1` | Layout profile buckets |
| `NATIVAX_METRICS` | `1` | Enable game/example metrics overlay and style metrics |
| `NATIVAX_METRICS_FILE` | path | Write game metrics JSON; implies overlay |
| `NATIVAX_METRICS_DIR` | directory | Benchmark script output directory |
| `NATIVAX_METRICS_LABEL` | label | Metrics run label |
| `NATIVAX_NO_STYLE_CACHE` | `1` | Disable computed-style cache for diagnosis |
| `NATIVAX_NO_BACKDROP` | `1` | Disable backdrop blur |
| `NATIVAX_ENGINE` | `quickjs` | Force QuickJS; any other value leaves V8 eligibility |
| `NATIVAX_V8_LIB` | path | V8 cdylib path (default `libnx_v8.so`) |
| `NATIVAX_V8_FLAGS` | string | Build/spike flags (not a page-runtime flag) |
| `NATIVAX_LAYOUT_PROFILE` | `1` | Render benchmark/profile switch; check the harness before relying on it |
| `NATIVAX_FIXED_WINDOW` | `1` | Example window sizing (benchmark/UI harness) |
| `NATIVAX_AUTOSTART` | `1` | Game example autostart |
| `NATIVAX_GAME_DPR` | number | Game example render scale |
| `NATIVAX_GAME_SHOT` | path | Game screenshot output |
| `NATIVAX_SHOT`, `NATIVAX_SHOT_DIR` | path | Screenshot harness output |
| `NATIVAX_PERF_*` | various | Performance suite/harness controls |
| `NATIVAX_BENCH_*` | various | Benchmark harness controls |
| `NATIVAX_GL_H`, `NATIVAX_WASM_H`, `NATIVAX_BRIDGE_H`, `NATIVAX_MIR_H`, `NATIVAX_JIT_H`, `NATIVAX_RUNTIME_INTERNAL_H` | paths | Native build/prototype include paths, not page settings |
| `NATIVAX_JSON`, `NATIVAX_AUDIT_MANIFEST` | path/flag | Audit/test harness controls |

Only `NATIVAX_ENGINE`, `NATIVAX_V8_LIB`, `NATIVAX_TRACE_*`, and the metrics
switches are common for embedding diagnostics. The rest are example/benchmark
controls; do not document them as public API without checking the consumer.

## Debug engines

Run from each engine directory:

```bash
cd debug/engines/compatibility
dart run bin/run_all.dart

cd debug/engines/visual_comparison
dart run bin/visual_check.dart --suite 50projects50days

cd debug/engines/performance
dart run bin/perf.dart run --out ../../../debug/artifacts/perf/latest

cd debug/engines/memory
dart run bin/leaks.dart run --profile quick

cd debug/engines/security
dart run bin/security.dart run --only limits.infinite_loop_interrupted
```

Engine READMEs are canonical for their flags. Do not copy flags between engines
without checking the parser.

## Artifacts

| Type | Canonical path | Tracked? |
|---|---|---|
| Conformance per-test rows | `debug/artifacts/conformance/results/*.jsonl` | No |
| Conformance summary metadata | `debug/artifacts/conformance/results/*.summary.json` | No |
| Immutable engine runs | `debug/artifacts/runs/<area>/<run_id>/` | No |
| Visual/perf/audit generated files | `debug/artifacts/{visual,perf,audit}/` | No |
| Benchmark/leak/security runs | `debug/benchmarks/<area>/<run_id>/` | Yes, selected |
| Convenience latest reports | `progress/reports/*-latest.md` | Yes |
| Context indexes | `debug/artifacts/index/*.jsonl` | No |

`debug/artifacts/` is large (about 1.1 GB in the current workspace) and must be
pruned explicitly. Do not add an automatic cleanup that deletes evidence.

## Context commands

```bash
python3 debug/run.py context brief --budget 2000
python3 debug/run.py context inventory
python3 debug/run.py context runs --area visual
python3 debug/run.py context conformance
python3 debug/run.py context docs
python3 debug/run.py context measure --path docs/README.md
python3 debug/run.py context index
```

These are LLM/agent projections. They do not replace canonical JSONL/manifests.
`brief` is budgeted; `index` writes JSONL indexes under `debug/artifacts/index/`.
Exact token counts are not available because `tiktoken`/`tokenizers` are not
installed; measurements use `estimate:utf8_bytes/4`.

## Reproducing a report

1. Run the engine command from its README.
2. Note date, commit, platform, SDK, engine, and flags.
3. Check `manifest.json` for `run_id`, commit, dirty state, and command.
4. Link the canonical JSON/JSONL/Markdown, not a screenshot or a pasted table.
5. Update `progress/status.md`/`progress/conformance.md` only with the new run.

## Known gaps

- No central structured logger; diagnostics are callbacks/prints.
- Draw traces are text, not a trace-viewer format.
- The latest leak run covered only the control case.
- `*-latest.md` can lag immutable timestamped evidence.
- Some benchmark scripts still write Spanish Markdown headings; the numbers and
  JSON are canonical.
- A skipped V8 test is not V8 coverage.

## Related

- [`../debugging.md`](../debugging.md)
- [`../benchmarks.md`](../benchmarks.md)
- [`../testing.md`](../testing.md)
- [`../information-architecture.md`](../information-architecture.md)
- [`../reference/environment-variables.md`](../reference/environment-variables.md)

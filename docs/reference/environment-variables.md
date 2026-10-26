# Environment variables

Environment variables are process-wide. They are not a public configuration API
for every embedding; prefer `NativaXRuntimeConfig` in app code. This page lists
the variables that actually have consumers, grouped by purpose.

## Runtime and engine

| Variable | Values | Consumer | Effect |
|---|---|---|---|
| `NATIVAX_ENGINE` | `quickjs` or other | `createDefaultJavaScriptEngine` | `quickjs` forces QuickJS. Any other value does **not** force V8; it only keeps V8 eligible. |
| `NATIVAX_V8_LIB` | path | `V8Engine` | V8 cdylib path; default `libnx_v8.so` |
| `NATIVAX_TRACE_HOST` | `1` | `nativa_js`, `web_ops` | Host bridge call tracing/timing |
| `NATIVAX_TRACE_JS` | `1` | `nativa_js` | Slow script evaluation trace |
| `NATIVAX_TRACE_TIMERS` | `1` | `TimerHost` | Timer scheduling/entry trace |
| `NATIVAX_TRACE_GC` | `1` | V8 engine | GC trace |
| `NATIVAX_TRACE_DRAW` | `1` | `nativa_render` | Draw trace; enables layout profile |
| `NATIVAX_TRACE_RENDER` | `1` | `nativa_render` | Alias for `NATIVAX_TRACE_DRAW` |
| `NATIVAX_RENDER_PROFILE` | `1` | `LayoutProfile` | Layout profile buckets |
| `NATIVAX_NO_STYLE_CACHE` | `1` | example/benchmark + style engine | Disable style cache |
| `NATIVAX_NO_BACKDROP` | `1` | game example | Disable backdrop blur |

`NATIVAX_ENGINE=v8` is not a selector in `createDefaultJavaScriptEngine`; it
happens to leave V8 eligible. The game example uses it to choose an explicit
`engineFactory`, and `run_v8.sh` sets `NATIVAX_V8_LIB`. In your own app, use
`forceQuickJs`/`engineFactory` rather than relying on the string value.

## Metrics and examples

| Variable | Values | Consumer | Effect |
|---|---|---|---|
| `NATIVAX_METRICS` | `1` | game example, render benchmark | Metrics overlay/metrics-enabled style engine |
| `NATIVAX_METRICS_FILE` | path | game example | Write one JSON metrics object; implies overlay |
| `NATIVAX_METRICS_DIR` | directory | `bench_game_player.sh` | Output directory |
| `NATIVAX_METRICS_LABEL` | string | game example | Run label in metrics |
| `NATIVAX_FIXED_WINDOW` | any set | game Linux runner | Fixed-size window |
| `NATIVAX_AUTOSTART` | `1` | game example | Auto-click start |
| `NATIVAX_GAME_DPR` | number | game example | Render scale/DPR |
| `NATIVAX_GAME_SHOT` | path | game example | Screenshot output |
| `NATIVAX_SHOT` | path | harness | Screenshot output |
| `NATIVAX_SHOT_DIR` | directory | harness | Screenshot directory |
| `NATIVAX_GUI_TOPMOST` | `1` | `debug/engines/performance/gui` | Tk panel always-on-top |

## Benchmark and render harness

| Variable | Values | Consumer | Effect |
|---|---|---|---|
| `NATIVAX_BENCH_FILE` | path | `examples/render-benchmark` | Load HTML from file |
| `NATIVAX_BENCH_HTML` | asset key | render benchmark | Load HTML from asset |
| `NATIVAX_BENCH_ROOT` | directory | render benchmark | `NativaXDirectoryLoader` root |
| `NATIVAX_SCENARIO` | load/mutate/updateall/scroll/resize | render benchmark | Scenario |
| `NATIVAX_TARGET` | selector | render benchmark | Target element |
| `NATIVAX_SCROLL_STEPS` | integer | render benchmark | Scroll steps |
| `NATIVAX_FRAMES_MS` | integer | render benchmark | Hold time |
| `NATIVAX_LAYOUT_PROFILE` | `1` | render benchmark | Layout profile |
| `NATIVAX_JSON` | path | render benchmark | JSON output |
| `NATIVAX_PERF_PAGE` | directory | web-challenge host | Load page from disk |
| `NATIVAX_PERF_OUT` | path | perf probe | Output file; probe skipped without it |
| `NATIVAX_PERF_WIDTH` | number | perf probe | Viewport width (default 800) |
| `NATIVAX_PERF_HEIGHT` | number | perf probe | Viewport height (default 900) |
| `NATIVAX_PERF_IDLE_MS` | integer | perf probe | Idle time |
| `NATIVAX_PERF_TIMEOUT_MS` | integer | perf probe | Timeout (default 60000) |
| `NATIVAX_PERF_SETUP_WAIT` | JS | perf probe | Setup wait expression |
| `NATIVAX_PERF_START` | JS | perf probe | Start expression |
| `NATIVAX_PERF_WAIT` | JS | perf probe | Wait expression |
| `NATIVAX_PERF_READ` | JS | perf probe | Read expression |
| `NATIVAX_PERF_OPS` | JSON | perf probe | Operations |
| `NATIVAX_PERF_NO_SANDBOX` | `1` | container perf | Chromium no-sandbox in container |
| `NATIVAX_FIXED_WINDOW` | any set | game runner | Fixed window (also listed above) |

These are harness controls. Changing them does not change the runtime contract,
and their Markdown/JSON outputs are not automatically valid baselines.

## Audit/build/prototype

| Variable | Values | Consumer | Effect |
|---|---|---|---|
| `NATIVAX_AUDIT_MANIFEST` | path | audit tests | Manifest for `nxaudit` batches |
| `NATIVAX_JIT` | `1` | native build | Compiles QuickJS JIT prototype code; not a supported page feature |
| `NATIVAX_V8_FLAGS` | string | V8 build/spike | Build flags, not a page runtime flag |
| `NATIVAX_GL_H` | path | native prototype | GL header include path |
| `NATIVAX_WASM_H` | path | native prototype | WASM header path |
| `NATIVAX_BRIDGE_H` | path | native prototype | Bridge header path |
| `NATIVAX_RUNTIME_INTERNAL_H` | path | native prototype | Runtime internal header path |
| `NATIVAX_MIR_H` | path | native prototype | MIR header path |
| `NATIVAX_JIT_H` | path | native prototype | JIT header path |

Do not present the prototype header variables or `NATIVAX_JIT` as stable product
configuration.

## Rules

- `NATIVAX_ENGINE=quickjs` is the only engine override in the default selector.
- A variable read at process start cannot be changed per page at runtime.
- Metrics/traces add overhead; do not benchmark with them enabled unless the
  benchmark defines that as its measurement.
- Do not put secrets in environment variables that a page can influence or log.
- Update this page when a variable gains/loses a consumer; grep the source before
  documenting one.

## Related

- [`configuration.md`](configuration.md)
- [`../internals/diagnostics.md`](../internals/diagnostics.md)
- [`../benchmarks.md`](../benchmarks.md)
- [`../testing.md`](../testing.md)

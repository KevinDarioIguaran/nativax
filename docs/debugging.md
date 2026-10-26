# Debugging

This page is a triage guide: where a symptom appears, which layer owns it, what
evidence to collect, and which debug engine can reproduce it. It does not replace
the engine READMEs or the source.

## First rule

Do not "fix" a page by adding a browser, a WebView, a local HTTP server, or a
JavaScript shim that hides the real gap. If the owned chain cannot render it,
the result is a documented limitation or a runtime bug, not a fallback.

NativaX has six failure surfaces:

1. **Parse** — invalid/limit HTML, bad tree, missing context.
2. **Style** — selector/cascade/property not implemented or wrong.
3. **Script** — engine/runtime/bridge error.
4. **Layout/paint** — renderer approximation or bug.
5. **Host policy** — resource/network/image denied.
6. **Environment** — no native library, wrong platform, no display, SDK mismatch.

## Symptom → layer

| Symptom | Check first | Likely owner |
|---|---|---|
| Blank page, no error | `runtime.parseErrors`, `onDiagnostic`, whether `body` has children | HTML/DOM/runtime |
| Text present but unstyled | stylesheet loaded? `styleEngine.computedStyle` | resource loader/CSS |
| Inline CSS works, linked CSS does not | `NativaXResourceLoader` and `documentUrl` | host policy |
| `ReferenceError`/syntax error | `onScriptError`, `NATIVAX_TRACE_JS` | JS engine/page |
| API says undefined | prelude support and engine name | bindings/engine |
| Bridge call fails | engine name, host trace, id validity | bindings/FFI |
| Layout shifted | visual judge diff/elements/positions | renderer/CSS |
| Image missing | image resolver and renderer diagnostic | host/renderer |
| Font wrong | `@font-face` bytes, format, fallback | host/renderer |
| Hangs/freezes | engine, loop, timer, host callback | JS engine/host |
| Crashes process | native stack, engine, GL/WASM | native |

## Runtime diagnostics

`NativaXRuntimeConfig`:

```dart
onDiagnostic: (m) => debugPrint('nativa: $m'),
onScriptError: (e) => debugPrint('script: $e'),
onConsole: (m) => debugPrint('console[${m.level.name}]: ${m.text}'),
```

`NativaXView` also accepts `onRuntimeReady`. The runtime exposes `engineName`,
`parseErrors`, `scriptErrors`, and `isDisposed`. `NativaXDocumentView` accepts a
renderer `onDiagnostic` and deduplicates messages per mount.

A diagnostic is not a thrown exception. A denied stylesheet, missing font, or
unresolved image is normally a diagnostic and the page continues.

## Trace switches

```bash
NATIVAX_ENGINE=quickjs NATIVAX_TRACE_JS=1 NATIVAX_TRACE_HOST=1 \
  flutter run -d linux
```

| Switch | What you get |
|---|---|
| `NATIVAX_TRACE_JS=1` | Slow script evaluation log |
| `NATIVAX_TRACE_HOST=1` | Host bridge call trace/timing |
| `NATIVAX_TRACE_TIMERS=1` | Timer scheduling/entry log |
| `NATIVAX_TRACE_DRAW=1` | Renderer draw trace + layout profile |
| `NATIVAX_RENDER_PROFILE=1` | Layout profile buckets |
| `NATIVAX_NO_STYLE_CACHE=1` | Uncaught style-cache bug reproduction |
| `NATIVAX_TRACE_GC=1` | V8 GC trace |
| `NATIVAX_METRICS=1` | Example metrics overlay/style metrics |

These print to the process output; they are not structured trace files. See
[`internals/diagnostics.md`](internals/diagnostics.md) for the full variable
table.

## Engine-specific checks

```dart
debugPrint(runtime.engineName);
```

- `quickjs`: modules, WebAssembly, SharedArrayBuffer, WebGL available when host
  support exists; wall-clock budget enforced.
- `v8`: classic scripts only for this implementation; no modules, WebGL, SAB,
  WASM host integration; **no time/job/stack enforcement**. A freeze on V8 is a
  real risk, not a test artifact.
- A page with a module script should never select V8 through the default path. If
  it does, inspect a custom `engineFactory`.

Test V8 only when `NATIVAX_V8_LIB` is set:

```bash
export NATIVAX_V8_LIB=/path/to/libnx_v8.so
cd packages/nativa_js && dart test test/v8_engine_test.dart
```

A skip is not success.

## Resource and network checks

- `NativaXDenyAllResources` is the default; a page with external `<script src>`
  or `<link>` will not load it unless a loader is supplied.
- Same-origin `fetch` routes through `LocalResourceNetwork` to the resource
  loader; if the loader returns null, it can fall back to the configured network
  policy. A denied network is still safe.
- `img` is never fetched; set `NativaXImageResolver`.
- `@font-face` uses `loadBytes`; a `load`-only loader cannot serve binary fonts.
- Cross-origin URLs must pass `NativaXNetwork`; `IoNetwork` is not CORS.

Add temporary logging in the host loader (not in page JS) to see the exact key.

## Debug engines

### Compatibility

```bash
cd debug/engines/compatibility
dart run bin/run_test262.dart
dart run bin/run_html5lib.dart
dart run bin/run_url.dart
dart run bin/run_wpt.dart
dart run bin/run_html_tree.dart
dart run bin/run_all.dart
```

Each runner writes per-test JSONL and a metadata summary under
`debug/artifacts/conformance/results/`. Recorded baselines are in
[`../progress/conformance.md`](../progress/conformance.md). The runners use QuickJS
and lite adapters; they are not a browser and do not measure V8.

### Visual fidelity

```bash
dart run debug/engines/visual_comparison/bin/visual_check.dart \
  --suite 50projects50days
```

Chromium is the measuring instrument, not part of NativaX. Outputs go to
`debug/artifacts/visual/latest/`: `results.json`, per-page screenshots, element
tables, and a diff. The judge compares geometry, computed styles, and pixels.
It does not judge video/audio/WebGL or animation timing.

Latest baseline: 51 pages, 52.59 % mean overall, 6 PASS / 5 WARN / 40 FAIL. Use
the per-page `positions.csv`/`elements.csv` to debug layout, not the aggregate
score alone.

### Performance

```bash
dart run debug/engines/performance/bin/perf.dart run --out debug/artifacts/perf/latest
dart run debug/engines/performance/bin/perf.dart run --list
dart run debug/engines/performance/bin/perf.dart idle-app --seconds 5 --build
```

The registry has 270 scenarios; the last baseline measured 17 of them. It is not
a full-suite result. Frame numbers are offscreen pump costs vs Chromium main-thread
layout/style, not FPS. Read the engine README's target/verdict section before
quoting a number.

### Leaks

```bash
cd debug/engines/memory
dart run bin/leaks.dart run --profile quick
dart run bin/leaks.dart run --list
```

Latest (2026-10-25) run covered only `control.release`: 1 PASS, 0 FAIL. That is a
smoke case, not a full leak claim. A RSS rise alone is not a leak; require a
sustained trend and resource counters.

### Security

```bash
cd debug/engines/security
dart run bin/security.dart run
dart run bin/security.dart run --list
dart run bin/security.dart run --only bridge
```

Latest run at `f47240e` had 45 cases: 44 PASS, 0 FAIL, 1 SKIP
(`platform.flutter_resource_policy`). A PASS covers only that attack case. The
suite is not proof of safety and the process is not an OS sandbox.

### JSON interface audit

```bash
python3 debug/engines/bug_detection/audit.py run --budget 400 --batch 50 --seed 2
python3 debug/engines/bug_detection/audit.py self-check --budget 80
python3 debug/engines/bug_detection/audit.py benchmark --budget 120
```

This generates JSON UI scenarios, renders them in NativaX and headless Chromium,
localizes divergences, minimizes cases, and writes issue briefs. Chromium
disagreement is not automatically a NativaX bug; `oracle_conflict` cases are
excluded.

## Artifact and manifest checks

Every benchmark run should have `manifest.json` with `run_id`, area, command,
commit, dirty state, timestamps, host, and files. Check it before trusting a
report:

```bash
cat debug/benchmarks/security/<run_id>/manifest.json
python3 debug/run.py runs --area security
python3 debug/run.py conformance
```

`progress/reports/*-latest.md` is a convenience copy and can lag immutable
timestamped evidence. Canonical per-test data is JSONL under
`debug/artifacts/conformance/results/`; canonical run data is under
`debug/benchmarks/<area>/<run_id>/`.

## Common traps

- Running package tests from the repository root. Use the package directory.
- Reporting a skipped V8 test as passing.
- Treating a lite WPT adapter result as full WPT.
- Treating a visual percentage as "percent of CSS supported".
- Editing `progress/reports/*-latest.md` by hand instead of rerunning the engine.
- Running performance with trace/metrics enabled and comparing it to a clean run.
- Calling `dispose()` and then using the runtime; late async loads must be
  discarded by generation checks.
- Assuming config changes reload `NativaXView`; they do not.
- Adding `webview_flutter`/`HtmlElementView` to route around an unsupported
  feature. This violates the product boundary.

## Related

- [`testing.md`](testing.md)
- [`benchmarks.md`](benchmarks.md)
- [`internals/diagnostics.md`](internals/diagnostics.md)
- [`internals/limits-and-memory.md`](internals/limits-and-memory.md)
- [`debug/README.md`](../debug/README.md)
- [`progress/status.md`](../progress/status.md)

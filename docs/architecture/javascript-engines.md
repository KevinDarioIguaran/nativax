# JavaScript engines

NativaX uses a real JavaScript engine. There is no toy interpreter, regex-based
evaluation, or browser fallback. Two backends implement the same
`JavaScriptEngine` contract:

- **QuickJS-ng** (`packages/nativa_js/lib/src/quickjs_engine.dart`) through a C
  build hook and `dart:ffi`.
- **V8** (`packages/nativa_js/lib/src/v8_engine.dart`) through the Rust
  `rusty_v8` cdylib in `tools/v8-spike/` and `dart:ffi`.

The contract is synchronous on purpose: DOM code must call into Dart and receive
a result in the same JavaScript entry, like a browser binding. Long-running work
is supposed to be bounded by the execution budget; the two backends do not
enforce it equally (see below).

## Default selection

`createDefaultJavaScriptEngine` implements the default page rule:

```text
NATIVAX_ENGINE == "jsc" and JavaScriptCore loads
        -> JavaScriptCore (opt-in)
desktop (Linux/macOS/Windows)
  and NATIVAX_ENGINE != "quickjs"
  and no live V8 instance
  and libnx_v8.so (or NATIVAX_V8_LIB) loads
        -> V8
otherwise
        -> QuickJS-ng
```

`NativaXRuntime._create` adds two page-level rules before that:

1. `<script type="module">` forces QuickJS, because V8 and JSC have no module
   evaluator.
2. `forceQuickJs: true` forces QuickJS, even over a custom `engineFactory`.

`NativaXView` makes the force flag sticky after a post-startup V8 heap stop, so a
reload stays on QuickJS.

There is exactly one live V8 engine per isolate/thread in this implementation.
The V8 cdylib uses a thread-local `STATE`; `V8Engine.hasLiveInstance` prevents a
second live instance in the default selector. Direct code that creates two V8
instances can still fail; the default path avoids it.

## QuickJS-ng

QuickJS-ng is the portable backend:

- compiled by the package build hook (`packages/nativa_js/hook/build.dart`);
- loaded from the native asset;
- supports classic scripts and ES modules;
- implements `moduleHost` for imports;
- has an event loop with a wall-clock execution budget, microtask draining, and
  a job cap;
- integrates WebAssembly (wasm3 bridge), SharedArrayBuffer, and the WebGL native
  bridge where the host provides a GL context;
- is the engine used by `debug/engines/compatibility` runs, which means the
  recorded Test262/WPT numbers are **QuickJS numbers**, not V8 numbers.

It is an interpreter, so it is slower than V8 on heavy JavaScript. That trade-off
is intentional for mobile/no-JIT contexts and for features V8 does not expose.

## V8

V8 is the desktop fast path:

- a Rust cdylib built from `tools/v8-spike/` (`rusty_v8`);
- loaded as `libnx_v8.so` by default, or `NATIVAX_V8_LIB`;
- runs classic scripts and supports the host function bridge;
- has a near-heap-limit callback that terminates a script instead of aborting
  the process, and a periodic GC timer;
- does **not** implement `evaluateModule`; it throws
  `JavaScriptEngineStateException('V8 modules are not implemented yet')`;
- does **not** expose the host WebAssembly, SharedArrayBuffer, or WebGL bridge
  (`__nx_sab_*` are null and `__nx_gl_native` is null in the V8 prelude);
- does not currently enforce `executionBudget`, `maxJobsPerDrain`, or a native
  stack limit in the native entry points. `nv8_create` receives
  `(memory_limit, _max_stack)` and ignores the stack value; there is no
  interrupt/timeout path in the Rust eval functions;
- reports `hasPendingMicrotasks == false` and drains through V8's microtask
  checkpoint.

This is a deliberate but incomplete backend. A desktop page that runs an
infinite loop on V8 can block the UI isolate; QuickJS is the engine with the
wall-clock budget. Do not describe the two as feature-identical.

## JavaScriptCore (opt-in)

`JscEngine` binds the host's JavaScriptCore through `dart:ffi` at run time;
nothing is linked at build time, so no platform build depends on it:

- Linux: `libjavascriptcoregtk-4.1.so.0` (then `-6.0.so.1`, `-4.0.so.18`);
  macOS/iOS: the system `JavaScriptCore.framework`; Android/Windows: only a
  library the app bundles, via `NATIVAX_JSC_LIB` or `libraryPath`.
- `isAvailable` is false when the library or
  `JSContextGroupSetExecutionTimeLimit` is missing; selection then falls back.
- `executionBudget` interrupts running code (uncatchable, also through nested
  script -> host -> script entries); the engine stays usable afterwards.
- The memory limit is checked between top-level entries from
  `JSGetMemoryUsageStatistics` (sampled at under 5 % overhead) and once after
  page startup. Over it, `memoryExhausted` is set and the page reloads on
  QuickJS like V8. One runaway allocation inside a single entry is bounded only
  by the time budget.
- Not supported: `evaluateModule`, WebGL (`__nx.gl` is null), cross-runtime
  SharedArrayBuffer, workers, and `maxJobsPerDrain` (JSC drains promise jobs
  itself; an endless chain is stopped by the time budget instead).
- JSC's global object has an immutable prototype; the DOM prelude copies the
  `Window` chain onto it (`adoptGlobalPrototype`).

Measured on Linux x64 only (JSC GTK 2.52.5); see `progress/log.md`
2026-10-27. Other platforms are untested.

## What “default” means in practice

| Situation | Engine | Reason |
|---|---|---|
| Linux desktop, `libnx_v8.so` shipped and loadable | V8 | Default desktop fast path |
| Linux desktop, library missing | QuickJS | `V8Engine.isAvailable` is false |
| macOS/Windows, library not built/bundled | QuickJS | Same availability rule |
| Android/iOS | QuickJS | `Platform.is*` desktop check fails; no JIT assumption |
| Any page with a module script | QuickJS | V8 modules absent |
| `NATIVAX_ENGINE=quickjs` | QuickJS | Explicit override |
| `forceQuickJs: true` | QuickJS | Explicit override |
| Custom `engineFactory` | Whatever the host returns | Host contract |
| Worker | QuickJS | Worker launcher constructs QuickJS |

“Desktop” here is code-level selection. Only Linux x86_64 has current build and
measurement evidence in this repository. macOS/Windows are **unverified**, not
supported by evidence.

## Configuration and actual limits

`JavaScriptEngineConfig` defaults:

| Field | Default | Effect |
|---|---:|---|
| `memoryLimitBytes` | 64 MiB | QuickJS allocator ceiling; V8 near-heap-limit termination |
| `maxStackBytes` | 256 KiB | QuickJS native stack guard; ignored by the V8 native create call |
| `executionBudget` | 1 s | QuickJS entry budget; not enforced by current V8 |
| `maxJobsPerDrain` | 10,000 | QuickJS promise-job guard; not enforced by current V8 |
| `microtaskSlice` | zero | QuickJS optional yield slice; zero means full drain |

`NativaXRuntimeConfig.defaultEngineConfig` changes the runtime defaults to a
10 s execution budget and 1,000,000 jobs per drain, with the 64 MiB memory and
256 KiB stack values unchanged. The 1 s values apply when you construct a
`JavaScriptEngineConfig` for a standalone engine.

`memoryLimitBytes: 0` disables the QuickJS allocator limit. That is not
recommended for hostile content.

## Bridge contract

Scripts call host functions through a generated prelude. The essential rule is:

> Scripts receive ids, scalars, and JSON only. They never receive Dart objects,
> `JSValue`s, native pointers, or callbacks that are not explicitly serialized.

- Host functions are registered by name (`timer.schedule`, DOM operations,
  storage, network, canvas, etc.).
- Arguments and results are JSON-compatible values: `null`, bool, number,
  string, list, map.
- Errors from Dart become generic JavaScript errors with a stable name and
  message, not a stack trace of the Dart host.
- `DomBindings.harden()` removes the raw bridge from globals before user scripts.
- Handles (nodes, windows, events, timers) are integer ids checked against a
  registry; a stale or forged id is rejected.

The detailed call sequence is in
[`../internals/javascript-bridge.md`](../internals/javascript-bridge.md).

## Asset loading and V8

V8 is a cdylib, not a browser. The host must make the V8 library available to the
loader. In this repository the game example's `native/libnx_v8.so` is untracked
and is used by `examples/game-player/run_v8.sh`; the default example build may
fall back to QuickJS when the library is absent. Do not assume that a desktop
build automatically ships V8.

## Testing

- `packages/nativa_js/test/quickjs_engine_test.dart`
- `packages/nativa_js/test/v8_engine_test.dart` (skips without
  `NATIVAX_V8_LIB`)
- `packages/nativax/test/v8_smoke_test.dart` (skips without `NATIVAX_V8_LIB`)
- `packages/nativa_js/test/module_test.dart`
- `packages/nativa_js/test/wasm_test.dart`
- `packages/nativa_js/test/jit_test.dart` (QuickJS JIT spike path)

A V8 test that skips is not V8 verification. Check the output, not the test
count.

## Known gaps

- V8 lacks modules, WebAssembly host integration, SharedArrayBuffer, WebGL, and
  time/job/stack enforcement.
- V8 has no standards-suite measurement in this repository.
- QuickJS is slower and is the only engine with the complete host integrations.
- Engine-specific behavior can differ; pages should be tested on the engine they
  will ship with.
- Workers are always QuickJS, even when the page is V8.

## Related

- [`../reference/configuration.md`](../reference/configuration.md)
- [`../internals/javascript-bridge.md`](../internals/javascript-bridge.md)
- [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md)
- [`../javascript-supported.md`](../javascript-supported.md)
- [`../status.md`](../status.md)

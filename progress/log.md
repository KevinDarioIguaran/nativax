# Work log

Newest first. Historical Spanish sessions are in
[`history/log-2026-10-25-es.md`](history/log-2026-10-25-es.md); they are
evidence, not current instructions. Numbers below are copied from recorded
outputs, not reconstructed from memory.

## 2026-10-27 — JavaScriptCore as the only engine

QuickJS-ng, V8, wasm3 and the MIR JIT were removed; `JscEngine` runs pages
and workers. The native library now holds only memory, buffers, shared
blocks and the futex (`nativax_native`).

- ES modules: `ModuleTransform` rewrites modules for a registry in the
  engine (imports, exports with live getters, cycles, `import()`,
  `import.meta`). Imported bindings are snapshots.
- SharedArrayBuffer: ArrayBuffers over reference-counted native blocks
  shared across worker runtimes; `Atomics.wait/notify` via a native futex.
- WebAssembly: JSC's own; async entry points compile synchronously because
  JSC settles them on a run loop a Dart host never spins.
- `queueMicrotask` shim; DOM wrappers released by a cache sweep after GC
  (JSC never runs FinalizationRegistry callbacks without its run loop:
  ~400 B leaked per wrapper otherwise).
- Results without a JSON form return null (engine contract).

Known gaps (recorded, not hidden):
- WebGL is not wired to JSC yet: `getContext` returns null; the game stops
  at "OffscreenCanvas is not available" (`game_boot_test`,
  `game_play_test` fail).
- A WebAssembly infinite loop is not interrupted by JSC's watchdog.
- The per-drain microtask job limit cannot be enforced
  (`limits.microtask_limit` fails; the time budget stops such loops).
- Android and Windows ship no JSC; the app must bundle one.
- Leak audit runs with JSC's JIT off; `audit.control.listeners_balanced`
  shows a one-time ~6 KB step and is not asserted until recalibration.

## 2026-10-27 — Opt-in JavaScriptCore engine

Scope: add `JscEngine` (nativa_js) as an optional backend behind
`JavaScriptEngine`, without changing the default engine. It binds the host's
JavaScriptCore through `dart:ffi` at run time (Linux `libjavascriptcoregtk`,
Apple system framework, `NATIVAX_JSC_LIB` elsewhere); nothing is linked at
build time, and where JSC does not load the usual engine is used.

- Limits: the execution budget interrupts running code
  (`JSContextGroupSetExecutionTimeLimit`), also through nested
  script -> host -> script entries. The heap is checked against the memory
  limit between entries (sampled, <5 % overhead) and once after page startup;
  over it the page reloads on QuickJS like V8. A single runaway allocation
  inside one entry is bounded only by the time budget.
- Not on JSC: ES modules (module pages stay on QuickJS), WebGL, cross-runtime
  SharedArrayBuffer, workers, and the per-drain microtask job limit.
- `adoptGlobalPrototype` in the DOM prelude: JSC's global has an immutable
  prototype, so Window members are copied onto it and `instanceof` recognises
  it. QuickJS still uses `Object.setPrototypeOf`.
- `forceQuickJs` (the memory-limit reload) now wins over `engineFactory`.
- Debug harnesses (microbenchmarks, security, Test262, memory runtime cases)
  read `NATIVAX_ENGINE` (default `quickjs`).

Measured on Linux x64, JavaScriptCore GTK 2.52.5, same tree, QuickJS -> JSC:

- Microbenchmarks (3 warmup / 15 rounds, `compare --threshold 10 --noise 2`):
  `js.*` -59 % to -96 %, `js_steady.*` -56 % to -99 %, `bridge.noop` -17.7 %,
  `dom.*` -23 % to -50 % (`create_nodes`, `innerHTML`, `style_recompute`
  within noise).
- Security: QuickJS 44 PASS / 0 FAIL / 1 SKIP; JSC 43 PASS / 1 FAIL / 1 SKIP.
  The failure is `limits.microtask_limit`: JSC stops the endless promise chain
  with the time budget, not with `maxJobsPerDrain`.
- Test262 (`language/{expressions,statements,types,literals}`, 21,098 tests):
  QuickJS 19,943 PASS / 47 FAIL / 1,108 SKIP (99.76 %, 55.6 s); JSC 19,824
  PASS / 166 FAIL / 1,108 SKIP (99.17 %, 186.8 s). Most JSC-only failures are
  `using` / `await using` syntax. The longer JSC wall time is not explained by
  engine creation (1.38 ms vs 0.98 ms per create+eval+dispose); cause not
  established.
- Leaks (`--profile quick --only runtime`): 12 PASS on both; only
  `runtime.engine_cycles` and `runtime.bindings_cycles` select the engine.

Not measured: macOS, iOS, Android, Windows, and V8 (no `libnx_v8.so` here).

## 2026-10-26 — Visual fidelity fixes (50projects50days)

Scope: renderer/cascade fixes found with the Chromium visual judge. Evidence:
`progress/reports/visual-50projects50days-latest.md` (2 PASS / 18 WARN /
31 FAIL, mean 89.62 %; same judge before: 2 / 7 / 42, mean 78.77 %).

- `nativa_css`: the style caches ignored ancestors' classes, so
  `.panel.active h3` styled every panel's `h3`; elements matched by
  descendant/child-combinator rules now share styles only with siblings.
  UA form controls use Chromium's computed borders/overflow.
- `nativa_render`: pixel-snapped box decorations; body background
  (incl. gradients) propagates to the canvas; outer `box-shadow` clipped
  outside the border box and blur converted to CSS sigma; `letter-spacing`
  offset; inline atomics baseline-aligned with margins and safe dry
  baselines; definite widths overflow block containers; column flex
  definiteness and fit-content; flex automatic minimum size; shrink-to-fit
  absolute boxes; fixed boxes inside transformed ancestors; collapsible
  spaces around `<br>`; empty lines have no height; 13px checkbox/radio;
  text fields without Material's 1.5 line height and with Chromium-like
  default widths; block-level controls are not stretched; label text taps.
- Harness: screenshots now paint blurred shadows (`debugDisableShadows`),
  a measurement correction, not a compatibility gain.
- Not fixed: glyph rasterization differs from Chromium (see report), so pages
  with text stay WARN. Default input width is a fit (±2px).

Tests: `nativa_render` 133 pass (19 new in `visual_fidelity_test.dart`,
`pixel_snap_test.dart`), `nativa_css` 113 pass (1 new), `nativax` pass.
`./tools/test_all.sh` and performance benchmarks were not run.

## 2026-10-26 — Documentation and evidence consolidation

Scope: make maintained documentation English and source-backed, consolidate
diagnostics under `debug/`, and add documentation validation. No runtime
behavior, public API, dependency, or package boundary was changed by this work.

Completed in this session:

- Removed the root `benchmarks/` layout; moved tracked baselines and game-player
  phase-0 evidence under `debug/benchmarks/`.
- Added `debug/manifest` and wired run manifests into benchmark, leak, and
  security engines. The schema is
  `debug/logic/schemas/run-manifest.schema.json` (schema 1.0).
- Moved generated `.visual`, `.perf`, `.conformance`, `.audit`, and `.runs`
  data under gitignored `debug/artifacts/`.
- Added compact conformance summaries (`resultsFile` points to JSONL) and
  `run-index`/`conformance-index` schemas.
- Added `debug/logic/context.py` and bounded agent projections (`brief`,
  `runs`, `conformance`, `docs`, `measure`, `index`).
- Added `debug/logic/ia_audit.py`; generated
  `progress/reports/information-architecture-latest.json`.
- Compacted `progress/status.md` and preserved the earlier long snapshot.
- Archived Spanish historical pages under `docs/archive/legacy-es/` and
  `progress/history/`; added archive indexes and a replacement map.
- Rewrote root `README.md`, `docs/README.md`, architecture/guides/reference/
  internals pages, testing/debugging/contributing/agents/glossary/FAQ, and the
  HTML/CSS/JS support pages in English.
- Translated the remaining maintained Spanish task pages and moved the
  phase-0 presentation and JIT baseline pages to `progress/history/` with a
  replacement index.
- Added `tools/check_docs.py` and `tools/test_check_docs.py`. The checker covers
  local links, maintained-document language, backticked source paths, shell
  command paths, and public `nativax` barrel symbols.
- Added docs checks to `tools/test_all.sh` and aligned
  `debug/logic/test_docs_links.py` with the checker's maintained-document scope.
- Archived the pre-consolidation debug-system snapshot and engine inventory
  under `debug/archive/`; fixed stale links and paths left by the docs moves.
- Published `progress/reports/docs-audit-latest.{json,md}`.
- Recorded source-backed corrections:
  - default `documentUrl` is `app://local/index.html`;
  - hard parser limits throw `HtmlLimitException`;
  - the runtime exposes `parseErrors`/`scriptErrors`, not public
    `styleSheets`/`linkedSheets`;
  - `NativaXView` does not reload on config-only changes;
  - `LocalResourceNetwork` falls back to the configured network when a
    same-origin loader returns null, and `/api/` bypasses the loader;
  - V8 does not enforce execution budget, job limit, or stack limit and lacks
    modules/WebAssembly/WebGL/SAB host integration.

Measured or reproduced in this session:

- URL conformance: 665 PASS / 231 FAIL / 0 SKIP / 0 ERROR, 74.22 %, 896 tests.
  Compact summary 289 B vs the legacy 197,504 B summary.
- Security: `20261026T024956Z-f47240e` — 45 cases, 44 PASS, 0 FAIL, 1 SKIP
  (`platform.flutter_resource_policy`).
- Leaks: `20261026T030350Z-f47240e` — only `control.release`, 1 PASS, RSS
  476.3 MiB → 290.5 MiB, `activeRuntimes=0`. Not a full leak suite.
- Compatibility/debug Python tests: **10/10 files OK** after the documentation
  moves. `python3 tools/test_check_docs.py`: **7/7 OK**.
- Documentation audit: **PASS**, 100 maintained files, 0 issues.
- Full `./tools/test_all.sh` is **flaky**. On 2026-10-26 three runs exited 0;
  a later run on the same tree exited **1** and
  `packages/nativax/test/game_play_test.dart` did not complete:
  `TestDeviceException(Shell subprocess crashed with SIGABRT (-6))`. The same
  failure occurred at clean `HEAD` `f47240e`. Root cause is not established.
  Passing package/analyzer stages before the failure are not a green suite.
- `git diff --check`: clean at the final validation checkpoint.

Still open:

- Review the complete diff with the owner and commit only after approval, with
  no AI attribution.
- Diagnose the `game_play_test.dart` SIGABRT/flake and make the full suite a
  stable gate; add CI when it is reproducible.
- Verify a non-Linux platform, enforce V8 time/job/stack limits, and run the
  remaining conformance/security coverage as separate changes.

## 2026-10-25 — Information architecture

- Consolidated debug data under `debug/`; added manifests, schema validation,
  metadata-only conformance summaries, context indexes, and storage/IA audits.
- Kept `debug/artifacts/` gitignored and prunable only by explicit command.
- Preserved old conformance summaries (92 historical summaries were not
  migrated).
- Added bounded context measurements. Token counts are estimates because no
  tokenizer library is installed.

## 2026-10-24 — Conformance, visual, and performance baseline

- Test262: 19,577 PASS / 413 FAIL / 1,108 SKIP, 97.93 %.
- html5lib tokenizer: 5,759 PASS / 43 FAIL / 1,025 SKIP, 99.26 %.
- WPT `dom/nodes`: 196 PASS / 84 FAIL / 47 SKIP, 70.00 %.
- WPT `css/selectors`: 127 PASS / 53 FAIL / 348 SKIP, 70.56 %.
- WPT `dom/events`: 52 PASS / 21 FAIL / 103 SKIP, 71.23 %.
- Tree construction: 1,556 PASS / 316 FAIL / 99 SKIP / 2 ERROR, 83.03 %; the
  2026-10-25 runner corrections that raised this from 71.18 % are harness fixes,
  not product gains.
- Visual 50projects50days: 51 pages, 6 PASS / 5 WARN / 40 FAIL, mean 52.59 %.
- Performance: 17 of 270 scenarios, 5 PASS / 2 WARN / 10 FAIL; Linux app idle
  105.0 MB RSS, 0.00 % CPU.
- Last recorded fully green full test run: 301 tests.

## How to append

Add a dated section with:

- scope and files/areas touched;
- exact commands;
- actual results and run IDs;
- skips/blockers;
- what could not be measured;
- whether the change is committed.

Do not rewrite earlier entries to make a later result look better.

# Migration plan — Flutter → standalone C runtime

Strategy: additive migration on `native-c-sokol`. The Flutter implementation on
`main` is untouched; this branch grows an independent C runtime. No step
depends on Dart, Flutter or the old FFI path.

Status legend: **done** (implemented + tested here), **partial** (working
subset, gaps listed), **pending**.

## Phase 1 — Audit

**done.** Repository audited (subsystems, tests, artifacts, benchmarks).
Defects fixed before adding features: GPU glyph-atlas upload off-by-one, leaked
glyph shader, CPU rasterizer double-blended shared edges, non-portable GPU
golden size, stale manifest claims. Evidence: `debug/progress/completed.md`,
`debug/reports/render-baseline.md`.

## Phase 2 — Native structure, toolchain, window

**done.** Single CMake build (`nativax_*` targets), platform layer
(`include/nativax/platform.h`: window, lifecycle, normalized input, DPI,
clipboard, readback) with the sokol_app backend in `src/platform_sokol.c`;
`src/main_sokol.c` is now an entry point over that contract. Resize/DPI changes
update the CSS viewport, pointer/touch coordinates are converted from
framebuffer pixels, keyboard events reach the DOM, and headless mode runs the
same pipeline for CI. Verified by `unit_platform`, `unit_app` (native key/pointer
dispatch) and `gpu_window_screenshot`.

## Phase 3 — Renderer

**partial → done for v1 primitives.** Display list (vertices, indices, groups,
scissor stack, transform stack), Sokol GFX batching, glyph atlas + text runs,
images/textures, rounded rects, borders, clipping, DPI scaling, deterministic
screenshots, GPU stats. Gaps: no opacity layers/compositing groups, no
per-element font selection, no retained render tree reuse across frames.

## Phase 4 — JavaScript engine + bindings

**done (this iteration).** JavaScriptCore behind `js_engine.h`; timers and rAF
in `js_loop`; DOM bindings in `js_dom` (native primitives + JS prelude):
`document`, element traversal/mutation, attributes, `textContent`/`innerHTML`,
`style`, `classList`, events, `console`. Verified by `tests/test_app.c`
(script mutates DOM → layout/paint updates; click dispatch by hit test).

## Phase 5 — HTML parsing, DOM, events

**partial.** Tokenizer + tree builder with implied end tags, raw text, entities,
comments, limits (4 MiB input, 100k nodes, depth 200). DOM: handle pool,
traversal, mutation, id index, capture/bubble dispatch, listener lifecycle.
Gaps: no foster parenting, no fragment parser, no `contenteditable`, no forms
model, no shadow DOM.

## Phase 6 — CSS, computed style, layout

**partial.** Tokenizer/parser, selector matching (type/id/class/attributes,
combinators, `:not()`, structural pseudo-classes), cascade with specificity +
source order + `!important`, `@media` width/height, inheritance, inline
`style=""` (also written by scripts). Layout: normal-flow blocks, inline text
wrapping, percentages, auto margins, text-align. Gaps: flexbox, grid, floats,
absolute/fixed, inline-block boxes (inline subtrees are flattened), margin
collapsing.

## Phase 7 — Complete pipeline

**done (this iteration).** `app.c` owns the pipeline:
HTML → CSS → computed styles → layout → display list → Sokol GFX. Incremental
invalidation: any DOM/style write marks the app dirty; restyle re-resolves into
the layout's array and re-runs layout; paint rebuilds the display list. No
GPU→CPU→GPU round trip on the presentation path.

## Phase 8 — Dev server, hot reload, incremental native builds

**done (this iteration).** `devserver.c`: HTTP static serving with content
types, ETag/304, loopback-only binding, path-traversal rejection; RFC 6455
WebSocket endpoint with SHA-1/base64 handshake; recursive inotify watcher with
debounced classification (`css`/`js`/`html`/`asset`). `hotreload.c`:
non-blocking client with reconnect. `cli_main.c`: `init`, `dev`, `build`,
`run`, `test`, `bench`, `clean`; `dev` also fingerprints native sources
(`src/`, `include/`, `CMakeLists.txt`) and performs incremental rebuild +
relaunch when they change. Validated live: CSS reload, JS reload, and native
rebuild/relaunch (`debug/reports/phase8-hot-reload.md`).

## Phase 9 — Memory, startup, performance

**partial, measured.** Optimization applied: per-node style arrays sized to
`nx_node_slot_bound(doc)` and restyled in place (no second allocation).
Measured effect on the windowed example app in the original (2026-10-27)
environment: **120.8 MB → 100.4 MB peak RSS**. Re-measured on 2026-10-28 with
Mesa 25.2.8/LLVM 20 under Xvfb: **136.7-137.1 MB windowed**, 30.5-31.0 MB
headless; `smaps` shows ~58.6 MB of LLVM JIT (llvmpipe) and ~10.9 MB of JSC, so
the 100 MB target is **not met in this environment** (R3). The renderer now
reports tracked GPU bytes (1.0 MB textures + 2.0 MB buffers) separately from
RSS. Remaining: hardware-GL measurement, driver GPU accounting, large-document
workloads (10k+ nodes), frame-time budget on real GPU hardware.

## Phase 10 — Conformance, stability, platforms

**partial.** Test suite: 16 headless ctest suites + 1 windowed GPU suite green,
including dev server, platform input and app reload paths. Remaining:
html5lib/WPT adapters against the C parser, long-run soak/stability harness,
per-platform ASan runs, and platform builds (Windows/Android/iOS) — requirements
documented in `docs/platforms.md`, not yet validated.

## Commit map (this branch, one commit per phase)

| phase | commit |
|---|---|
| 1–3 (audit, structure, renderer) | `cab1e7f`, `b9adb0f` (pre-existing on this branch) |
| 4 — JavaScript engine + DOM bindings | `81f2e65` feat(js): DOM bindings and inline style in the cascade |
| 7 — complete pipeline | `dcdfabf` feat(runtime): application host renders real HTML/CSS/JS documents |
| 8 — dev server, hot reload, CLI | `ed97fa5` feat(dev): self-hosted dev server, hot reload and nativax CLI |
| 9 — memory measurement + optimization | `7eaf71b` perf(memory): size style tables to the document and restyle in place |
| 10 — validation and documentation | `bc4e51a` docs: architecture, dependencies, plan, risks and baseline |
| 1 — audit closure (re-measured baseline) | `b07fe97` docs(audit): close phase 1 with re-verified measurements |
| 2 — native platform layer + normalized input | `74af76a` feat(platform): native platform layer and normalized input (phase 2) |

Phases 5 and 6 (HTML/DOM/CSS/layout subsystems) were already present on the
branch and are extended by the phase 4 commit (inline style cascade) and the
phase 7 commit (pipeline integration).

## Immediate next steps (ordered)

1. Measure GPU/driver memory on hardware GL (the llvmpipe/LLVM fixed cost
   dominates windowed RSS; see `docs/phase1-audit.md` §5).
2. Add flexbox subset needed by the existing NativaX sample apps.
3. Give the DOM event object key/pointer payloads (platform input already
   delivers the data; `js_dom` only dispatches the type today).
4. Wire the html5lib/WPT tokenizer adapters to the C parser for real
   conformance numbers.
5. Validate one more platform (Windows via sokol D3D11 + JSC) before claiming
   cross-platform support.

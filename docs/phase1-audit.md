# Phase 1 — Repository audit (verified 2026-10-28)

Everything below was checked by building and running the code in a clean
build directory, not copied from earlier documents. Where an earlier document
disagrees with what was measured, the discrepancy is listed in §6.

## 1. Inventory

| area | files | lines | notes |
|---|---|---|---|
| Runtime sources | `src/*.c` (24) | ~9.9k | C11, no C++ |
| Public headers | `include/nativax/*.h` (18) | ~1.0k | engine internals do not leak (`JSValueRef` stays in `js_engine.c`/`js_dom.c`) |
| Tests | `tests/*.c` (13) + `gpu_smoke.*` | — | 3 golden PNGs in `tests/goldens/` |
| Vendored | sokol (app/gfx/glue/log), stb (truetype/image/image_write), DejaVu Sans | — | zlib / MIT-PD / DejaVu |
| Example app | `examples/counter` (html/css/js/nativax.json) | — | the only workload measured |
| Lab | `debug/` (Python harness, cases, judges, reports) | — | Python is not needed to build or run |

Largest modules: `css.c` 1440, `dom.c` 1134, `js_dom.c` 896, `html.c` 838,
`style.c` 780, `devserver.c` 727, `app.c` 594, `cli_main.c` 540.

## 2. Subsystem status (code-level, verified by tests)

| subsystem | module(s) | state |
|---|---|---|
| Window/lifecycle/input | `main_sokol.c` | working (X11 via sokol_app) |
| Renderer | `gfx_sokol.c`, `dl.c`, `text.c`, `image.c` | rects, rounded rects, borders, scissor, text atlas, images; **no opacity layers / transforms** |
| CPU raster (tests) | `raster.c` | test oracle for goldens |
| HTML/DOM | `html.c`, `dom.c` | subset parser, handle pool, bubbling events |
| CSS/cascade | `css.c`, `style.c` | selectors, specificity, `@media`, inheritance, inline style |
| Layout | `layout.c` | **normal-flow block + inline text only. No flexbox, grid, float, positioned, inline-block** |
| JS | `js_engine.c`, `js_loop.c`, `js_dom.c` | JavaScriptCore behind one header; timers, rAF, DOM bindings |
| App host | `app.c` | full HTML→CSS→layout→paint pipeline, reload paths |
| Dev server / hot reload / CLI | `devserver.c`, `hotreload.c`, `cli_main.c` | HTTP+ETag, RFC 6455 WS, inotify, `init/dev/build/run/test/bench/clean` |

## 3. Verification run

Toolchain: GCC 13.3, CMake + Ninja, JSC 2.52.6, Xvfb + llvmpipe.

| check | result |
|---|---|
| Clean Release build | 0 warnings, 0 errors |
| `ctest` (Release, no display at configure) | 15/15 pass |
| `gpu_window_screenshot` (real window under Xvfb) | pass (registered only when `DISPLAY` is set at configure time) |
| `ctest` under `-fsanitize=address,undefined` | 15/15 pass, no ASan/UBSan reports (closes the R14 gap for the existing suites) |
| Forbidden-dependency scan (`flutter\|dart\|webview\|electron\|chromium`) in `src include tests CMakeLists.txt` | only comments in headers/CLI text; no code, link or build dependency |

## 4. Dependencies

See `dependency-map.md`. Direct system requirements on Linux: JavaScriptCoreGTK
4.1, X11, Xcursor, Xi, OpenGL. Python is lab-only.

## 5. Benchmarks on record

`benchmarks/baseline.json` and `benchmarks/results/*.json`. Key numbers (as
recorded; the memory numbers were **not** re-measured in this audit):

- windowed counter app: ~100.2-100.5 MB peak RSS under llvmpipe
- windowed minimal `<p>`: 98.0-100.1 MB, so the fixed windowing/GL cost
  dominates and the app adds about 2 MB
- headless counter app: 44.7-46.3 MB
- CPU raster bench: 116 ms/frame at 1024x768 (test oracle, not the GPU path)

## 6. Findings and discrepancies

1. **"At the 100 MB target" is not a meaningful result yet.** ~96-98 MB of the
   windowed figure is software GL + X11 in this environment. It says nothing
   about real GPU drivers, and the margin is zero. The target stays open (R3).
2. **Docs are stale on test count**: `architecture.md` and `current-task.md`
   say 13 suites; the build registers 15 (+1 GPU). Needs a doc fix.
3. **Working tree is dirty**: 16 modified files (app, dom, gfx, main_sokol,
   meminfo, html, CMake, lab scripts) are uncommitted. The last commit
   (`bc4e51a`) does not include them. They need review and a checkpoint commit
   before Phase 2 work builds on them.
4. **Build artifacts are inside the archive**: `build/` (23 MB) and
   `build-asan/` (82 MB) should not be tracked/shared; `.gitignore` is 20 bytes.
5. **Original NativaX test suite is not in this archive.** Only the native
   branch was provided, so "run existing NativaX tests against the C runtime"
   cannot be done yet. Needs the Flutter-side repo or its test corpus.
6. **Conformance is unmeasured**: `debug/upstream` is 40 KB (manifests only),
   and the html5lib/WPT adapters still target the old runtime (R13).
7. **JavaScript engine**: JavaScriptCore is a JS VM only, but it ships from
   the WebKitGTK package (LGPL-2.1). That is compatible with "no embedded
   browser", but must be an explicit decision for the mission's
   "independent JS engine" wording; alternatives behind `js_engine.h` are QuickJS
   (MIT, ~1-2 MB, much lower RSS) and Duktape. QuickJS would also help the
   memory target and portability to Windows/Android/iOS.
8. **Header comments still reference the Dart runtime** (`js_engine.h`, `dom.h`,
   `js_loop.h`, `css.c`, `debug_dump.h`). Harmless comments, but they should be
   reworded so the branch reads as Flutter-free.
9. **Platforms**: only Linux/X11 validated; Wayland not wired.
10. **Hard gaps vs. the mission**: flexbox, opacity/transforms, `fetch`,
    ES modules, GPU memory accounting, runaway-script interruption (R10).

## 7. Proposed order of work

1. Review and commit the 16 uncommitted files as a checkpoint; untrack
   `build*/`; fix test-count docs; reword Dart comments.
2. Decision on JS engine (keep JSC vs. QuickJS).
3. Flexbox subset, then opacity/transforms (renderer), since real apps need them.
4. GPU memory counters in `--mem`; re-measure on the representative workload.
5. Wire html5lib/WPT adapters to the C parser; publish measured pass rates.
6. One additional platform (Windows) build.

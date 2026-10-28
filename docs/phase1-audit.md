# Phase 1 — Repository audit (verified 2026-10-28)

Everything below was checked by building and running the code in a clean build
directory on this machine, not copied from earlier documents. Where an earlier
document disagrees with what was measured, the discrepancy and its resolution
are listed in §6/§8.

Checkpoint note: this audit is the closing record of the iteration. The
platform module (`src/platform*.c`, `unit_platform`) and the matching test row
are introduced by the Phase 2 commit that immediately follows this one, so the
same tree is measured at both checkpoints.

## 1. Inventory

| area | files | lines | notes |
|---|---|---|---|
| Runtime sources | `src/*.c` (25) | ~11.4k | C11, no C++ |
| Public headers | `include/nativax/*.h` (21) | ~1.2k | engine internals do not leak (`JSValueRef` stays in `js_engine.c`/`js_dom.c`) |
| Tests | `tests/*.c` (14) + `gpu_smoke.*` | — | 3 golden PNGs in `tests/goldens/` |
| Vendored | sokol (app/gfx/glue/log), stb (truetype/image/image_write), DejaVu Sans | — | zlib / MIT-PD / DejaVu |
| Example app | `examples/counter` (html/css/js/nativax.json) | — | the only workload measured |
| Lab | `debug/` (Python harness, cases, judges, reports) | — | Python is not needed to build or run |

Largest modules: `css.c` 1440, `dom.c` 1134, `js_dom.c` 896, `html.c` 838,
`style.c` 780, `devserver.c` 727, `app.c` 611, `cli_main.c` 540.

## 2. Subsystem status (code-level, verified by tests)

| subsystem | module(s) | state |
|---|---|---|
| Platform/lifecycle/input | `platform.c`, `platform_sokol.c`, `main_sokol.c` | working (X11 via sokol_app); normalized events, DPI-correct coordinates, clipboard, readback |
| Renderer | `gfx_sokol.c`, `dl.c`, `text.c`, `image.c` | rects, rounded rects, borders, scissor, text atlas, images; **no opacity layers / transforms** |
| CPU raster (tests) | `raster.c` | test oracle for goldens |
| HTML/DOM | `html.c`, `dom.c` | subset parser, handle pool, bubbling events |
| CSS/cascade | `css.c`, `style.c` | selectors, specificity, `@media`, inheritance, inline style |
| Layout | `layout.c` | **normal-flow block + inline text only. No flexbox, grid, float, positioned, inline-block** |
| JS | `js_engine.c`, `js_loop.c`, `js_dom.c` | JavaScriptCore behind one header; timers, rAF, DOM bindings |
| App host | `app.c` | full HTML→CSS→layout→paint pipeline, reload paths |
| Dev server / hot reload / CLI | `devserver.c`, `hotreload.c`, `cli_main.c` | HTTP+ETag, RFC 6455 WS, inotify, `init/dev/build/run/test/bench/clean` |

## 3. Verification run

Toolchain: GCC 13.3, CMake 3.28 + Ninja, JSC 2.52.6, Mesa 25.2.8
(llvmpipe/LLVM 20), Xvfb 21.1, Python 3 + Pillow for screenshot checks.

| check | result |
|---|---|
| Clean Release build | 0 warnings, 0 errors |
| `ctest` (Release, with `DISPLAY=:99`) | **17/17 pass** (16 headless + 1 windowed GPU) |
| `ctest` under `-fsanitize=address,undefined` | **16/16 pass**, no ASan/UBSan reports (GPU suite is not registered in that build; it was run separately in Release) |
| `gpu_window_screenshot` (real window under Xvfb) | pass: 1024x768, palette + glyph coverage validated |
| Forbidden-dependency scan (`flutter\|dart\|webview\|electron\|chromium`) in `src include tests CMakeLists.txt` | only comments/CLI text stating their absence. The binary contains the string `Chromium` from a sokol GL vendor workaround (ANGLE detection), not an embedded browser |
| `ldd build/nativax-runtime` | JSC, GL dispatch, X11; no WebKit web process, no Flutter engine, no Dart VM |

## 4. Dependencies

See `dependency-map.md`. Direct system requirements on Linux: JavaScriptCoreGTK
4.1, X11, Xcursor, Xi, OpenGL. Python is lab-only.

## 5. Benchmarks on record (re-measured in this audit)

`benchmarks/baseline.json` holds the machine-readable version.

| workload | command | peak RSS |
|---|---|---|
| headless counter, 60 frames | `nativax-runtime --headless --root examples/counter --frames 60 --mem` | 30.5–31.0 MB |
| windowed counter, 120 frames | `nativax-runtime --root examples/counter --frames 120 --mem` under Xvfb/llvmpipe | **136.7–137.1 MB** |
| windowed minimal `<p>`, 60 frames | same binary, `/tmp/nxmin` | 132.9–135.2 MB |

Attribution of the windowed figure (`smaps_rollup` + top mappings): libLLVM
(llvmpipe JIT) ≈ 59 MB resident, libjavascriptcoregtk ≈ 11 MB, anonymous heap
≈ 20 MB (driver + JSC + runtime), the rest is X11/GL/mesa/gallium mappings.
The application itself adds ~2–4 MB over the minimal page. GPU allocations
tracked by the renderer at teardown: 1.0 MB textures + 2.0 MB vertex/index
buffers (separate from RSS).

Other numbers:

- `nativax_perf`: cold start 11.8 ms, first frame 11.8 ms, load phases
  read 0.03 / parse 0.05 / collect 1.64 / style+layout 0.55 / script 7.50 ms;
  navigation (3 full reloads) 2.7 ms average.
- CPU raster benchmark: 126.6 ms/frame at 1024x768 (6.2 Mpix/s, 9493 verts).
  This bounds the software test oracle, not the Sokol GPU path.
- Windowed counter / minimal-page difference confirms the fixed graphics-stack
  cost dominates, as the earlier baseline had claimed.

## 6. Findings and status

1. **"At the 100 MB target" is not a meaningful result.**
   **Open (R3).** On this machine the windowed process is 136.7–137.1 MB peak;
   ~59 MB is the llvmpipe LLVM JIT and ~11 MB is JSC. RSS includes shared
   library pages. The 100 MB target must be evaluated on hardware GL (and with
   GPU memory reported separately); it is not met in this software-rendering
   environment.
2. **Docs were stale on test count.** **Fixed:** `architecture.md`,
   `migration-plan.md`, `benchmarks/baseline.json` and the lab progress notes
   now report 16 headless + 1 windowed suite.
3. **Working tree was dirty.** **Fixed:** the follow-up commit checkpointed the
   tree; this audit ran on a clean tree.
4. **Build artifacts inside the archive.** **Fixed:** `build/` and
   `build-asan/` are ignored, not tracked.
5. **Original NativaX test suite is not in this archive.** **Open:** only the
   native branch was provided. "Run existing NativaX tests against the C
   runtime" needs the Flutter-side repo or its test corpus. Parser/CSS cases
   already ported from the V1 suites live in `tests/`.
6. **Conformance is unmeasured.** **Open (R13):** `debug/upstream` holds
   manifests, not full suites; html5lib/WPT adapters still target the old
   runtime.
7. **JavaScript engine decision.** **Decided for Phase 1/2:** keep
   JavaScriptCore behind `js_engine.h`; it is a JS VM only (no browser
   process). QuickJS remains the fallback if the memory/portability target
   requires it; nothing above `js_engine.h` depends on the choice.
8. **Headers referenced the Dart runtime.** **Fixed:** comments now speak of the
   V1 runtime/implementation. Remaining mentions are explicit "no Dart"
   statements.
9. **Platforms.** **Open:** only Linux/X11 validated; Wayland not wired;
   Windows/Android/iOS are documented requirements (`docs/platforms.md`).
10. **Hard gaps vs. the mission.** **Open:** flexbox, opacity/transforms,
    `fetch`, ES modules, keyboard/pointer event payloads in JS, GPU memory
    accounting on real drivers, runaway-script interruption (R10).

## 7. Proposed order of work (unchanged, re-ordered by evidence)

1. Hardware-GL memory/performance measurement; keep GPU bytes separate from RSS.
2. Flexbox subset, then opacity/transforms.
3. Event payloads (`key`, `pointer` coordinates) for DOM listeners.
4. Wire html5lib/WPT adapters to the C parser; publish measured pass rates.
5. One additional platform (Windows) build.
6. Conformance/stability at scale (10k+ node documents, long soak on GPU).

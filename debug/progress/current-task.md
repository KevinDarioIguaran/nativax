# Current task

Phase 2 — Audit, fix and optimize (in progress).

Branch: `native-c-sokol` @ `7637bc3` (orphan branch, no merge-base with `main`).
Environment: GCC 13.3, CMake 3.28 + Ninja, JSC 2.52.6, X11/GL via apt, Xvfb :99 (llvmpipe).

## Verified baseline (evidence captured in this session)

| Test | Result | Detail |
|---|---|---|
| ctest headless (6) | 6/6 PASS | smoke_headless, unit_render, unit_js, unit_dom, unit_css, unit_debug |
| ctest gpu_window_screenshot | PASS under Xvfb | screenshot 1024x768 written (32 KB) |
| checks totals | 473 checks, 0 failures | render 46, js 44, dom 185, css 157, debug 41 |
| warnings (clean build) | 0 | gcc -Wall -Wextra |
| test_visual_judge.py | PASS | after installing Pillow (was broken: no PIL) |
| test_screenshot_determinism.py | PASS | two GPU screenshots identical |
| test_rendering_golden.py | **FAIL** | golden is 1111x809 (author's WM), runtime renders 1024x768 |
| debug/run.py (all commands) | **BROKEN** | ROOT/NATIVE paths point to `native/` subdir of the old branch; imports missing `storage` |
| test_storage_roundtrip.py | **BROKEN** | imports `debug/logic/storage.py`, absent on this branch |

## Bugs found (confirmed empirically)

1. **GPU text renders as solid blocks** — off-by-one in `src/gfx_sokol.c`
   `nx_gfx_sync_textures`: loop queries `nx_tex_info(i)` but registry ids are
   1-based, so texture id 1 (the glyph atlas) is never uploaded and every
   glyph group falls back to the white texture. Probe: `nx_tex_info(0)` is
   NULL, `nx_tex_info(1)` is valid. The committed GPU goldens
   (tests/goldens/smoke_render.png, debug/artifacts/golden/smoke.png) contain
   the broken output (1111x809, text = blocks).
2. **CPU rasterizer double-blends shared fan edges** — `src/raster.c`
   `raster_triangle` uses an inclusive `e >= 0` test on all three edges; a
   subsample exactly on a shared triangle edge is covered by BOTH triangles.
   Diagnostic: 119 pixels with coverage > 4 in a single 80x32 rounded pill;
   visible as lighter streaks in tests/goldens/render_basic.png (committed).
3. **`sg_shader shd_glyph` leaked** in gfx_sokol.c (never destroyed).
4. Manifest/progress documents make stale or unsupported claims
   (manifest.json says 7/7 PASS including GPU without evidence; blockers.md
   says "No Git metadata"; run.py `report` prints hardcoded "7/7 PASS").
5. `js_loop.c` timer flood: O(n^2) scheduling (linear scans per timer).
6. `nx_js_call_json`/`nx_js_json` use fixed 512/1024/2048-byte buffers:
   large JSON args get silently truncated.

## Next (in order)

- Bench harness `nativax_bench` to capture a renderer baseline BEFORE fixes.
- Fix GPU off-by-one + shader leak; re-capture GPU goldens at canonical size.
- Fix raster fill rule; regenerate CPU golden (documented).
- Optimize raster hot path; re-measure each step.
- Repair debug/run.py + storage test + manifest + report (real numbers only).

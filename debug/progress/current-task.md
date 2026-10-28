# Current task

Phase 1 closed and Phase 2 started (platform layer). Next: Phase 2 close-out
(hardware-GL window verification, then Phase 3 renderer gaps).

Branch: `native-c-sokol`. Environment: GCC 13.3, CMake 3.28 + Ninja, JSC 2.52.6,
X11/GL via apt, Xvfb :99 + llvmpipe (Mesa 25.2.8 / LLVM 20.1).

## Verified in this iteration (2026-10-28)

| Test | Result | Detail |
|---|---|---|
| clean Release build | PASS | 0 warnings, 0 errors |
| ctest (DISPLAY=:99) | **17/17 PASS** | 16 headless + `gpu_window_screenshot` |
| ctest ASan+UBSan | **16/16 PASS** | no sanitizer reports (GPU suite not registered there) |
| platform contract | PASS | `unit_platform`: CSS/physical conversion at 1x/1.5x/2x |
| native input → script | PASS | `unit_app`: `keydown` + `pointermove` listeners observed |
| windowed counter peak RSS | 136.7–137.1 MB | 120 frames, llvmpipe; not the 100 MB target |
| windowed minimal peak RSS | 132.9–135.2 MB | fixed graphics-stack cost dominates |
| headless counter peak RSS | 30.5–31.0 MB | 60 frames |
| GPU allocations (renderer) | 1.0 MB textures + 2.0 MB buffers | reported separately from RSS |
| cold start / navigation | 11.8 ms / 2.7 ms avg | `nativax_perf`, 3 full reloads |
| render bench | 126.6 ms/frame, 6.2 Mpix/s | CPU raster oracle 1024x768 |

## Findings closed

- Docs no longer claim 13 suites or a met 100 MB target.
- V1 references in headers/comments reworded; no Flutter/Dart in build or code.
- `build/`, `build-asan/` untracked.
- JS engine decision recorded: keep JSC behind `js_engine.h` for now.

## Next (in order)

- Phase 2 close-out: verify the window/platform layer on hardware GL and record
  the result; keep the software-GL number as a separate data point.
- Give DOM events key/pointer payloads (data already crosses the platform layer).
- Phase 3 gaps: opacity layers, transforms, retained render tree.
- Phase 6: flexbox subset.
- Wire html5lib/WPT adapters to the C parser; publish measured pass rates.
- Validate one additional platform (Windows) before claiming cross-platform support.

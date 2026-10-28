# Phase 2 evidence — native platform layer and window

Date: 2026-10-28. Branch `native-c-sokol`. Environment: Linux/X11, Xvfb `:99`
1280x1024x24, Mesa 25.2.8 (llvmpipe/LLVM 20.1), gcc 13.3, CMake 3.28 + Ninja,
JavaScriptCoreGTK 2.52.6.

## What changed

- New contract `include/nativax/platform.h`: window + lifecycle callbacks,
  normalized input events (resize, focus/blur, pointer down/up/move, touch
  begin/move/end, key down/up, char, clipboard paste, suspend/resume, quit),
  DPI and framebuffer queries, clipboard set/get, framebuffer readback.
- `src/platform.c`: backend-independent coordinate contract
  (`nx_platform_css_coord`, `nx_platform_physical_size`).
- `src/platform_sokol.c`: sokol_app backend. It is now the only runtime
  translation unit that includes `sokol_app.h`.
- `src/main_sokol.c`: entry point over `nx_platform_run`; it contains no
  `sapp_*` symbols. Pointer/touch positions are converted to CSS px, DPI
  changes on resize update the viewport, `keydown`/`keyup` reach the DOM and
  framebuffer readback goes through the platform interface.
- `src/app.c`: `nx_app_pointer_move` and `nx_app_key` dispatch
  `pointermove`/`keydown`/`keyup` on the hit node / `<body>`.

## Verification (commands and observed results)

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4
DISPLAY=:99 ctest --output-on-failure
```

Observed:

```
16/16 headless tests passed
17/17 including gpu_window_screenshot
```

The windowed suite runs the real application (`examples/counter`, 1024x768
deterministic) and validates the screenshot structure (page/header/accent/card
palette + glyph coverage):

```
GPU smoke OK: 12603 bytes; ok size=1024x768
colors={'bg': 22356, 'header': 10434, 'accent': 981, 'card': 49549}
pill_white_px=1557
```

Platform/internals:

- `unit_platform`: 16 checks over CSS↔physical conversion at 1x, 1.5x, 2x,
  zero/negative dpi and the key-enum contract.
- `unit_app`: native `keydown` and `pointermove` reach script listeners
  (`window.__keys * 10 + window.__moves == 11`), then existing click/hot-reload
  assertions still pass.
- Memory probe remained unchanged in shape:
  windowed counter peak 136.7-137.1 MB, headless 30.5-31.0 MB (see
  `docs/phase1-audit.md` §5 for why the windowed figure is driver-dominated).

## Known limitations

- Windowed verification ran under Xvfb + llvmpipe, the only GL stack available
  in this environment (no hardware GPU). The platform contract, event
  translation and presentation path are exercised, but driver-specific DPI
  behaviour (1.5x/2x window scale) and hardware-driver memory are still
  unverified; that is tracked as R3/R1 in `risk-register.md`.
- The event object exposed to scripts carries only the event type; key codes,
  pointer coordinates and modifier state cross the platform layer but are not
  yet in the JS payload (R12).
- No hover styling, no pointer capture, no wheel event in the normalized enum
  yet.
- Only the sokol_app backend exists; Windows/Android/iOS implement the same
  header without touching `main_sokol.c`.

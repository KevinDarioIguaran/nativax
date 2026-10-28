# Current task

Phase 9/10 — memory attribution, conformance and platform validation (next).

Branch: `native-c-sokol`. Environment: GCC 13.3, CMake 3.31 + Ninja, JSC 2.52.6,
X11/GL via apt, Xvfb + llvmpipe.

## Verified in this iteration

| Test | Result | Detail |
|---|---|---|
| ctest | 13/13 PASS | includes unit_bindings, unit_app, unit_devserver, headless_render |
| dev server HTTP | 200 / 304 / 404 | with ETag + Content-Type |
| WebSocket | 101 + RFC 6455 accept key | broadcast delivered as text frame |
| inotify watcher | PASS | css message after editing style.css |
| hot reload css/js | PASS | live log evidence in debug/reports/phase8-hot-reload.md |
| native rebuild + relaunch | PASS | `src/log.c` edit → ninja → relaunch |
| windowed peak RSS | 100.2-100.5 MB | examples/counter, 120 frames, llvmpipe |
| headless peak RSS | 44.7-46.3 MB | examples/counter, 60 frames |
| render bench | 116.3 ms/frame, 6.8 Mpix/s | CPU raster 1024x768, cards 6, text 40 |

## Next (in order)

- Run the 13 suites under ASan/UBSan (build-asan) and fix findings.
- Report GPU memory separately: glyph atlas pages, image textures, vertex/index buffers.
- Add capture-phase scripting + pointermove events before interactive samples.
- Wire html5lib/WPT adapters to the C parser; publish measured pass rates.
- Flexbox subset needed by existing sample apps.
- Validate one additional platform (Windows) before claiming cross-platform support.

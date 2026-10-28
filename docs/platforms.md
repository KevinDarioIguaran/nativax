# Platform build and packaging notes

Status legend: **validated** = built and tested in this environment;
**requirements** = documented design, not yet built.

## Linux (X11) — validated

The window/input layer is `include/nativax/platform.h` with the sokol_app
backend in `src/platform_sokol.c`. Ports implement the header; the entry point
(`src/main_sokol.c`) and the rest of the runtime contain no platform SDK calls.

Requirements:

- C11 compiler, CMake ≥ 3.22, Ninja.
- `javascriptcoregtk-4.1` (WebKitGTK) development package — provides the JS VM.
- OpenGL headers, `libx11`, `libxcursor`, `libxi`, `pkg-config`.

```bash
# configure + build (incremental afterwards)
cmake -S . -B build -G Ninja
cmake --build build -j"$(nproc)"

# tests (headless suites + GPU window smoke when DISPLAY is set)
cd build && ctest --output-on-failure

# run the example app
./build/nativax run examples/counter

# development workflow: HTTP server + hot reload + native rebuild/relaunch
./build/nativax dev examples/counter
```

Headless environments (CI, containers) need no display:

```bash
./build/nativax-runtime --headless --root examples/counter --frames 2 \
  --screenshot /tmp/page.png --stats --mem
```

Packaging (not automated yet):

- Ship the `nativax-runtime` binary plus the app directory (HTML/CSS/JS/fonts).
- The default font is resolved from `NATIVAX_SOURCE_DIR/assets/fonts/
  DejaVuSans.ttf` (compile-time path) with a fallback to
  `assets/fonts/DejaVuSans.ttf` next to the working directory. A release
  layout must place the font (or a bundled font) accordingly.
- `nativax.json` holds `entry`, `width`, `height`, `port` for the CLI.
- No bundling of assets into the binary yet; no installer; no release-mode
  asset hashing (see risk R15).

## Windows — requirements (not validated)

- Toolchain: MSVC 2019+ or clang-cl; CMake with the Visual Studio or Ninja
  generator.
- Graphics/windowing: sokol_app + sokol_gfx D3D11 backend (no GL/X11 code
  needed). `devserver.c`/`hotreload.c` use POSIX sockets and inotify and must
  be ported to Winsock + `ReadDirectoryChangesW`; plan is to keep the same
  interfaces (`nx_dev_server_poll`, `nx_hot_reload_poll`).
- JavaScript engine: a Windows build of JavaScriptCore (WebKit for Windows) or
  another engine implementing `include/nativax/js_engine.h`.
- Packaging: ship `nativax-runtime.exe` + app directory + JSC DLLs.

## Android — requirements (not validated)

- sokol_app provides the Android backend (native activity, EGL/GLES).
- Dev server on the host, app on device: `adb reverse tcp:8788 tcp:8788`, then
  launch the runtime with `--dev ws://127.0.0.1:8788/__nativax_ws`.
- JavaScript engine: JavaScriptCore must be bundled as a shared library for the
  target ABIs (system WebView JSC is not a stable public C API).
- Packaging: Gradle wrapper around the native activity; native libs per ABI.

## iOS / macOS — requirements (not validated)

- sokol_app Metal backend; JavaScriptCore is available as a system framework
  (the only platform where the engine ships with the OS).
- Dev server runs on the host; simulator can reach `127.0.0.1`. Physical devices
  need a LAN-visible dev server (the server currently binds loopback only).
- Packaging: Xcode project or CMake-generated bundle; app directory copied as
  resources.

## Porting order

1. Linux/X11 (current, validated).
2. Windows (most tooling overlap with the existing CMake setup; D3D11 avoids
   an OpenGL dependency).
3. macOS/iOS (JSC ships with the OS, Metal backend available).
4. Android (highest packaging and engine-bundling effort).

No platform target depends on Flutter, Dart or a Flutter host process.

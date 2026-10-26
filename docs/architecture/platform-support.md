# Platform support

NativaX is a Flutter/Dart runtime with native code through `dart:ffi` and Dart
native assets. Platform support is **not** inferred from `Platform.isLinux`/
`isAndroid` branches or from a build hook compiling for a target. A platform is
“verified” only when the build, tests, and relevant behavior were run there.

## Current matrix

| Platform | Build scaffolding in repo | Runtime tests | Benchmarks/security | Status |
|---|---|---|---|---|
| Linux x86_64 | Examples have `linux/`; native assets built | Recorded here | Visual, performance, security, conformance | **Verified, partial** |
| Android | No example `android/` projects | None recorded | None | **Unverified** |
| iOS | No example `ios/` projects | None recorded | None | **Unverified** |
| macOS | No example `macos/` projects | None recorded | None | **Unverified** |
| Windows | No example `windows/` projects | None recorded | None | **Unverified** |
| Web (Flutter web/browser) | Not a target | Not applicable | Not applicable | **Unsupported** |

The packages contain platform-aware code and the QuickJS build hook has Linux,
Android, and Windows branches (`nativax_gl.c` on Linux/Android; a GL stub
elsewhere). That is implementation, not evidence. There is no CI matrix in
`.github/` because this repository has no CI workflows at all.

## What would count as verification

For a platform claim, record all of the following in `progress/` with a date and
commit:

1. A reproducible Flutter build with the platform toolchain (`flutter build` or
   `flutter test`).
2. `./tools/test_all.sh` or an explicit subset with the same known-failure list.
3. Native asset loading: QuickJS works; V8 is optional and must be reported
   separately.
4. At least one representative page: layout, text, input, forms, canvas, and a
   worker.
5. Security suite results and the OS sandbox assumption.
6. DPI/orientation/IME/accessibility behavior where relevant.
7. Memory/RSS and startup data for that platform.

A test skipped because `NATIVAX_V8_LIB` is absent is not V8 verification.

## Engine availability by platform

### QuickJS

QuickJS-ng is compiled by the `nativa_js` build hook for the target OS and
architecture. It is the intended engine on Android and iOS because it does not
need JIT. It also loads on desktop. The current build hook:

- uses `nativax_gl.c` only on Linux/Android and a stub elsewhere;
- uses `pthread` on Linux, `dl`/`m` on Linux/Android, and
  `/experimental:c11atomics` on Windows;
- builds wasm3 with a 384 KiB native stack guard and disables musttail on
  Android.

This is not proof that those targets build or run.

### V8

V8 is a **desktop optional cdylib** (`libnx_v8.so` by default). It is loaded with
`DynamicLibrary.open` and requires all `nv8_*` symbols. The current source uses
the Linux `.so` naming convention; macOS/Windows would need an explicit
`NATIVAX_V8_LIB` path and a matching build. No such build is tracked. V8 also
uses a thread-local native state and only one live instance is supported by the
default selector.

V8 is not available on iOS/Android in this repo and is not a mobile engine
option. It is also not built into the Flutter app automatically; the example
game uses `examples/game-player/native/libnx_v8.so` when present. If the library
is absent, a desktop page falls back to QuickJS.

V8 is not a security boundary. It lacks modules, WebAssembly host integration,
SharedArrayBuffer, WebGL, and time/job/stack enforcement.

## Platform-specific behavior that must be tested

- **Filesystem/resource roots**: `NativaXDirectoryLoader` uses `dart:io`; mobile
  sandbox paths and macOS/Windows path rules differ.
- **Native assets**: Flutter's code-asset resolution differs by platform;
  QuickJS and V8 loading must be checked, not assumed.
- **Stack size**: QuickJS runs on the calling thread; iOS secondary threads have
  as little as 512 KiB. The default 256 KiB stack guard is chosen for that, but
  it has not been measured on iOS.
- **Threads/isolates**: worker isolates, `SharedArrayBuffer`, and native buffer
  sharing need per-platform behavior checks.
- **Input and focus**: touch, keyboard, IME, pointer lock, hover (absent on
  touch), and focus traversal differ.
- **Lifecycle**: suspend/resume, orientation, low-memory warnings, and engine
  disposal must be exercised.
- **DPI**: `devicePixelRatio` and canvas backing stores can exhaust memory on
  HiDPI mobile screens; the config allows capping DPR but the app must choose it.
- **Graphics**: the GL bridge exists only on Linux/Android; other platforms use
  a stub. Canvas 2D is not the same as WebGL.
- **Security**: Android/iOS permissions, entitlements, TLS trust stores, and app
  sandbox behavior are not covered by Linux tests.

## Flutter and Dart versions

The current workspace was measured with Dart 3.13.0 and Flutter 3.47.0 on Linux
x86_64 (2026-10-25/26). The `pubspec.yaml` environment is Dart `^3.10.0`; the
README states Flutter 3.35+ as a practical minimum. A different SDK is a
different verification environment unless re-run.

## What is explicitly unsupported

- Flutter web / browser targets. `dart:io`, `dart:ffi`, and native assets are
  core to the runtime. Do not advertise a web build.
- A browser engine embedded through a plugin. This is a product boundary; adding
  `webview_flutter`, `flutter_inappwebview`, `HtmlElementView`, Chromium, CEF,
  Electron, or a local HTTP server for presentation violates it.
- A claim of Android/iOS/macOS/Windows support based only on a package compiling
  in isolation.

## How to extend this page

Do not add a platform row without an evidence link. Add the command, date,
commit, SDK versions, engine, artifact path, and result. If only part of the
matrix passed, say which part and mark the platform **partial**, not verified.
Update [`../status.md`](../status.md), [`../../progress/status.md`](../../progress/status.md),
and the security platform matrix in the same change.

## Related

- [`../reference/configuration.md`](../reference/configuration.md)
- [`../security/platform-matrix.md`](../security/platform-matrix.md)
- [`../testing.md`](../testing.md)
- [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md)

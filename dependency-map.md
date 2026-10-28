# Dependency map

Everything the runtime links, why it is there, and what would change if it were
replaced. Generated from the actual build (`CMakeLists.txt`, `pkg-config`,
`ldd`) on 2026-10-28 — not from memory.

## 1. Vendored source (in-tree)

| dependency | version/source | license | used by | purpose |
|---|---|---|---|---|
| sokol_app | `third_party/sokol/sokol_app.h` (single header) | zlib | `nativax_sokol` | native window, input events, lifecycle |
| sokol_gfx | `third_party/sokol/sokol_gfx.h` | zlib | `nativax_sokol`, `nativax_gfx` | GPU abstraction (GL core backend on Linux) |
| sokol_glue | `third_party/sokol/sokol_glue.h` | zlib | `nativax_sokol` | sg environment from sapp |
| sokol_log | `third_party/sokol/sokol_log.h` | zlib | runtime | sokol log routing |
| stb_truetype | `third_party/stb/` | MIT / public domain | `nativax_stb` | glyph rasterization for the atlas |
| stb_image | `third_party/stb/` | MIT / public domain | `nativax_stb` | image decode |
| stb_image_write | `third_party/stb/` | MIT / public domain | runtime, raster | PNG output (screenshots, goldens) |
| DejaVu Sans | `assets/fonts/` | DejaVu license (Bitstream Vera derivative) | runtime, tests | default UI font (see `LICENSE-DejaVu.txt`) |

No vendored dependency is a browser engine, WebView, Flutter engine or Dart
runtime.

## 2. System dependencies (Linux, validated platform)

| dependency | pkg-config / soname | license | why | replaceable by |
|---|---|---|---|---|
| JavaScriptCoreGTK 4.1 | `javascriptcoregtk-4.1` → `libjavascriptcoregtk-4.1.so` | LGPL-2.1 (WebKit) | the only JS engine in this branch (AGENTS.md non-negotiable) | another embeddable JS engine behind `js_engine.h` (the interface exposes no JSValueRef outside the engine layer) |
| OpenGL | `OpenGL::GL` → `libGL.so` | MIT/X11-style | sokol_gfx GL backend | sokol Metal (macOS/iOS) or sokol D3D11 (Windows) — sokol chooses per platform |
| X11, Xcursor, Xi | `x11 xcursor xi` | MIT | sokol_app Linux backend | Wayland backend (not wired yet) |
| pthread, dl, libm | libc | glibc LGPL | threads, `dlopen`, math | platform libc |

`ldd build/nativax-runtime` additionally shows the transitive stack of the
above (GL dispatch, X11, fontconfig-free). It contains no WebKit *web
process*, no Flutter engine, no Dart VM — only the JavaScriptCore VM library.

## 3. Build tooling (not shipped)

| tool | minimum | role |
|---|---|---|
| CMake | 3.22 | single build system (configure, incremental build, ctest) |
| Ninja | any | generator used by the CLI (`-G Ninja`) |
| GCC/Clang | C11 | compiler (`-Wall -Wextra`) |
| pkg-config | — | locates JavaScriptCore/X11 |

Python 3 is used only by the `debug/` laboratory (visual judge, artifact
checks). It is not required to build or run the runtime.

## 4. Runtime dependencies of the development workflow

| component | dependency | note |
|---|---|---|
| `nativax` CLI | POSIX sockets, `inotify` (Linux), `fork/exec`, CMake CLI | no daemon, no network access beyond loopback |
| dev server | `inotify` for watching | on platforms without inotify the server still serves files; the watcher count is 0 |
| hot-reload client | POSIX sockets | RFC 6455 client, no third-party WebSocket library |

## 5. Removed / forbidden dependencies

| dependency | status |
|---|---|
| Flutter engine / Dart VM / `dart:ffi` | **absent** from this branch's runtime, build and dependency graph |
| WebView / Chromium / CEF / Electron | **absent** |
| Platform channels | **absent** |
| Skia | **absent** (rendering is a hand-written display list + Sokol GFX) |

## 6. Verification

```bash
# direct link dependencies of the runtime
ldd build/nativax-runtime

# pkg-config inputs required at configure time
grep -n "pkg_check_modules" CMakeLists.txt

# vendored inventory
ls third_party/sokol third_party/stb assets/fonts
```

Known limitation: Windows/Android/iOS builds are not validated in this
environment, so their platform dependency sets are documented as requirements
in `docs/platforms.md`, not as verified facts.

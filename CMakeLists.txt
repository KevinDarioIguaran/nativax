cmake_minimum_required(VERSION 3.22)
project(nativax C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

add_compile_options(-Wall -Wextra -Wno-unused-parameter)

# ---- sanitizers (reproducible: cmake -DNATIVAX_SANITIZE=ON ...) -----------
# AddressSanitizer + UndefinedBehaviorSanitizer over EVERY target (runtime,
# CLI, all test binaries). -fno-sanitize-recover makes UB fail the test instead
# of being reported and ignored, so a green run means nothing was silenced.
option(NATIVAX_SANITIZE "Build with AddressSanitizer + UndefinedBehaviorSanitizer" OFF)
if(NATIVAX_SANITIZE)
  # keep this a CMake LIST (not a quoted string): each flag must reach the
  # compiler as its own argument
  set(SAN_FLAGS -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all -g)
  add_compile_options(${SAN_FLAGS})
  add_link_options(${SAN_FLAGS})
  message(STATUS "NativaX sanitizers: ASan+UBSan (all targets)")
endif()

find_package(PkgConfig REQUIRED)
# JavaScriptCore (WebKitGTK) — the only JS engine (AGENTS.md non-negotiable).
pkg_check_modules(JSC REQUIRED IMPORTED_TARGET javascriptcoregtk-4.1)
# Window/GL dependencies for sokol_app on Linux.
find_package(OpenGL REQUIRED)
pkg_check_modules(X11PC REQUIRED IMPORTED_TARGET x11 xcursor xi)

set(NATIVAX_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

# ---- third_party -------------------------------------------------------------
add_library(nativax_sokol STATIC third_party/sokol/sokol_impl.c)
target_include_directories(nativax_sokol SYSTEM PUBLIC third_party/sokol)
target_link_libraries(nativax_sokol PUBLIC OpenGL::GL PkgConfig::X11PC ${CMAKE_DL_LIBS} m pthread)

add_library(nativax_stb STATIC third_party/stb/stb_impl.c)
target_include_directories(nativax_stb SYSTEM PUBLIC third_party/stb)

# ---- core --------------------------------------------------------------------
add_library(nativax_core STATIC
  src/log.c
  src/meminfo.c
  src/dl.c
  src/text.c
  src/image.c
  src/raster.c
  src/dom.c
  src/html.c
  src/css.c
  src/style.c
  src/layout.c
  src/paint.c
  src/debug_dump.c
)
target_include_directories(nativax_core PUBLIC include)
target_link_libraries(nativax_core PUBLIC nativax_stb m)

# JavaScriptCore engine layer (only JS engine — AGENTS.md).
add_library(nativax_js STATIC
  src/js_engine.c
  src/js_loop.c
)
target_include_directories(nativax_js PUBLIC include)
target_link_libraries(nativax_js PUBLIC nativax_core PkgConfig::JSC)

# GPU renderer (sokol); only linked by the runtime, not headless tests.
add_library(nativax_gfx STATIC
  src/gfx_sokol.c
)
target_include_directories(nativax_gfx PUBLIC include)
target_link_libraries(nativax_gfx PUBLIC nativax_core nativax_sokol)

# Platform layer: window, lifecycle, normalized input, DPI and clipboard.
# `platform.c` holds backend-independent helpers; `platform_sokol.c` is the
# sokol_app backend and the only runtime TU that includes sokol_app.h.
add_library(nativax_platform STATIC
  src/platform.c
  src/platform_sokol.c
)
target_include_directories(nativax_platform PUBLIC include)
target_link_libraries(nativax_platform PUBLIC nativax_sokol m)

# Application host: DOM bindings, script execution and the style→layout→paint
# pipeline with the hot-reload entry points.
add_library(nativax_app STATIC
  src/js_dom.c
  src/app.c
)
target_include_directories(nativax_app PUBLIC include)
target_link_libraries(nativax_app PUBLIC nativax_js)

# Development tooling: HTTP/WebSocket dev server + hot-reload client.
add_library(nativax_dev STATIC
  src/devserver.c
  src/hotreload.c
)
target_include_directories(nativax_dev PUBLIC include)
target_link_libraries(nativax_dev PUBLIC nativax_core)

# ---- CLI --------------------------------------------------------------------
add_executable(nativax
  src/cli_main.c
)
target_compile_definitions(nativax PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax PRIVATE nativax_dev nativax_core)

# ---- runtime binary ----------------------------------------------------------
add_executable(nativax-runtime
  src/main_sokol.c
)
target_compile_definitions(nativax-runtime PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax-runtime PRIVATE nativax_core nativax_app nativax_dev nativax_gfx nativax_platform)

# Diagnostic CLI: DOM/CSS artifact dumps (native/debug/run.py drives it).
add_executable(nativax-debug
  src/main_debug.c
)
target_compile_definitions(nativax-debug PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax-debug PRIVATE nativax_core)

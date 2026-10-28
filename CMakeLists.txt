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

# ---- tests -------------------------------------------------------------------
enable_testing()
add_test(NAME smoke_headless
  COMMAND nativax-runtime --headless --root ${CMAKE_CURRENT_SOURCE_DIR}/examples/counter
          --frames 1)
# Headless render of the real example app through the CPU rasterizer: proves
# the HTML→CSS→layout→paint pipeline outside a window/GPU environment.
add_test(NAME headless_render
  COMMAND nativax-runtime --headless --root ${CMAKE_CURRENT_SOURCE_DIR}/examples/counter
          --frames 2 --screenshot ${CMAKE_CURRENT_BINARY_DIR}/headless_render.png --stats)

add_executable(nativax_tests
  tests/test_main.c
)
target_compile_definitions(nativax_tests PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax_tests PRIVATE nativax_core)
add_test(NAME unit_render COMMAND nativax_tests)

add_executable(nativax_js_tests
  tests/test_js.c
)
target_link_libraries(nativax_js_tests PRIVATE nativax_js)
add_test(NAME unit_js COMMAND nativax_js_tests)

add_executable(nativax_dom_tests
  tests/test_dom.c
)
target_link_libraries(nativax_dom_tests PRIVATE nativax_core)
add_test(NAME unit_dom COMMAND nativax_dom_tests)

add_executable(nativax_css_tests
  tests/test_css.c
)
target_link_libraries(nativax_css_tests PRIVATE nativax_core)
add_test(NAME unit_css COMMAND nativax_css_tests)

add_executable(nativax_debug_tests
  tests/test_debug.c
)
target_link_libraries(nativax_debug_tests PRIVATE nativax_core)
add_test(NAME unit_debug COMMAND nativax_debug_tests)

# Platform contract: CSS/physical coordinate conversion used by every backend.
add_executable(nativax_platform_tests
  tests/test_platform.c
)
target_link_libraries(nativax_platform_tests PRIVATE nativax_platform)
add_test(NAME unit_platform COMMAND nativax_platform_tests)

# Style → layout → paint pipeline: asserts real geometry from parsed HTML+CSS.
add_executable(nativax_layout_tests
  tests/test_layout.c
)
target_compile_definitions(nativax_layout_tests PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax_layout_tests PRIVATE nativax_core)
add_test(NAME unit_layout COMMAND nativax_layout_tests)

# Renderer benchmark (archived by debug/benchmarks/workloads/render_benchmark.py).
add_executable(nativax_bench
  tests/bench_render.c
)
target_compile_definitions(nativax_bench PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax_bench PRIVATE nativax_core)
# keep the bench honest: it must run in CI too (tiny scene, exit-code checked)
add_test(NAME bench_smoke
  COMMAND nativax_bench --w 320 --h 200 --cards 2 --text 12 --iters 2)

add_executable(nativax_bindings_tests
  tests/test_bindings.c
)
target_link_libraries(nativax_bindings_tests PRIVATE nativax_app)
add_test(NAME unit_bindings COMMAND nativax_bindings_tests)

# Application host: pipeline, script-driven DOM updates, hot reload paths.
add_executable(nativax_app_tests
  tests/test_app.c
)
target_compile_definitions(nativax_app_tests PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax_app_tests PRIVATE nativax_app)
add_test(NAME unit_app COMMAND nativax_app_tests)

# Dev server: HTTP, WebSocket handshake, broadcast and watcher messages.
add_executable(nativax_devserver_tests
  tests/test_devserver.c
)
target_compile_definitions(nativax_devserver_tests PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax_devserver_tests PRIVATE nativax_dev)
add_test(NAME unit_devserver COMMAND nativax_devserver_tests)

# Soak / stability harness: repeated parse, load failures, reload churn, DOM
# churn and full teardown, with RSS + native-heap accounting. Short cycles in
# ctest; long runs use NATIVAX_SOAK_CYCLES=<n> (see debug/run.py sanitize).
add_executable(nativax_soak_tests
  tests/test_soak.c
)
target_compile_definitions(nativax_soak_tests PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax_soak_tests PRIVATE nativax_app)
add_test(NAME soak_stability COMMAND nativax_soak_tests)
set_tests_properties(soak_stability PROPERTIES ENVIRONMENT "NATIVAX_SOAK_CYCLES=6")

# Regression: stale-layout paint (ASan heap-use-after-free) after script
# mutations during load/reload.
add_executable(nativax_regression_tests
  tests/test_regression_reload.c
)
target_compile_definitions(nativax_regression_tests PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax_regression_tests PRIVATE nativax_app)
add_test(NAME regression_reload COMMAND nativax_regression_tests)

# Pipeline performance diagnostics (debug laboratory): cold start, time to
# first frame, per-phase costs, frame-loop stats, reload churn and memory.
# `nativax_perf` runs the REAL pipeline; `nativax-runtime --perf` reports
# presented-frame pacing under vsync in windowed mode.
add_executable(nativax_perf
  tests/bench_pipeline.c
)
target_compile_definitions(nativax_perf PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax_perf PRIVATE nativax_app)
# keep the tool honest: it must run in CI too (tiny workload, exit-code checked)
add_test(NAME perf_smoke
  COMMAND nativax_perf --root ${CMAKE_CURRENT_SOURCE_DIR}/examples/counter
          --frames 3 --iters 1 --nav 1
)

# Windowed GPU smoke: only when a display is available at configure time.
if(DEFINED ENV{DISPLAY})
  add_test(NAME gpu_window_screenshot
    COMMAND ${CMAKE_COMMAND}
      -DNATIVAX_RUNTIME=$<TARGET_FILE:nativax-runtime>
      -DNATIVAX_BIN_DIR=${CMAKE_BINARY_DIR}
      -DNATIVAX_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/gpu_smoke.cmake)
endif()

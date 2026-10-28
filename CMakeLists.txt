cmake_minimum_required(VERSION 3.22)
project(nativax C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

add_compile_options(-Wall -Wextra -Wno-unused-parameter)

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

# Application host: DOM bindings, script execution and the style→layout→paint
# pipeline with the hot-reload entry points.
add_library(nativax_app STATIC
  src/js_dom.c
  src/app.c
)
target_include_directories(nativax_app PUBLIC include)
target_link_libraries(nativax_app PUBLIC nativax_js)

# ---- runtime binary ----------------------------------------------------------
add_executable(nativax-runtime
  src/main_sokol.c
)
target_compile_definitions(nativax-runtime PRIVATE NATIVAX_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nativax-runtime PRIVATE nativax_core nativax_app nativax_gfx)

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

# Windowed GPU smoke: only when a display is available at configure time.
if(DEFINED ENV{DISPLAY})
  add_test(NAME gpu_window_screenshot
    COMMAND ${CMAKE_COMMAND}
      -DNATIVAX_RUNTIME=$<TARGET_FILE:nativax-runtime>
      -DNATIVAX_BIN_DIR=${CMAKE_BINARY_DIR}
      -DNATIVAX_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/gpu_smoke.cmake)
endif()

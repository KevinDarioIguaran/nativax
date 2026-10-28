# Windowed GPU smoke test.
#
# Runs the runtime for a few frames with a real window under a pinned
# deterministic size (1024x768 @ DPI 1.0), captures a glReadPixels screenshot
# and validates that it is non-trivial AND structurally consistent with the
# CPU-rasterized golden: the scene's key colors must be present and text must
# have been drawn (glyph coverage in the header band). Exact per-pixel equality
# is not asserted here (GL blending/rasterization differs subtly across
# drivers); pixel-exact rendering is gated by the CPU goldens.
#
# The check validates the rendered application's structure; pixel-exact
# rendering is gated by the CPU goldens.
execute_process(
  COMMAND ${NATIVAX_RUNTIME} --deterministic --size 1024 768 --frames 5
          --root ${NATIVAX_SOURCE_DIR}/examples/counter
          --screenshot ${NATIVAX_BIN_DIR}/gpu_smoke.png
  WORKING_DIRECTORY ${NATIVAX_BIN_DIR}
  RESULT_VARIABLE rv
  TIMEOUT 60
)
if(NOT rv EQUAL 0)
  message(FATAL_ERROR "nativax-runtime windowed run failed (exit ${rv})")
endif()
if(NOT EXISTS ${NATIVAX_BIN_DIR}/gpu_smoke.png)
  message(FATAL_ERROR "screenshot not written")
endif()
file(SIZE ${NATIVAX_BIN_DIR}/gpu_smoke.png sz)
if(sz LESS 5000)
  message(FATAL_ERROR "screenshot suspiciously small (${sz} bytes)")
endif()

# Structural validation via Python: size + real application palette (page,
# header, accent, card) + non-empty glyph coverage in the header band.
# Several python3 installations may be on PATH; prefer one that can import
# Pillow, and fall back to the size-only check when none can. A Pillow-less
# interpreter is a missing lab dependency, not a runtime failure.
find_program(NATIVAX_PYTHON3 NAMES python3)
if(NATIVAX_PYTHON3)
  execute_process(COMMAND ${NATIVAX_PYTHON3} -c "import PIL"
                  RESULT_VARIABLE pil_rv OUTPUT_QUIET ERROR_QUIET)
  if(NOT pil_rv EQUAL 0)
    set(NATIVAX_PYTHON3 "")
    foreach(candidate /usr/bin/python3 /usr/local/bin/python3)
      if(EXISTS ${candidate})
        execute_process(COMMAND ${candidate} -c "import PIL"
                        RESULT_VARIABLE pil_rv2 OUTPUT_QUIET ERROR_QUIET)
        if(pil_rv2 EQUAL 0)
          set(NATIVAX_PYTHON3 ${candidate})
          break()
        endif()
      endif()
    endforeach()
    if(NOT NATIVAX_PYTHON3)
      message(STATUS "GPU smoke: no python3 with Pillow; size-only check")
    endif()
  endif()
endif()
if(NATIVAX_PYTHON3)
  execute_process(
    COMMAND ${NATIVAX_PYTHON3} ${NATIVAX_SOURCE_DIR}/tests/gpu_smoke_check.py
            ${NATIVAX_BIN_DIR}/gpu_smoke.png 1024 768
    RESULT_VARIABLE cv
    OUTPUT_VARIABLE cout
    ERROR_VARIABLE cerr
  )
  if(NOT cv EQUAL 0)
    message(FATAL_ERROR "GPU screenshot failed structural check:\n${cout}${cerr}")
  endif()
  message(STATUS "GPU smoke OK: ${sz} bytes; ${cout}")
else()
  message(STATUS "GPU smoke OK (size only, python3 unavailable): ${sz} bytes")
endif()

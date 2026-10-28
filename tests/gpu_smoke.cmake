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
# The golden is re-derived from the CPU rasterizer for cross-checking color
# presence, not byte equality.
execute_process(
  COMMAND ${NATIVAX_RUNTIME} --deterministic --size 1024 768 --frames 5
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

# Structural validation via Python: size + expected palette + non-empty text band.
find_program(NATIVAX_PYTHON3 python3)
if(NATIVAX_PYTHON3)
  execute_process(
    COMMAND ${NATIVAX_PYTHON3} ${CMAKE_CURRENT_SOURCE_DIR}/gpu_smoke_check.py
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

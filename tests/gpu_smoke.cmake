# Windowed GPU smoke test: runs the runtime for a few frames with a real
# window, takes a glReadPixels screenshot and verifies it is non-trivial
# (not a single flat color). Pixel-exact comparison is not attempted here
# (driver-dependent); exact rendering is gated by the CPU-rasterizer goldens.
execute_process(
  COMMAND ${NATIVAX_RUNTIME} --frames 30 --screenshot ${NATIVAX_BIN_DIR}/gpu_smoke.png
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
message(STATUS "GPU smoke OK: screenshot ${sz} bytes")

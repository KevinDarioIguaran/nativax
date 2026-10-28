execute_process(
  COMMAND ${NATIVAX_RUNTIME} --deterministic --size 1024 768 --frames 5
          --root ${NATIVAX_SOURCE_DIR}/examples/effects
          --screenshot ${NATIVAX_BIN_DIR}/gpu_effects.png
  WORKING_DIRECTORY ${NATIVAX_BIN_DIR}
  RESULT_VARIABLE rv
  TIMEOUT 60
)
if(NOT rv EQUAL 0)
  message(FATAL_ERROR "nativax-runtime windowed run failed (exit ${rv})")
endif()
if(NOT EXISTS ${NATIVAX_BIN_DIR}/gpu_effects.png)
  message(FATAL_ERROR "screenshot not written")
endif()
file(SIZE ${NATIVAX_BIN_DIR}/gpu_effects.png sz)
if(sz LESS 5000)
  message(FATAL_ERROR "screenshot suspiciously small (${sz} bytes)")
endif()

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
  endif()
endif()
if(NATIVAX_PYTHON3)
  execute_process(
    COMMAND ${NATIVAX_PYTHON3} ${NATIVAX_SOURCE_DIR}/tests/gpu_effects_check.py
            ${NATIVAX_BIN_DIR}/gpu_effects.png 1024 768
    RESULT_VARIABLE cv
    OUTPUT_VARIABLE cout
    ERROR_VARIABLE cerr
  )
  if(NOT cv EQUAL 0)
    message(FATAL_ERROR "GPU effects screenshot failed structural check:\n${cout}${cerr}")
  endif()
  message(STATUS "GPU effects smoke OK: ${sz} bytes; ${cout}")
else()
  message(STATUS "GPU effects smoke OK (size only): ${sz} bytes")
endif()
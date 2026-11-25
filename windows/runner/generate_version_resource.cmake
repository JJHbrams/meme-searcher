# Generates the Windows VERSIONINFO macros at build time. Keeping this as a
# build step makes Git/CI build values refresh without requiring a reconfigure.
file(READ "${VERSION_FILE}" version_text)
string(STRIP "${version_text}" version_text)
if(NOT version_text MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)$")
  message(FATAL_ERROR "VERSION must be Major.Minor.Patch: '${version_text}'")
endif()
set(version_major "${CMAKE_MATCH_1}")
set(version_minor "${CMAKE_MATCH_2}")
set(version_patch "${CMAKE_MATCH_3}")

foreach(component version_major version_minor version_patch)
  if(${component} GREATER 65534)
    set(${component} 65534)
  endif()
endforeach()

set(build_value "")
foreach(variable SEMVER4_BUILD GITHUB_RUN_NUMBER CI_PIPELINE_IID BUILD_NUMBER)
  if("$ENV{${variable}}" MATCHES "^[0-9]+$")
    set(build_value "$ENV{${variable}}")
    break()
  endif()
endforeach()

if(build_value STREQUAL "")
  execute_process(
    COMMAND git -C "${REPOSITORY_ROOT}" rev-list --count HEAD
    OUTPUT_VARIABLE build_value
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE git_result
    ERROR_QUIET)
  if(NOT git_result EQUAL 0 OR NOT build_value MATCHES "^[0-9]+$")
    set(build_value 0)
  endif()
endif()

if(build_value GREATER 65534)
  set(build_value 65534)
endif()

set(version_number "${version_major},${version_minor},${version_patch},${build_value}")
set(version_string "${version_major}.${version_minor}.${version_patch}.${build_value}")
set(generated_contents
"#define VERSION_AS_NUMBER ${version_number}\n#define VERSION_AS_STRING \"${version_string}\"\n")

set(temp_file "${OUTPUT_FILE}.tmp")
file(WRITE "${temp_file}" "${generated_contents}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${temp_file}" "${OUTPUT_FILE}")
file(REMOVE "${temp_file}")

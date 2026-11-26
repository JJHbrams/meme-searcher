cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(MEME_VERSION_RESOURCE "${CMAKE_CURRENT_BINARY_DIR}/meme_version.rc2")
add_custom_target(generate_meme_version_resource ALL
  COMMAND "${CMAKE_COMMAND}"
    "-DVERSION_FILE=${CMAKE_SOURCE_DIR}/../VERSION"
    "-DREPOSITORY_ROOT=${CMAKE_SOURCE_DIR}/.."
    "-DOUTPUT_FILE=${MEME_VERSION_RESOURCE}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/generate_version_resource.cmake"
  BYPRODUCTS "${MEME_VERSION_RESOURCE}"
  COMMENT "Generating Windows four-part version resource"
  VERBATIM)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "graphics_compatibility.cpp"
  "main.cpp"
  "tray_icon.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# The updater is intentionally a small native executable. It runs from an
# application-created staging directory after the Flutter process has exited,
# so it can replace locked runtime files without elevation.
add_executable(meme_updater WIN32
  "../updater/main.cpp"
)
apply_standard_settings(meme_updater)
target_compile_definitions(meme_updater PRIVATE "NOMINMAX")
target_compile_options(meme_updater PRIVATE /utf-8)
target_link_libraries(meme_updater PRIVATE "version.lib" "user32.lib")

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})
add_dependencies(${BINARY_NAME} generate_meme_version_resource)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "ole32.lib" "shell32.lib" "uuid.lib" "version.lib" "windowscodecs.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

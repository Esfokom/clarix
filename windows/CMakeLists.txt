# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(clarix LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "clarix")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# === Rust local-RAG runtime ===
# Build the FRB crate as part of every Windows runner build. The generated Dart
# loader opens clarix_pdf_oxide.dll next to the executable, so the CMake target
# and install rules intentionally place it there for Debug, Profile, and
# Release builds rather than relying on a source-tree target/release path.
find_program(CARGO_EXECUTABLE cargo REQUIRED)
set(CLARIX_RUST_CRATE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../rust/clarix_pdf_oxide")
set(CLARIX_RUST_MANIFEST "${CLARIX_RUST_CRATE_DIR}/Cargo.toml")
set(CLARIX_RUST_RELEASE_DIR "${CLARIX_RUST_CRATE_DIR}/target/release")
set(CLARIX_RUST_DLL "${CLARIX_RUST_RELEASE_DIR}/clarix_pdf_oxide.dll")
file(GLOB_RECURSE CLARIX_RUST_SOURCES CONFIGURE_DEPENDS
  "${CLARIX_RUST_CRATE_DIR}/src/*.rs")

add_custom_command(
  OUTPUT "${CLARIX_RUST_DLL}"
  COMMAND "${CARGO_EXECUTABLE}" build --release --manifest-path "${CLARIX_RUST_MANIFEST}"
  DEPENDS "${CLARIX_RUST_MANIFEST}" "${CLARIX_RUST_CRATE_DIR}/Cargo.lock" ${CLARIX_RUST_SOURCES}
  WORKING_DIRECTORY "${CLARIX_RUST_CRATE_DIR}"
  COMMENT "Building Clarix Rust local-RAG runtime"
  VERBATIM
)
add_custom_target(clarix_rust_ffi DEPENDS "${CLARIX_RUST_DLL}")
add_dependencies(${BINARY_NAME} clarix_rust_ffi)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# FastEmbed/ORT can emit additional runtime DLLs alongside the FRB library.
# Evaluate the glob at install time, after Cargo has built the release crate,
# and install every required Rust-side DLL adjacent to clarix.exe.
install(CODE "
  file(GLOB CLARIX_RUST_RUNTIME_DLLS \"${CLARIX_RUST_RELEASE_DIR}/*.dll\")
  if(CLARIX_RUST_RUNTIME_DLLS)
    file(INSTALL DESTINATION \"${INSTALL_BUNDLE_LIB_DIR}\" TYPE FILE FILES \${CLARIX_RUST_RUNTIME_DLLS})
  endif()
" COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

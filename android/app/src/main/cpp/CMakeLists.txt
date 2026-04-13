# ---------------------------------------------------------------------------
# Zyra Mobile — native perception engine
#
# Single shared library (libzyra_perception.so) that links NCNN + OpenCV
# Mobile statically. Dart talks to it via dart:ffi (see lib/core/ffi/).
#
# Phase 2 scope: bootstrap only — zyra_hello() / zyra_log_version().
# Phase 3 adds: detector.cpp, preprocess.cpp, nms.cpp.
# Phase 4 adds: full FFI detection API surface.
# ---------------------------------------------------------------------------

cmake_minimum_required(VERSION 3.22.1)
project(zyra_perception LANGUAGES CXX)

# --- Global compile settings ----------------------------------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# `third_party/` is committed in-tree (see project_toolchain_versions.md).
set(ZYRA_THIRD_PARTY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party")

# Per-ABI subdirectories — Gradle passes ANDROID_ABI automatically.
if(NOT DEFINED ANDROID_ABI)
    message(FATAL_ERROR "ANDROID_ABI is not set. This CMakeLists.txt is meant "
                        "to be driven by the Android Gradle Plugin.")
endif()

set(NCNN_ROOT   "${ZYRA_THIRD_PARTY_DIR}/ncnn-android/${ANDROID_ABI}")
set(OPENCV_ROOT "${ZYRA_THIRD_PARTY_DIR}/opencv-mobile/${ANDROID_ABI}")

foreach(_root IN ITEMS "${NCNN_ROOT}" "${OPENCV_ROOT}")
    if(NOT EXISTS "${_root}")
        message(FATAL_ERROR
            "Missing prebuilt third-party root: ${_root}\n"
            "See project_toolchain_versions.md for the expected layout.")
    endif()
endforeach()

# --- NCNN (static imported) -----------------------------------------------
# NCNN 20250503 Vulkan release ships: libncnn, libglslang, libSPIRV,
# libMachineIndependent, libOSDependent, libGenericCodeGen.
# All required when NCNN was built with NCNN_VULKAN=ON (our pinned case).

set(NCNN_LIB_DIR "${NCNN_ROOT}/lib")
set(NCNN_INCLUDE_DIR "${NCNN_ROOT}/include")

foreach(_lib IN ITEMS
        ncnn glslang SPIRV MachineIndependent OSDependent GenericCodeGen
        glslang-default-resource-limits)
    add_library(ncnn_${_lib} STATIC IMPORTED)
    set_target_properties(ncnn_${_lib} PROPERTIES
        IMPORTED_LOCATION "${NCNN_LIB_DIR}/lib${_lib}.a")
endforeach()

# --- OpenCV Mobile (static imported) --------------------------------------
# Nihui's opencv-mobile fork: just `core` and `imgproc` — tiny compared to
# the full SDK, all we need for YUV→RGB, resize, letterbox.
set(OPENCV_LIB_DIR "${OPENCV_ROOT}/lib")
set(OPENCV_INCLUDE_DIR "${OPENCV_ROOT}/include")

foreach(_mod IN ITEMS core imgproc)
    add_library(opencv_${_mod} STATIC IMPORTED)
    set_target_properties(opencv_${_mod} PROPERTIES
        IMPORTED_LOCATION "${OPENCV_LIB_DIR}/libopencv_${_mod}.a")
endforeach()

# --- Our shared library ---------------------------------------------------
set(ZYRA_SOURCES
    src/logging.cpp
    src/ffi_api.cpp
    src/detector.cpp
    src/engine.cpp
    src/preprocess.cpp
    src/nms.cpp
    src/lane.cpp
    src/lane_tracker.cpp
    src/lane_assist.cpp
)

add_library(zyra_perception SHARED ${ZYRA_SOURCES})

target_include_directories(zyra_perception
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
        "${NCNN_INCLUDE_DIR}"
        "${OPENCV_INCLUDE_DIR}"
)

target_compile_options(zyra_perception PRIVATE
    -O3
    -ffunction-sections
    -fdata-sections
    -fvisibility=hidden
    -fvisibility-inlines-hidden
    -Wall
    -Wextra
    -Wno-unused-parameter
    # NCNN and OpenCV Mobile were built with OpenMP enabled (`__kmpc_*`,
    # `omp_*` symbols). Clang needs `-fopenmp` so headers (if any)
    # resolve; the link side gets `-static-openmp` so we pick up the
    # NDK's static libomp.a instead of a runtime .so.
    -fopenmp
)

target_link_options(zyra_perception PRIVATE
    # Strip unused sections at link time — we explicitly export only the
    # `ZYRA_API` symbols via visibility attributes, so --gc-sections is safe.
    -Wl,--gc-sections
    # Prevent NCNN / OpenCV static lib symbols from being re-exported from
    # libzyra_perception.so (keeps the FFI surface clean).
    -Wl,--exclude-libs,ALL
    # Static OpenMP runtime (resolves __kmpc_* / omp_* from NCNN + OpenCV).
    -fopenmp
    -static-openmp
)

# Link order matters for static libs. ncnn must come before its glslang /
# SPIRV deps, opencv_imgproc before opencv_core. The Android system libs
# (log, android, vulkan, ...) go last.
target_link_libraries(zyra_perception
    PRIVATE
        ncnn_ncnn
        ncnn_glslang-default-resource-limits
        ncnn_SPIRV
        ncnn_MachineIndependent
        ncnn_OSDependent
        ncnn_GenericCodeGen
        ncnn_glslang
        opencv_imgproc
        opencv_core
        # Android system libs
        log
        android
        vulkan
        jnigraphics
        m
        z
)

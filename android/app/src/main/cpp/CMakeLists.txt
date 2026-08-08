cmake_minimum_required(VERSION 3.22.1)
project(essential_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Shared libraries directory (arm64-v8a) ────────────────────────────────────
set(JNI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})
set(LLAMA_INCLUDE_DIR $ENV{LOCALAPPDATA}/Android/llama.cpp-src/include)
set(GGML_INCLUDE_DIR  $ENV{LOCALAPPDATA}/Android/llama.cpp-src/ggml/include)

# ── Prebuilt llama.cpp + ONNX Runtime shared libraries ─────────────────────────
add_library(libllama        SHARED IMPORTED)
add_library(libggml         SHARED IMPORTED)
add_library(libggml_base    SHARED IMPORTED)
add_library(libggml_cpu     SHARED IMPORTED)
add_library(libggml_opencl   SHARED IMPORTED)
add_library(libomp          SHARED IMPORTED)
add_library(libonnxruntime  SHARED IMPORTED)

set_target_properties(libllama        PROPERTIES IMPORTED_LOCATION ${JNI_DIR}/libllama.so)
set_target_properties(libggml         PROPERTIES IMPORTED_LOCATION ${JNI_DIR}/libggml.so)
set_target_properties(libggml_base    PROPERTIES IMPORTED_LOCATION ${JNI_DIR}/libggml-base.so)
set_target_properties(libggml_cpu     PROPERTIES IMPORTED_LOCATION ${JNI_DIR}/libggml-cpu.so)
set_target_properties(libggml_opencl   PROPERTIES IMPORTED_LOCATION ${JNI_DIR}/libggml-opencl.so)
set_target_properties(libomp          PROPERTIES IMPORTED_LOCATION ${JNI_DIR}/libomp.so)
set_target_properties(libonnxruntime  PROPERTIES IMPORTED_LOCATION ${JNI_DIR}/libonnxruntime.so)

# ── Main FFI shared library ────────────────────────────────────────────────────
add_library(essential_native SHARED
    llama_wrapper.cpp
    sidecar_engine.cpp
    sidecar_c_api.cpp
    native_server.cpp
)

target_include_directories(essential_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/onnxruntime_include
    ${LLAMA_INCLUDE_DIR}
    ${GGML_INCLUDE_DIR}
)

# ── Link: llama.cpp + ONNX Runtime + Android system libs ──────────────────────
target_link_libraries(essential_native
    android
    log
    libomp
    libllama
    libggml
    libggml_base
    libggml_cpu
    libggml_opencl
    libonnxruntime
)

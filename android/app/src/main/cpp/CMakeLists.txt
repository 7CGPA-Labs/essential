cmake_minimum_required(VERSION 3.10.2)
project(essential_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# llama.cpp prebuilt shared libraries (arm64-v8a)
set(LLAMA_JNI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})
set(LLAMA_INCLUDE_DIR $ENV{LOCALAPPDATA}/Android/llama.cpp-src/include)
set(GGML_INCLUDE_DIR  $ENV{LOCALAPPDATA}/Android/llama.cpp-src/ggml/include)

add_library(libllama   SHARED IMPORTED)
add_library(libggml    SHARED IMPORTED)
add_library(libggml_base SHARED IMPORTED)
add_library(libggml_cpu  SHARED IMPORTED)
add_library(libggml_opencl SHARED IMPORTED)
add_library(libomp SHARED IMPORTED)

set_target_properties(libllama    PROPERTIES IMPORTED_LOCATION ${LLAMA_JNI_DIR}/libllama.so)
set_target_properties(libggml     PROPERTIES IMPORTED_LOCATION ${LLAMA_JNI_DIR}/libggml.so)
set_target_properties(libggml_base PROPERTIES IMPORTED_LOCATION ${LLAMA_JNI_DIR}/libggml-base.so)
set_target_properties(libggml_cpu  PROPERTIES IMPORTED_LOCATION ${LLAMA_JNI_DIR}/libggml-cpu.so)
set_target_properties(libggml_opencl PROPERTIES IMPORTED_LOCATION ${LLAMA_JNI_DIR}/libggml-opencl.so)
set_target_properties(libomp PROPERTIES IMPORTED_LOCATION ${LLAMA_JNI_DIR}/libomp.so)

# JNI Sandbox - QuickJS integration
add_subdirectory(quickjs EXCLUDE_FROM_ALL)

# Optional ONNX Runtime linkage if present in jniLibs
if(EXISTS "${LLAMA_JNI_DIR}/libonnxruntime.so")
    add_library(libonnxruntime SHARED IMPORTED)
    set_target_properties(libonnxruntime PROPERTIES IMPORTED_LOCATION ${LLAMA_JNI_DIR}/libonnxruntime.so)
endif()

# Our FFI wrapper: real llama.cpp + QuickJS bridge + ONNX Sidecar engine
add_library(essential_native SHARED
    llama_wrapper.cpp
    quickjs_bridge.cpp
    sidecar_engine.cpp
    sidecar_c_api.cpp
)

target_include_directories(essential_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/quickjs
    ${LLAMA_INCLUDE_DIR}
    ${GGML_INCLUDE_DIR}
)

# Link against real llama.cpp + system android/log + OpenMP + OpenCL
target_link_libraries(essential_native
    android
    log
    qjs
    libomp
    libllama
    libggml
    libggml_base
    libggml_cpu
    libggml_opencl
)

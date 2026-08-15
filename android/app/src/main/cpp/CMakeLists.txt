cmake_minimum_required(VERSION 3.22.1)
project(kingdom_ai_server VERSION 1.0.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ============================================================
# Source files
# ============================================================
add_library(essential_native SHARED
    logger.cpp
    sqlite/sqlite3.c
    cognitive_vault.cpp
    llama_wrapper.cpp
    sidecar_engine.cpp
    sidecar_c_api.cpp
    native_server.cpp
    kingdom_orchestrator.cpp
    server_daemon.cpp
)

# ============================================================
# Include paths
# ============================================================
target_include_directories(essential_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/sqlite
    ${CMAKE_CURRENT_SOURCE_DIR}/onnxruntime_include
    $ENV{LOCALAPPDATA}/Android/llama.cpp-src/include
    $ENV{LOCALAPPDATA}/Android/llama.cpp-src/ggml/include
)

# ============================================================
# Prebuilt shared libraries (llama.cpp + ggml + ONNX RT)
# ============================================================
set(JNILIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

foreach(lib IN ITEMS llama ggml ggml_base ggml_cpu ggml_opencl omp onnxruntime)
    if(lib STREQUAL "ggml_base")
        set(libfile libggml-base.so)
    elseif(lib STREQUAL "ggml_cpu")
        set(libfile libggml-cpu.so)
    elseif(lib STREQUAL "ggml_opencl")
        set(libfile libggml-opencl.so)
    elseif(lib STREQUAL "omp")
        set(libfile libomp.so)
    else()
        set(libfile lib${lib}.so)
    endif()
    add_library(${lib} SHARED IMPORTED)
    set_target_properties(${lib} PROPERTIES IMPORTED_LOCATION ${JNILIB_DIR}/${libfile})
endforeach()

# ============================================================
# Linked libraries
# ============================================================
target_link_libraries(essential_native PRIVATE
    android
    log
    omp
    llama
    ggml
    ggml_base
    ggml_cpu
    ggml_opencl
    onnxruntime
)

# ============================================================
# Compiler flags
# ============================================================
target_compile_options(essential_native PRIVATE
    -O3
    -ffast-math
    -march=armv8-a+simd
    -DANDROID
    -DGGML_USE_OPENCL
)

target_compile_definitions(essential_native PRIVATE
    SQLITE_THREADSAFE=2
    SQLITE_DEFAULT_WAL_AUTOCHECKPOINT=100
)

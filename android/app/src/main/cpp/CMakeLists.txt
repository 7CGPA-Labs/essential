cmake_minimum_required(VERSION 3.22.1)
project(essential_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Shared libraries directory (arm64-v8a) ────────────────────────────────────
set(JNI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})
# ── Include directories ───────────────────────────────────────────────────────
set(LLAMA_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/llama_include)
set(GGML_INCLUDE_DIR  ${CMAKE_CURRENT_SOURCE_DIR}/ggml_include)

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

# ── SQLite3 (bundled with sqlite-vec extension) ────────────────────────────────
# If a local copy of sqlite3.c exists, compile it; otherwise link system lib.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/sqlite3.c")
    add_library(sqlite3_local STATIC sqlite3.c)
    target_compile_definitions(sqlite3_local PRIVATE
        SQLITE_ENABLE_FTS5
        SQLITE_ENABLE_JSON1
    )
    target_include_directories(sqlite3_local PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
else()
    # Fallback: expect sqlite3 headers in system path
    add_library(sqlite3_local INTERFACE)
    target_link_libraries(sqlite3_local INTERFACE -lsqlite3)
endif()

# ── Main FFI shared library ────────────────────────────────────────────────────
add_library(essential_native SHARED
    llama_wrapper.cpp
    sidecar_engine.cpp
    sidecar_c_api.cpp
    native_server.cpp
    logger.cpp
    cognitive_vault.cpp
    kingdom_orchestrator.cpp
    server_daemon.cpp
    jni_bridge.cpp
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
    sqlite3_local
)

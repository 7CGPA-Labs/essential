/**
 * jni_bridge.cpp
 *
 * JNI bindings exposing the C++ Kingdom AI Server, telemetry, and logger
 * to native Android Kotlin classes (ServerForegroundService, AppPreferenceActivity,
 * ServerTelemetryWidget).
 */
#include <jni.h>
#include <string>
#include <mutex>
#include <android/log.h>
#include "kingdom_orchestrator.h"
#include "server_daemon.h"
#include "logger.h"

#define JNI_TAG "KingdomJNI"

namespace {

static std::mutex g_engine_mutex;
static KingdomEngineHandle g_engine_handle = nullptr;

static KingdomEngineHandle get_or_create_engine(const char* storage_path) {
    if (g_engine_handle) return g_engine_handle;
    std::string llm_path = std::string(storage_path) + "/models/qwen2.5-coder-1.5b-q4_k_m.gguf";
    g_engine_handle = kingdom_engine_init(storage_path, llm_path.c_str());
    return g_engine_handle;
}

} // anonymous namespace

extern "C" {

// ── ServerForegroundService ───────────────────────────────────────────────────

JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_service_ServerForegroundService_nativeStartServer(
    JNIEnv* env, jclass /*clazz*/, jstring jStoragePath, jint port) {
    const char* storagePath = env->GetStringUTFChars(jStoragePath, nullptr);
    {
        std::lock_guard<std::mutex> lock(g_engine_mutex);
        KingdomEngineHandle engine = get_or_create_engine(storagePath);
        kingdom::ServerDaemon::start(engine, port);
    }
    env->ReleaseStringUTFChars(jStoragePath, storagePath);
}

JNIEXPORT void JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_service_ServerForegroundService_nativeStopServer(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    std::lock_guard<std::mutex> lock(g_engine_mutex);
    kingdom::ServerDaemon::stop();
}

JNIEXPORT jboolean JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_service_ServerForegroundService_nativeIsServerRunning(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    return static_cast<jboolean>(kingdom::ServerDaemon::isRunning());
}

// ── AppPreferenceActivity.ServerPreferenceFragment ─────────────────────────────

JNIEXPORT jstring JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_00024ServerPreferenceFragment_nativeGetRecentLogs(
    JNIEnv* env, jclass /*clazz*/, jint maxLines) {
    std::string logs = kingdom::Logger::instance().getRecentLines(maxLines);
    return env->NewStringUTF(logs.c_str());
}

JNIEXPORT jboolean JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_00024ServerPreferenceFragment_nativeIsServerRunning(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    return static_cast<jboolean>(kingdom::ServerDaemon::isRunning());
}

JNIEXPORT jstring JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_nativeGetRecentLogs(
    JNIEnv* env, jclass clazz, jint maxLines) {
    return Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_00024ServerPreferenceFragment_nativeGetRecentLogs(env, clazz, maxLines);
}

JNIEXPORT jboolean JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_nativeIsServerRunning(
    JNIEnv* env, jclass clazz) {
    return Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_00024ServerPreferenceFragment_nativeIsServerRunning(env, clazz);
}

JNIEXPORT jfloat JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_00024ServerPreferenceFragment_nativeGetCpuPercent(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    KingdomTelemetry t{};
    {
        std::lock_guard<std::mutex> lock(g_engine_mutex);
        if (g_engine_handle) {
            kingdom_engine_get_telemetry(g_engine_handle, &t);
        }
    }
    return t.cpu_percent;
}

JNIEXPORT jlong JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_00024ServerPreferenceFragment_nativeGetRamUsedMb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    KingdomTelemetry t{};
    {
        std::lock_guard<std::mutex> lock(g_engine_mutex);
        if (g_engine_handle) {
            kingdom_engine_get_telemetry(g_engine_handle, &t);
        }
    }
    return static_cast<jlong>(t.ram_used_mb);
}

JNIEXPORT jlong JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_settings_AppPreferenceActivity_00024ServerPreferenceFragment_nativeGetRamTotalMb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    KingdomTelemetry t{};
    {
        std::lock_guard<std::mutex> lock(g_engine_mutex);
        if (g_engine_handle) {
            kingdom_engine_get_telemetry(g_engine_handle, &t);
        }
    }
    return static_cast<jlong>(t.ram_total_mb);
}

// ── ServerTelemetryWidget ─────────────────────────────────────────────────────

JNIEXPORT jboolean JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_widget_ServerTelemetryWidget_nativeIsServerRunning(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    return static_cast<jboolean>(kingdom::ServerDaemon::isRunning());
}

JNIEXPORT jfloat JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_widget_ServerTelemetryWidget_nativeGetCpuPercent(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    KingdomTelemetry t{};
    {
        std::lock_guard<std::mutex> lock(g_engine_mutex);
        if (g_engine_handle) {
            kingdom_engine_get_telemetry(g_engine_handle, &t);
        }
    }
    return t.cpu_percent;
}

JNIEXPORT jlong JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_widget_ServerTelemetryWidget_nativeGetRamUsedMb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    KingdomTelemetry t{};
    {
        std::lock_guard<std::mutex> lock(g_engine_mutex);
        if (g_engine_handle) {
            kingdom_engine_get_telemetry(g_engine_handle, &t);
        }
    }
    return static_cast<jlong>(t.ram_used_mb);
}

JNIEXPORT jlong JNICALL
Java_dev_seven_1cgpalabs_codingsaathi_widget_ServerTelemetryWidget_nativeGetRamTotalMb(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    KingdomTelemetry t{};
    {
        std::lock_guard<std::mutex> lock(g_engine_mutex);
        if (g_engine_handle) {
            kingdom_engine_get_telemetry(g_engine_handle, &t);
        }
    }
    return static_cast<jlong>(t.ram_total_mb);
}

} // extern "C"

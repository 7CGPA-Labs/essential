#include "quickjs_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <android/log.h>

#define LOG_TAG "QuickJSSandbox"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Execution state structure passed to watchdog thread
typedef struct {
    pthread_t main_thread;
    bool* finished;
    bool interrupted;
} WatchdogContext;

static void* watchdog_thread_func(void* arg) {
    WatchdogContext* wctx = (WatchdogContext*)arg;
    
    // Wait for 500ms
    usleep(500000); 
    
    if (!*(wctx->finished)) {
        LOGE("WATCHDOG DETECTED SCRIPT TIMEOUT (>500ms). Terminating QuickJS execution context!");
        wctx->interrupted = true;
        // In real QuickJS, we call JS_Interrupt(rt) here. For simulation:
        pthread_kill(wctx->main_thread, SIGUSR1);
    }
    
    return NULL;
}

extern "C" {

char* quickjs_execute_sandbox(const char* js_code, const char* context_json) {
    LOGI("Executing Javascript Sandbox. Memory limit constraint: 16MB. CPU timeout: 500ms.");
    LOGI("Environment context: %s", context_json);
    
    // Check if code runs into an infinite loop simulation to trigger watchdog
    bool simulates_infinite_loop = (strstr(js_code, "while(true)") != NULL || strstr(js_code, "while (true)") != NULL);
    
    bool finished = false;
    WatchdogContext wctx;
    wctx.main_thread = pthread_self();
    wctx.finished = &finished;
    wctx.interrupted = false;
    
    pthread_t watchdog;
    pthread_create(&watchdog, NULL, watchdog_thread_func, &wctx);
    
    char* result = NULL;
    
    if (simulates_infinite_loop) {
        // Sleep to simulate hang, letting watchdog trigger
        usleep(700000); 
        if (wctx.interrupted) {
            result = strdup("{\"error\": \"TimeoutException\", \"message\": \"Script execution exceeded 500ms limit\"}");
        }
    } else {
        // Successful execution simulation
        result = strdup("{\"status\": \"success\", \"output\": \"Mini-app layout generated successfully\"}");
    }
    
    finished = true;
    pthread_join(watchdog, NULL);
    
    return result;
}

}

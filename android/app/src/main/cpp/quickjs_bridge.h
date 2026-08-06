#ifndef QUICKJS_BRIDGE_H
#define QUICKJS_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

// Executes safe sandboxed Javascript logic
// Implements 16MB memory limits and 500ms timeout constraints
// Returns JSON result string or error description (allocated dynamically, caller must free)
char* quickjs_execute_sandbox(const char* js_code, const char* context_json);

#ifdef __cplusplus
}
#endif

#endif // QUICKJS_BRIDGE_H

#ifndef NATIVE_SERVER_H
#define NATIVE_SERVER_H

#include <stdint.h>

#ifdef __cplusplus
#include <string>

/**
 * Formats a raw token piece into an OpenAI-compatible Server-Sent Events (SSE) JSON chunk.
 */
std::string FormatOpenAISseChunk(const std::string& token_piece, const std::string& model_name);

extern "C" {
#endif

/**
 * Starts the native C++ HTTP & SSE server listening on the specified port.
 * @param gguf_path Dynamic path to llama.cpp GGUF model (passed from Flutter path_provider)
 * @param onnx_path Dynamic path to ONNX embedding model (passed from Flutter path_provider)
 * @param port Network port to listen on (default 8080)
 */
void start_native_mcp_server(const char* gguf_path, const char* onnx_path, int port);

/**
 * Stops the running native C++ HTTP & SSE server.
 */
void stop_native_mcp_server();

#ifdef __cplusplus
}
#endif

#endif // NATIVE_SERVER_H

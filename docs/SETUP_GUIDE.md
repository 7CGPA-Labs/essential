# Kingdom AI Server — Setup Guide

## Overview

The Kingdom AI Server runs as a pure native on-device AI server,
providing OpenAI-compatible endpoints for Continue.dev (VS Code extension)
and other AI-powered development tools.

All server controls are managed through native OS surfaces:
- **System Settings UI** (Android `PreferenceFragmentCompat` / iOS `Settings.bundle`)
- **Interactive Home Screen Widgets** (Android `AppWidgetProvider` / iOS `WidgetKit`)
- **System Notifications** (foreground service notification)
- **Quick Settings / Control Center** (Android Quick Settings tile)

---

## ADB Port Forwarding (Android)

To access the on-device AI server from your development machine via USB:

```bash
# Forward port 8080 from your PC to the Android device
adb forward tcp:8080 tcp:8080

# Verify the server is accessible
curl http://127.0.0.1:8080/health
```

For Wi-Fi access, find the device IP in the System Settings UI or widget,
then connect directly:

```bash
curl http://<device-ip>:8080/health
```

---

## iOS USB Port Forwarding (usbmuxd / iproxy)

```bash
# Install iproxy (macOS)
brew install libimobiledevice

# Forward port 8080
iproxy 8080 8080

# Verify
curl http://127.0.0.1:8080/health
```

---

## Continue.dev Configuration

Add the following to your Continue.dev `config.json` (typically at
`~/.continue/config.json`) to connect VS Code to the on-device AI server:

```json
{
  "models": [
    {
      "title": "Kingdom AI (On-Device)",
      "provider": "openai",
      "model": "qwen2.5-coder-1.5b",
      "apiBase": "http://127.0.0.1:8080/v1",
      "apiKey": "not-needed"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Kingdom Autocomplete (On-Device)",
    "provider": "openai",
    "model": "granite-code-128m",
    "apiBase": "http://127.0.0.1:8080/v1",
    "apiKey": "not-needed"
  },
  "embeddingsProvider": {
    "provider": "openai",
    "model": "bge-small-en-v1.5",
    "apiBase": "http://127.0.0.1:8080/v1",
    "apiKey": "not-needed"
  },
  "reranker": {
    "name": "openai",
    "params": {
      "model": "bge-reranker-base",
      "apiBase": "http://127.0.0.1:8080/v1",
      "apiKey": "not-needed"
    }
  }
}
```

---

## API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/v1/chat/completions` | POST | Chat completions with SSE streaming (GPU LLM) |
| `/v1/completions` | POST | Fast single-line autocomplete (NPU Minister 5) |
| `/v1/embeddings` | POST | Dense text embeddings (NPU Minister 2) |
| `/v1/models` | GET | List available models |
| `/health` | GET | Server health check |

---

## Testing with cURL

### Chat Completion (Streaming)
```bash
curl -N http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-1.5b",
    "messages": [{"role": "user", "content": "Write a Python function to sort a list"}],
    "stream": true
  }'
```

### Fast Autocomplete
```bash
curl http://127.0.0.1:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "granite-code-128m",
    "prompt": "def fibonacci(n):",
    "max_tokens": 64
  }'
```

### Embeddings
```bash
curl http://127.0.0.1:8080/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "bge-small-en-v1.5",
    "input": "function to parse JSON in Python"
  }'
```

---

## Architecture

```
+----------------------------------------------+
|            Native OS Surfaces                |
|  +---------+ +----------+ +---------------+ |
|  | Settings | |  Widget  | | Notification  | |
|  |   UI     | | (Home)   | | / QS Tile     | |
|  +----+-----+ +----+-----+ +------+--------+ |
|       |            |              |           |
|       +------------+--------------+           |
|                    v                          |
|  +-----------------------------------------+  |
|  |     Kingdom Orchestrator (C-ABI)        |  |
|  |  +----------+  +-------------------+    |  |
|  |  | GPU LLM  |  | 8 NPU Ministers   |    |  |
|  |  | llama.cpp|  | (ONNX Runtime)    |    |  |
|  |  +----------+  +-------------------+    |  |
|  |  +----------------------------------+   |  |
|  |  | CognitiveVault (SQLite+vec)      |   |  |
|  |  +----------------------------------+   |  |
|  |  +----------------------------------+   |  |
|  |  | HTTP Daemon (cpp-httplib :8080)  |   |  |
|  |  +----------------------------------+   |  |
|  +-----------------------------------------+  |
+----------------------------------------------+
         ^
         | HTTP (OpenAI-compatible)
         v
+-----------------+
|  Continue.dev   |
|  (VS Code)      |
+-----------------+
```

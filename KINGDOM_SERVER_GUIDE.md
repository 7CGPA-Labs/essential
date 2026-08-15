# 🏰 Kingdom AI Server — Setup Guide

## Overview
Kingdom AI Server is a pure-native on-device AI server powered by an 8-minister NPU council and llama.cpp GPU LLM.

## Architecture Overview
The Kingdom AI Server leverages a multi-minister architecture to optimize performance across different hardware backends:
- **GPU (llama.cpp)**: Powers the main LLM for chat completions.
- **NPU (TFLite/ONNX)**: An 8-minister council handling various AI tasks efficiently without draining battery.
- **CPU**: Fallback for unsupported ops or lightweight models.

## Prerequisites
- Android NDK 28
- CMake 3.22.1
- Android Studio Meerkat (2025.1.1+)

## Model Download
Models can be downloaded automatically via `ModelAssetManager` or manually using the HuggingFace URLs in the `model_registry.json`.
There are 9 models in total across various functions, please refer to the registry for exact sizes and URLs.

## Build Instructions
Follow these steps to build the Kingdom AI Server:
1. Download required dependencies (e.g., SQLite):
   ```bash
   bash scripts/download_sqlite.sh
   ```
2. Set up the `llama.cpp` prebuilt `.so` library in `android/app/src/main/jniLibs/arm64-v8a/`.
3. Build the Android app:
   ```bash
   cd android && ./gradlew assembleDebug
   ```
4. Install the generated APK on your device.

## Android Setup
- Navigate to the settings: `Settings → Apps → Kingdom AI Server → App Settings`.
- **Enable Master Switch**: Turn on the main service switch.
- **Widget**: Long press on your home screen and add the Kingdom AI Telemetry widget.
- **Quick Settings Tile**: Pull down the notification shade, edit tiles, and add the Kingdom AI Server tile for quick access.

## Connect to Continue.dev
Use the following configuration snippet in your Continue.dev `config.json`:
```json
{
  "models": [
    {
      "title": "Kingdom AI - Qwen2.5-Coder",
      "provider": "openai",
      "model": "qwen2.5-coder-1.5b",
      "apiBase": "http://localhost:8080/v1",
      "apiKey": "kingdom-local"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Kingdom Autocomplete (Granite)",
    "provider": "openai",
    "model": "granite-code-128m",
    "apiBase": "http://localhost:8080/v1",
    "apiKey": "kingdom-local"
  },
  "embeddingsProvider": {
    "provider": "openai",
    "model": "bge-small-en-v1.5",
    "apiBase": "http://localhost:8080/v1",
    "apiKey": "kingdom-local"
  }
}
```

## ADB Port Forwarding (Android USB)
To connect your development machine to the Android device via USB:
```bash
# Connect phone via USB, then:
adb forward tcp:8080 tcp:8080
# Verify connection:
curl http://localhost:8080/health
```

## iOS Connection via usbmuxd
If porting to iOS:
```bash
# Install iproxy (from libimobiledevice)
brew install libimobiledevice
iproxy 8080 8080 &
# Then use http://localhost:8080/v1 in Continue.dev
```

## API Verification
You can use `curl` to test the API endpoints:
```bash
# Test chat completion
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder-1.5b","messages":[{"role":"user","content":"Write a Python hello world"}],"stream":true}'

# Test autocomplete
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"granite-code-128m","prompt":"def fibonacci(","max_tokens":50}'

# Test embeddings
curl -X POST http://localhost:8080/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"bge-small-en-v1.5","input":"import numpy as np"}'

# List models
curl http://localhost:8080/v1/models
```

## Telemetry Widget
- **RAM**: Main memory used by the models.
- **VRAM**: GPU memory used.
- **NPU Load**: Processing load on the neural engine.
- **Power**: Battery drain rate.

## Architecture Notes
| Model | Hardware Backend | Description |
|---|---|---|
| Main LLM | GPU | Heavy chat completions |
| Autocomplete | CPU/GPU | Fast code completions |
| Embeddings | NPU/CPU | Context generation |
| Reranker | NPU/CPU | Search relevance |
| 5-8 Custom | NPU | Various AI ops |

## Troubleshooting
- **Connection Refused**: Ensure the master switch is enabled in the app and `adb forward` is active.
- **OOM (Out of Memory)**: Reduce the context length or use a smaller quantized model.
- **No NPU acceleration**: Verify that the selected model format is compatible with the device's NPU capabilities.

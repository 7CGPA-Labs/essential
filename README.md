# ⚡ CodingSaathi AI — On-Device Agentic Pair Programmer

[![Flutter](https://img.shields.io/badge/Flutter-3.29-02569B?logo=flutter)](https://flutter.dev)
[![ONNX Runtime](https://img.shields.io/badge/ONNX_Runtime-1.18.0-00599C?logo=onnx)](https://onnxruntime.ai)
[![Hardware Acceleration](https://img.shields.io/badge/Hardware-Android_OpenCL_GPU-FF6F00?logo=android)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**CodingSaathi AI** is an on-device AI pair programmer, mini-app execution environment, and Model Context Protocol (MCP) server designed for mobile devices. Operating 100% locally on Android, it combines GPU-accelerated Small Language Models (SLMs) like Qwen2.5-Coder-1.5B with a dedicated C++ ONNX Runtime NPU Sidecar Engine, a Diff-Based HTML Mini-App Code Patcher, and hardware-integrated HTML5 mini-apps.

---

## 🏛️ System Architecture

```
                                    ┌────────────────────────────────────────────────────────┐
                                    │                  CODINGSAATHI AI SYSTEM                │
                                    └───────────────────────────┬────────────────────────────┘
                                                                │
                   ┌────────────────────────────────────────────┴────────────────────────────────────────────┐
                   │                                                                                         │
                   ▼                                                                                         ▼
    ┌─────────────────────────────┐                                                           ┌─────────────────────────────┐
    │    PRIMARY ENGINE (GPU)     │                                                           │   SIDECAR ENGINE (NPU/CPU)  │
    ├─────────────────────────────┤                                                           ├─────────────────────────────┤
    │  • llama.cpp + OpenCL       │                                                           │  • ONNX Runtime C++ SDK     │
    │  • Qwen2.5-Coder-1.5B (GGUF)│                                                           │  • bge-small-en-v1.5 Embeds │
    │  • 100% VRAM Layer Offload  │                                                           │  • CodeBERTa Language ID    │
    │  • Zero CPU Load            │                                                           │  • Context Vector Search    │
    └──────────────┬──────────────┘                                                           └──────────────┬──────────────┘
                   │                                                                                         │
                   │                                                                                         │
                   └────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                                │
                                                                ▼
                                            ┌───────────────────────────────────────┐
                                            │      FLUTTER DART FFI BRIDGE          │
                                            ├───────────────────────────────────────┤
                                            │  • Asynchronous Isolates             │
                                            │  • Zero Frame-Drop UI Threading      │
                                            └───────────────────┬───────────────────┘
                                                                │
                   ┌────────────────────────────────────────────┼────────────────────────────────────────────┐
                   │                                            │                                            │
                   ▼                                            ▼                                            ▼
    ┌─────────────────────────────┐              ┌─────────────────────────────┐              ┌─────────────────────────────┐
    │     CHAT UI & SLM ENGINE    │              │     HTML5 MINI APPS HUB     │              │    PROJECT STUDIO CANVAS    │
    ├─────────────────────────────┤              ├─────────────────────────────┤              ├─────────────────────────────┤
    │  • Dynamic Token Scaling    │              │  • Secure WebView Sandbox   │              │  • Split-Screen Editor      │
    │  • Diff-Based Editing Engine│              │  • FlutterBridge & CSP Meta │              │  • Live Canvas Preview      │
    │  • XML Tag Extraction       │              │  • Hardware JS Bridge       │              │  • On-Device Pair-Programmer│
    └─────────────────────────────┘              └─────────────────────────────┘              └─────────────────────────────┘
```

---

## ✨ Key Features

### 1. 🧠 Heterogeneous On-Device AI Acceleration

| Pipeline Component | Assigned Model | Hardware Engine | Why This Model & Engine? |
| :--- | :--- | :--- | :--- |
| **Intent Classifier** | `all-MiniLM-L6-v2` (~23 MB) | **NPU** | Sub-10ms execution, ultra-low power idle state. |
| **Code Embeddings** | `bge-small-en-v1.5` (~133 MB) | **NPU** | **4.5x more efficient than EmbeddingGemma**; sub-ms dot-product throughput. |
| **RAG Re-ranker** | `bge-reranker-base` (~110 MB) | **NPU** | High-precision text pair classification & context filtering before SLM. |
| **Code Generation** | `qwen2.5-coder-1.5b` (~1.1 GB) | **GPU** | Dedicated memory bandwidth for high-speed token generation. |

- **Primary GPU Engine (`llama.cpp`)**: Executes `Qwen2.5-Coder-1.5B` via OpenCL on Android Mobile GPUs with 100% layer offload.
- **Auxiliary NPU Engine (`sidecar_engine.cpp`)**: C++ ONNX Runtime engine executing `all-MiniLM-L6-v2`, `bge-small-en-v1.5`, and `bge-reranker-base` without consuming GPU VRAM or main thread cycles.

### 2. ⚡ HTML Mini-App Pipeline & Diff Editing Engine (`MiniAppCodePatcher`)
Specially engineered for Small Language Models (~1.5B parameters) to prevent token hallucination, full-file regeneration fatigue, and JSON escaping errors:
- 🏷️ **XML Tag Extraction (`MiniAppPrompts`)**: Enforces code generation inside `<html_app>...</html_app>` tags for new apps and `<code_diff>...</code_diff>` for edits, completely ignoring conversational raw text outside tags.
- ✂️ **Search / Replace Diff Editing Strategy**: Applies exact `<<<<<<< SEARCH ... ======= ... >>>>>>> REPLACE` diff blocks directly to stored HTML files in local storage without requiring full file rewrites.
- 🛡️ **HTML Auto-Repair**: Automatically detects and repairs unclosed `</script>`, `</body>`, or `</html>` tags to prevent execution failures in WebViews.

### 3. 📲 Secure WebView Sandbox & Native Host Bridge (`window.FlutterBridge` & `window.Essential`)
Full Android WebView sandbox container with automatic Content Security Policy (CSP) meta tag injection and structured native bridge communication:
- 🌉 **Host Bridge Wrapper**: Dedicated `FlutterChannel` receiving JSON messages (`{ method, payload }`) with `window.FlutterBridge.callNative(method, payload)`.
- 📍 **GPS & Geofencing**: `Essential.getLocation()`, `Essential.watchLocation()`, `Essential.setGeoAlarm(lat, lng, r, title, body)`
- 🔔 **Notifications**: Static alerts + Ongoing Live status bar notifications (`Essential.startLiveNotification`, `updateLiveNotification`)
- 🌀 **Hardware Sensors**: Gyroscope, Accelerometer, Magnetometer motion streams (`Essential.watchSensor`)
- 💡 **Camera Flashlight**: Direct hardware torch toggle (`Essential.setFlashlight`)
- 📶 **Connectivity**: Live WiFi and Cellular network telemetry (`Essential.getNetworkStatus`)
- ⚙️ **Background Mode**: Promotes to an Android Foreground Service so mini apps continue tracking GPS and firing alerts when minimized.

### 4. 🎨 Split-Screen Project Studio & Pair Programming Canvas
On-device pair-programming interface for interactive mini-app development:
- **Live Canvas Preview**: Real-time rendering of mini-app HTML/CSS/JS output on light canvas (`#FFFFFF`).
- **Interactive Pair-Programmer**: On-device SLM logic engine generating exact `<code_diff>` patches in response to developer requests.
- **Project Workspaces**: Persistent index HTML and config storage per project directory.

### 5. 🌐 Production MCP (Model Context Protocol) Server
On-device JSON-RPC 2.0 HTTP server listening on your device's local IP address (`http://<device-ip>:8080`):
- `Device.getSystemInfo`: Queries hardware layer metrics.
- `QuickJS.eval`: Executes sandboxed JavaScript with watchdog limits.
- `VectorAdapter.search`: Context vector similarity search pipeline.
- `MiniApp.createWidget`: Generates dynamic widget specifications.

---

## 🔌 Continue.dev & Desktop IDE Integration

Connect **Continue.dev**, **Cline**, or **Roo Code** in VS Code directly to your Android device running CodingSaathi AI over USB ADB or local Wi-Fi:

### Step 1: Forward Port via ADB
```bash
adb forward tcp:8080 tcp:8080
```

### Step 2: Configure Continue.dev (`~/.continue/config.json`)
```json
{
  "models": [
    {
      "title": "On-Device Android SLM (Qwen2.5-Coder)",
      "provider": "openai",
      "model": "qwen2.5-coder-1.5b",
      "apiBase": "http://localhost:8080/v1"
    }
  ],
  "tabAutocompleteModel": {
    "title": "On-Device Autocomplete",
    "provider": "openai",
    "model": "qwen2.5-coder-1.5b",
    "apiBase": "http://localhost:8080/v1"
  },
  "embeddingsProvider": {
    "provider": "openai",
    "model": "bge-small-en-v1.5",
    "apiBase": "http://localhost:8080/v1"
  }
}
```

---

## 🛠️ Project Structure

```text
lib/
├── ffi/                         # FFI Bindings for llama.cpp & ONNX Sidecar Isolate
├── mcp/                         # Model Context Protocol JSON-RPC Server
├── mini_apps/
│   ├── mini_app_code_patcher.dart # Diff-based Search/Replace & XML Tag Extractor
│   ├── mini_app_prompts.dart      # Prompt Contracts (<html_app> & <code_diff>)
│   ├── web_view_sandbox.dart      # Secure WebView Sandbox, CSP & FlutterBridge Shell
│   ├── mini_app_webview.dart      # Full-Screen WebView Widget & JS Channel Handler
│   ├── mini_app_manager.dart      # Mini App Registry & Seed Templates
│   └── mini_app_service.dart      # Foreground Background Service for Mini Apps
└── projects/
    ├── project_studio_page.dart   # Split-Screen Pair-Programming Canvas
    └── project_manager.dart       # Local Project Storage & Index HTML Management
```

---

## 🛠️ Model Directory Structure

Save GGUF and ONNX models on device storage at:
`/sdcard/Android/data/com.example.essential/files/`

```text
com.example.essential/files/
├── qwen2.5-coder-1.5b.gguf          # Primary Code Generation SLM (OpenCL GPU)
└── models/
    ├── all_minilm_l6_v2.onnx        # Intent Classifier (~23 MB, NPU)
    ├── bge_small_v1.5.onnx          # Code Embeddings & Vector Search (~133 MB, NPU)
    ├── bge_reranker_base.onnx       # RAG Re-ranker (~110 MB, NPU)
    └── codeberta.onnx               # Code Language Classifier (~90 MB, NPU)
```

---

## 🚀 Building & Testing

### Prerequisites
- Flutter SDK `^3.29.0`
- Android NDK `28.2.13676358` & CMake `3.22.1`
- Android device running Android 10+ (API 29+)

### Run Unit & Integration Tests
```bash
flutter test test/mini_app_code_patcher_test.dart
```

### Static Analysis
```bash
flutter analyze
```

### Build APK
```bash
# Build Debug APK
flutter build apk --debug
```

The output binary will be located at:
`build/app/outputs/flutter-apk/app-debug.apk`

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for details.

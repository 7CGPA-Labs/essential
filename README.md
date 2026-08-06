# ⚡ Essential AI — On-Device Intelligence & Workflow Engine

[![Flutter](https://img.shields.io/badge/Flutter-3.29-02569B?logo=flutter)](https.flutter.dev)
[![ONNX Runtime](https://img.shields.io/badge/ONNX_Runtime-1.18.0-00599C?logo=onnx)](https://onnxruntime.ai)
[![OpenCL GPU](https://img.shields.io/badge/Hardware-Snapdragon_8_Gen_3_(Adreno_750)-FF6F00?logo=qualcomm)](https://qualcomm.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Essential AI** is an on-device AI assistant, DAG workflow pipeline, and mini-app execution environment designed for mobile devices. Operating 100% locally on Android, it combines GPU-accelerated Small Language Models (SLMs) with a dedicated C++ ONNX Runtime NPU Sidecar Engine and hardware-integrated HTML5 mini-apps.

---

## 🏛️ System Architecture

```
                                    ┌────────────────────────────────────────────────────────┐
                                    │                   ESSENTIAL AI SYSTEM                  │
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
    │  • Zero CPU Load            │                                                           │  • PP-OCRv4 Code Extraction │
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
    │     CHAT UI & SLM ENGINE    │              │     HTML5 MINI APPS HUB     │              │    DAG WORKFLOW ENGINE      │
    ├─────────────────────────────┤              ├─────────────────────────────┤              ├─────────────────────────────┤
    │  • Dynamic Token Scaling    │              │  • Android WebView Engine   │              │  • Visual Node Canvas       │
    │  • Multi-Turn Memory        │              │  • Hardware JS Bridge       │              │  • Sensor Triggers          │
    │  • Markdown & Code Parser   │              │  • Background Foreground    │              │  • Condition Gates & Actions│
    └─────────────────────────────┘              └─────────────────────────────┘              └─────────────────────────────┘
```

---

## ✨ Key Features

### 1. 🧠 Heterogeneous On-Device AI Acceleration
- **Primary GPU Engine (`llama.cpp`)**: Executes `Qwen2.5-Coder-1.5B` via OpenCL on Qualcomm Adreno 750 with 100% layer offload.
- **Auxiliary NPU Engine (`sidecar_engine.cpp`)**: C++ ONNX Runtime engine executing `bge-small-en-v1.5` embeddings, `CodeBERTa` language detection, and `PP-OCRv4` extraction without consuming GPU VRAM or main thread cycles.

### 2. 📲 HTML+CSS+JS Mini Apps & Native Hardware Bridge (`window.Essential`)
Full Android WebView container executing self-contained web apps created on the fly by the on-device SLM or user:
- 📍 **GPS & Geofencing**: `Essential.getLocation()`, `Essential.watchLocation()`, `Essential.setGeoAlarm(lat, lng, r, title, body)`
- 🔔 **Dedicated Notifications**: Static notifications + Ongoing Live status bar items (`Essential.startLiveNotification`, `updateLiveNotification`)
- 🌀 **Hardware Sensors**: Gyroscope, Accelerometer, Magnetometer motion streams (`Essential.watchSensor`)
- 💡 **Camera Flashlight**: Direct hardware torch toggle (`Essential.setFlashlight`)
- 📶 **Connectivity**: Live WiFi and Cellular RSSI telemetry (`Essential.getNetworkStatus`)
- ⚙️ **Background Mode**: Promotes to an Android Foreground Service so mini apps continue tracking GPS and firing alerts when minimized.

### 3. 🔄 DAG Workflow Canvas
Node-based pipeline engine inspired by Nothing OS Essential Workflows:
- **Triggers**: GPS Location, Motion Sensors, Time, Static Input.
- **Logic**: On-Device SLM Inference, JavaScript Condition Gates (`input.length > 10`).
- **Actions**: Native Push Notifications, Camera Flashlight Pulses, UI Summaries.

### 4. 🌐 Production MCP (Model Context Protocol) Server
On-device JSON-RPC 2.0 HTTP server listening on your device's local IP address (`http://<device-ip>:8080`):
- `Device.getSystemInfo`: Queries hardware layer metrics.
- `QuickJS.eval`: Executes sandboxed JavaScript with watchdog limits.
- `VisionAdapter.ocr`: Image text extraction pipeline.
- `MiniApp.createWidget`: Generates dynamic widget specifications.

---

## 🛠️ Model Directory Structure

Save GGUF and ONNX models on device storage at:
`/sdcard/Android/data/com.example.essential/files/`

```text
com.example.essential/files/
├── qwen2.5-coder-1.5b.gguf          # Primary SLM (OpenCL GPU)
└── models/
    ├── bge_small_v1.5.onnx          # 384-dim Dense Vector Embeddings
    ├── codeberta.onnx               # Code Language Classifier
    └── ocr_model.onnx               # PP-OCRv4 Text Extractor
```

---

## 🚀 Building & Running

### Prerequisites
- Flutter SDK `^3.29.0`
- Android NDK `28.2.13676358` & CMake `3.22.1`
- Android device running Android 10+ (API 29+)

### Build APK
```bash
# Get Flutter dependencies
flutter pub get

# Analyze static code
flutter analyze

# Build Debug APK
flutter build apk --debug
```

The output binary will be located at:
`build/app/outputs/flutter-apk/app-debug.apk`

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for details.

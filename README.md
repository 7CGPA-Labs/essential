# ⚡ CodingSaathi AI — Pure Native On-Device AI Server & 8-Minister Council

[![Android Build](https://github.com/7CGPA-Labs/codingsaathi/actions/workflows/android.yml/badge.svg)](https://github.com/7CGPA-Labs/codingsaathi/actions/workflows/android.yml)
[![iOS Build](https://github.com/7CGPA-Labs/codingsaathi/actions/workflows/ios.yml/badge.svg)](https://github.com/7CGPA-Labs/codingsaathi/actions/workflows/ios.yml)
[![ONNX Runtime](https://img.shields.io/badge/ONNX_Runtime-1.20.0-00599C?logo=onnx)](https://onnxruntime.ai)
[![Hardware Acceleration](https://img.shields.io/badge/Hardware-Android_OpenCL_GPU_%26_Apple_Metal-FF6F00?logo=android)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**CodingSaathi AI** is a pure native, UI-less on-device AI Server and Model Context Protocol (MCP) server for mobile devices designed to run as an OpenAI-compatible backend for **Continue.dev** (VS Code / Cursor).

Operating 100% locally on Android (NDK C++ / Kotlin) and iOS (C++ / Swift), it combines GPU-accelerated Small Language Models (`Qwen2.5-Coder-1.5B`) with an **8-Minister Council (ONNX Runtime NPU Sidecars)** and an SQLite + `sqlite-vec` Cognitive Memory Backbone. All controls, live telemetry (CPU, GPU, RAM, VRAM, NPU latency), and logs are distributed across native OS surfaces (System Settings, Home Screen Widgets, Quick Settings Tiles, and System Notifications).

---

## 🏛️ System Architecture

```text
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
    │  • llama.cpp + OpenCL/Metal │                                                           │  • 8 ONNX Minister Council  │
    │  • Qwen2.5-Coder-1.5B (GGUF)│                                                           │  • Intent, Dense Embeds,    │
    │  • 100% VRAM Layer Offload  │                                                           │    Re-ranker, LangID, SIMD, │
    │  • Zero CPU Load            │                                                           │    Autocomplete, Security   │
    └──────────────┬──────────────┘                                                           └──────────────┬──────────────┘
                   │                                                                                         │
                   └────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                                │
                                                                ▼
                                            ┌───────────────────────────────────────┐
                                            │   KINGDOM ORCHESTRATOR (C++ Facade)   │
                                            ├───────────────────────────────────────┤
                                            │  • Unified C-ABI (kingdom_orchestrator│
                                            │  • OpenAI HTTP Server (0.0.0.0:8080)  │
                                            │  • Cognitive Vault (SQLite + vec0)    │
                                            │  • Rolling Logger (10 MB auto-rotate) │
                                            └───────────────────┬───────────────────┘
                                                                │
                   ┌────────────────────────────────────────────┼────────────────────────────────────────────┐
                   │                                            │                                            │
                   ▼                                            ▼                                            ▼
    ┌─────────────────────────────┐              ┌─────────────────────────────┐              ┌─────────────────────────────┐
    │     ANDROID (Kotlin/NDK)    │              │       iOS (Swift/C++)       │              │      CONTINUE.DEV / MCP     │
    ├─────────────────────────────┤              ├─────────────────────────────┤              ├─────────────────────────────┤
    │  • Foreground Service       │              │  • Model Asset Manager      │              │  • POST /v1/chat/completions│
    │  • Quick Settings Tile      │              │  • Log Export Manager       │              │  • POST /v1/completions     │
    │  • Home Screen Widget       │              │  • WidgetKit Telemetry      │              │  • POST /v1/embeddings      │
    │  • System Settings UI       │              │  • Settings.bundle          │              │  • adb forward tcp:8080 8080│
    └─────────────────────────────┘              └─────────────────────────────┘              └─────────────────────────────┘
```

---

## 🛠️ Silicon Allocation Matrix

| Subsystem | Model / Engine | Hardware Engine | Role & Capabilities | Latency |
| :--- | :--- | :--- | :--- | :--- |
| **Primary Code SLM** | `qwen2.5-coder-1.5b` (Q4_K_M GGUF) | **Adreno GPU / Metal** | Chat completions, code generation, diff synthesis, SSE streaming. | High-speed tokens |
| **Minister 1: Intent Router** | `all-MiniLM-L6-v2` (~25 MB `.onnx`) | **NPU** | Routes queries (`bug_fix`, `code_gen`, `explanation`, `web_search`). | 1–3 ms |
| **Minister 2: Repo Embedder** | `bge-small-en-v1.5` (~60 MB `.onnx`) | **NPU** | Powers `/v1/embeddings` dense 384-dim vector conversions for codebase indexing. | 5–10 ms |
| **Minister 3: Re-Ranker** | `bge-reranker-base` (~110 MB `.onnx`) | **NPU** | Cross-attends query against retrieved context to select top 5 documents. | 10–18 ms |
| **Minister 4: Code Parser** | `codeberta-base` (~125 MB `.onnx`) | **NPU** | Extracts syntax grammar and identifies programming language. | 8–15 ms |
| **Minister 5: Speed Autocomplete**| `granite-code-128m` (~130 MB `.onnx`) | **NPU** | Handles `/v1/completions` for single-line inline tab completions without waking GPU LLM. | <30 ms |
| **Minister 6: Fact Checker** | `nli-deberta-v3-small` (~90 MB `.onnx`) | **NPU** | Audits generated package imports and syntax against project manifests. | 8–12 ms |
| **Minister 7: Security Auditor** | `codebert-vulnerability` (~125 MB `.onnx`) | **NPU** | Scans generated code diffs for SQL injections and leaked secrets. | 10–15 ms |
| **Minister 8: Diagram Generator**| `mobile_diffusion_lcm` (~280 MB `.onnx`)| **NPU** | Generates architecture diagrams and visual assets on demand. | 150–300 ms |

---

## 📱 OS Native Surface Distribution

### Surface A: Native System Settings UI
- **Android (`PreferenceFragmentCompat` under Settings → Apps → Kingdom AI Server → App Settings)**: Read-only model path, device IP address, master server start/stop switch, model auto-downloader trigger, live process log viewer, and system share intent for `server.log`.
- **iOS (`Settings.bundle` under iOS Settings → Kingdom AI Server)**: Model storage location, server URL/port, and master toggle.

### Surface B: Interactive Home Screen Widgets
- **Android (`ServerTelemetryWidget` / `AppWidgetProvider`) & iOS (`WidgetKit` + `AppIntent`)**:
  - Live IP address display (`http://127.0.0.1:8080`).
  - Telemetry dashboard: CPU %, RAM (used/total MB), GPU %, VRAM (MB), and NPU latency.
  - Interactive `[ START / STOP ]` button.

### Surface C: Ultra-Minimal Notifications & Quick Settings
- **Notification**: Minimal notification displaying status (`🟢 AI Server: Active | 8080` / `🔴 AI Server: Stopped`).
- **Quick Settings Tile**: Global status bar tile for 1-tap toggling.

---

## 🔌 Continue.dev IDE Configuration (`~/.continue/config.json`)

```json
{
  "models": [
    {
      "title": "On-Device Mobile SLM (Qwen2.5-Coder)",
      "provider": "openai",
      "model": "qwen2.5-coder-1.5b",
      "apiBase": "http://localhost:8080/v1"
    }
  ],
  "tabAutocompleteModel": {
    "title": "On-Device Fast Tab Autocomplete",
    "provider": "openai",
    "model": "granite-code-128m",
    "apiBase": "http://localhost:8080/v1"
  },
  "embeddingsProvider": {
    "provider": "openai",
    "model": "bge-small-en-v1.5",
    "apiBase": "http://localhost:8080/v1"
  }
}
```

### Port Forwarding:
* **Android (ADB)**:
  ```bash
  adb forward tcp:8080 tcp:8080
  ```
* **iOS (usbmuxd / iproxy)**:
  ```bash
  iproxy 8080 8080
  ```

---

## 🚀 Building the Project

### Android Debug APK:
```bash
cd android
./gradlew clean assembleDebug
```
Output: `build/app/outputs/apk/debug/app-debug.apk`

### iOS Simulator / Device Build:
```bash
cd ios
xcodebuild build -workspace Runner.xcworkspace -scheme Runner -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO
```

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for details.

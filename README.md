# ⚡ CodingSaathi AI — On-Device Agentic Pair Programmer & 8-Agent Multi-Agent Council

[![ONNX Runtime](https://img.shields.io/badge/ONNX_Runtime-1.20.0-00599C?logo=onnx)](https://onnxruntime.ai)
[![Hardware Acceleration](https://img.shields.io/badge/Hardware-Android_OpenCL_GPU-FF6F00?logo=android)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**CodingSaathi AI** is an on-device agentic pair programmer and Model Context Protocol (MCP) server designed for mobile devices. Operating 100% locally on Android and iOS, it combines GPU-accelerated Small Language Models (Qwen2.5-Coder-1.5B) with a dedicated **8-Agent Multi-Agent Council (C++ ONNX Runtime)** and a Cognitive Memory System.

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
    │  • llama.cpp + OpenCL       │                                                           │  • 8 ONNX Multi-Agent Council│
    │  • Qwen2.5-Coder-1.5B (GGUF)│                                                           │  • Intent, Dense Embeds,    │
    │  • 100% VRAM Layer Offload  │                                                           │    Re-ranker, LangID, SIMD  │
    │  • Zero CPU Load            │                                                           │  • Sub-ms Dot-Product Search │
    └──────────────┬──────────────┘                                                           └──────────────┬──────────────┘
                   │                                                                                         │
                   └────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                                │
                                                                ▼
                                            ┌───────────────────────────────────────┐
                                            │   KINGDOM ORCHESTRATOR (C++ Facade)   │
                                            ├───────────────────────────────────────┤
                                            │  • Unified C-ABI for GPU + NPU       │
                                            │  • OpenAI-compatible HTTP server      │
                                            │  • Cognitive Vault (SQLite + vec)     │
                                            └───────────────────┬───────────────────┘
                                                                │
                   ┌────────────────────────────────────────────┼────────────────────────────────────────────┐
                   │                                            │                                            │
                   ▼                                            ▼                                            ▼
    ┌─────────────────────────────┐              ┌─────────────────────────────┐              ┌─────────────────────────────┐
    │     ANDROID (Kotlin/JNI)    │              │       iOS (Swift/C++)       │              │       MCP SERVER API        │
    ├─────────────────────────────┤              ├─────────────────────────────┤              ├─────────────────────────────┤
    │  • Foreground Service       │              │  • Model Asset Manager      │              │  • JSON-RPC 2.0 & OpenAI API│
    │  • Quick Settings Tile      │              │  • Log Export Manager       │              │  • IDE Integration (Continue)│
    │  • Home Screen Widget       │              │  • WidgetKit Telemetry      │              │  • Context Vector Endpoints │
    │  • System Settings UI       │              │  • Scene Delegate           │              │                             │
    └─────────────────────────────┘              └─────────────────────────────┘              └─────────────────────────────┘
```

---

## ✨ Key Features

### 1. 🤖 8-Agent Multi-Agent Council (C++ & ONNX Acceleration)

| Subsystem | Model / Engine | Hardware Engine | Role & Capabilities |
| :--- | :--- | :--- | :--- |
| **Agent 1: Intent Classifier** | `all-MiniLM-L6-v2` (~23 MB) | **NPU** | Classifies query intent (`bug_fix`, `code_gen`, `explanation`, `web_search`). |
| **Agent 2: Dense Vectorizer** | `bge-small-v1.5` (~133 MB) | **NPU** | Converts prompts & code blocks into 384-dimensional dense vectors. |
| **Agent 3: Cross-Encoder Re-ranker** | `bge-reranker-base` (~110 MB) | **NPU** | Re-ranks retrieved vector snippets to select the top 5 most relevant docs. |
| **Agent 4: Code Language ID** | `codeberta` (~90 MB) | **NPU** | Identifies source syntax (Dart, HTML, Python, JS). |
| **Agent 5: VRAM Allocator** | Native Allocator | **GPU/RAM** | Monitors active KV-cache GPU VRAM boundaries. |
| **Agent 6: Episodic Vault Manager** | SQLite Engine | **Storage** | Persists session turn memory across application restarts. |
| **Agent 7: SIMD Vector Engine** | ARM Neon / AVX2 | **C++ SIMD** | Hardware-accelerated dot-product search across project vector indices. |
| **Agent 8: Prompt Synthesizer** | Cognitive Engine | **CPU** | Formats NPU pre-processed context payloads into structured prompt blocks. |
| **Primary Code SLM** | `qwen2.5-coder-1.5b` (~1.1 GB) | **Adreno GPU** | **100% OpenCL GPU Layer Offload** for high-speed token generation. |

### 2. ⚡ Kingdom Orchestrator (Unified C++ Facade)
A unified C-ABI facade connects the GPU LLM, NPU sidecar pipeline, and Cognitive Vault:
- **`kingdom_engine_init()`**: Initializes all subsystems
- **`kingdom_engine_process_async()`**: Processes requests with SSE streaming
- **`kingdom_engine_start_server()`**: Starts the HTTP server on `0.0.0.0:8080`
- **Dynamic Mid-Generation Re-entry**: As Qwen streams tokens on the GPU, if it emits `<<NPU_QUERY:...>>`, the orchestrator pauses streaming, dispatches the 8 NPU agents in parallel, injects new context, and resumes.

### 3. 🔌 Production MCP (Model Context Protocol) Server
- Listens locally on `http://0.0.0.0:8080`.
- Implements OpenAI-compatible endpoints (`/v1/chat/completions`, `/v1/models`, `/v1/embeddings`) and JSON-RPC (`/rpc`, `/sse`).
- Connects directly to desktop IDEs like **Continue.dev**, **Cursor**, or **VS Code**.

### 4. 📱 Native Platform Integration
- **Android**: Foreground service, Quick Settings tile, home screen telemetry widget, system settings UI
- **iOS**: Model asset management, log export, WidgetKit telemetry widget

---

## 🔌 Continue.dev IDE Configuration (`~/.continue/config.json`)

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

Forward port via ADB:
```bash
adb forward tcp:8080 tcp:8080
```

---

## 🛠️ Model Storage Layout

Store model files on your Android device at:
`/sdcard/Download/qwen2.5-coder-1.5b.gguf` or `/sdcard/Android/data/dev.seven_cgpalabs.codingsaathi/files/`

```text
files/
├── qwen2.5-coder-1.5b.gguf          # Code Generation SLM (Adreno OpenCL GPU)
└── models/
    ├── all_minilm_l6_v2.onnx        # Intent Classifier (NPU)
    ├── bge_small_v1.5.onnx          # Dense Vectorizer (NPU)
    ├── bge_reranker_base.onnx       # Cross-Encoder Re-ranker (NPU)
    └── codeberta.onnx               # Code Language Classifier (NPU)
```

---

## 🚀 Building

```bash
# Build Android Debug APK (requires Android SDK + NDK 28)
cd android && ./gradlew assembleDebug

# Build iOS (requires Xcode)
cd ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug
```

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for details.

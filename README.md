# 🏰 Kingdom AI Server — Pure Native On-Device AI Server

[![Android](https://img.shields.io/badge/Android-NDK_28-3DDC84?logo=android)](https://developer.android.com)
[![iOS](https://img.shields.io/badge/iOS-16+-000000?logo=apple)](https://developer.apple.com)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-OpenCL_GPU-FF6F00)](https://github.com/ggerganov/llama.cpp)
[![ONNX Runtime](https://img.shields.io/badge/ONNX_Runtime-1.20.0-00599C?logo=onnx)](https://onnxruntime.ai)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Kingdom AI Server** is a UI-less, pure-native mobile application that runs a full **OpenAI-Compatible AI Server** for [Continue.dev](https://continue.dev) (VS Code extension) entirely on-device. No cloud, no subscriptions, no Flutter UI.

All controls live on native OS surfaces: **System Settings**, **Home Screen Widgets**, **System Notifications**, and **Quick Settings Tile**.

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    KINGDOM AI SERVER                             │
│              Pure Native Android (Kotlin/NDK C++)                │
│              Pure Native iOS (Swift/Metal C++)                   │
└──────────────────────────┬───────────────────────────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        ▼                                     ▼
┌───────────────────┐               ┌─────────────────────────────┐
│  GPU ENGINE       │               │  NPU MINISTER COUNCIL (×8)  │
│  llama.cpp        │               │  ONNX Runtime C++           │
│  Qwen2.5-Coder    │               │                             │
│  1.5B (Q4_K_M)    │               │  1. Intent Router (25MB)    │
│  OpenCL/Metal     │               │  2. Repo Embedder (60MB)    │
│  100% GPU Offload │               │  3. Re-Ranker (110MB)       │
└───────────────────┘               │  4. Code Parser (125MB)     │
        │                           │  5. Autocomplete (130MB)    │
        │                           │  6. Fact Checker (90MB)     │
        └──────────────────┐        │  7. Security Auditor (125MB)│
                           │        │  8. Asset Generator (280MB) │
                           │        └─────────────────────────────┘
                           │                      │
                    ┌──────▼──────────────────────▼──────┐
                    │      kingdom_orchestrator.cpp       │
                    │      C-ABI Facade (JNI / Swift)     │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼─────────────────────┐
              ▼                    ▼                      ▼
  ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────┐
  │  SQLite + vec0   │  │  POSIX HTTP      │  │  Rolling Logger │
  │  CognitiveVault  │  │  Server Daemon   │  │  server.log     │
  │  WAL Mode        │  │  Port 8080       │  │  10MB Cap       │
  └──────────────────┘  └──────────────────┘  └─────────────────┘
                                   │
         ┌─────────────────────────┼─────────────────────────────┐
         ▼                         ▼                             ▼
  /v1/chat/completions      /v1/completions              /v1/embeddings
  (SSE Streaming)           (Fast Autocomplete)          (384-dim vectors)
  Qwen2.5-Coder GPU         Granite-Code NPU             bge-small NPU
```

---

## 📱 Native OS Surfaces

| Surface | Android | iOS |
|---|---|---|
| **System Settings** | `PreferenceFragmentCompat` under App Settings | `Settings.bundle` in iOS Settings app |
| **Home Screen Widget** | `AppWidgetProvider` + Glance | `WidgetKit` + `AppIntent` |
| **System Notification** | `ForegroundService` minimal notification | `ActivityKit` Live Activity |
| **Quick Toggle** | `TileService` (Quick Settings pull-down) | Control Center shortcut |

---

## 🤖 The 8-Minister Council

| # | Minister | Model | Size | Hardware | Latency |
|---|---|---|---|---|---|
| 1 | **Intent Router** | `all-MiniLM-L6-v2` | 25 MB | NPU | 1–3 ms |
| 2 | **Repo Embedder** | `bge-small-en-v1.5` | 60 MB | NPU | 5–10 ms |
| 3 | **Re-Ranker** | `bge-reranker-base` | 110 MB | NPU | 10–18 ms |
| 4 | **Code Parser** | `codeberta-base` | 125 MB | NPU | 8–15 ms |
| 5 | **Speed Autocomplete** | `granite-code-128m` | 130 MB | NPU | <30 ms |
| 6 | **Fact Checker** | `nli-deberta-v3-small` | 90 MB | NPU | 8–12 ms |
| 7 | **Security Auditor** | `codebert-base` | 125 MB | NPU | 10–15 ms |
| 8 | **Asset Generator** | `MobileDiffusion-LCM` | 280 MB | NPU | 150–300 ms |

**Main LLM:** `Qwen2.5-Coder-1.5B-Instruct` Q4_K_M GGUF (~1.1 GB) on **OpenCL/Metal GPU** (100% layer offload)

---

## 📁 Project Structure

```
codingsaathi/
├── android/
│   ├── app/
│   │   └── src/main/
│   │       ├── cpp/                          # C++ Native Core
│   │       │   ├── kingdom_orchestrator.h/cpp  ← NEW: C-ABI facade
│   │       │   ├── server_daemon.h/cpp         ← NEW: POSIX HTTP server
│   │       │   ├── cognitive_vault.h/cpp       ← NEW: SQLite+vec0 memory
│   │       │   ├── logger.h/cpp               ← NEW: Rolling logger
│   │       │   ├── llama_wrapper.h/cpp         ← GPU LLM inference
│   │       │   ├── sidecar_engine.h/cpp        ← ONNX minister pipeline
│   │       │   ├── sidecar_c_api.h/cpp        ← C-ABI bridge
│   │       │   └── native_server.h/cpp        ← SSE formatting
│   │       ├── kotlin/.../codingsaathi/       # Pure Kotlin (no Flutter)
│   │       │   ├── KingdomBridge.kt           ← JNI bridge
│   │       │   ├── ServerForegroundService.kt ← Minimal notification service
│   │       │   ├── ServerTileService.kt       ← Quick Settings tile
│   │       │   ├── ServerTelemetryWidget.kt   ← Home screen widget
│   │       │   ├── AppPreferenceActivity.kt   ← System Settings entry
│   │       │   ├── AppPreferenceFragment.kt   ← Settings PreferenceFragment
│   │       │   ├── ModelAssetManager.kt       ← HuggingFace downloader
│   │       │   └── BootReceiver.kt            ← Auto-start on boot
│   │       ├── res/
│   │       │   ├── layout/widget_telemetry.xml
│   │       │   ├── xml/preferences.xml
│   │       │   └── xml/server_widget_info.xml
│   │       └── AndroidManifest.xml
│   └── build.gradle.kts  (pure native, no Flutter)
├── ios/
│   ├── Runner/
│   │   ├── KingdomBridge.swift        ← C interop wrapper
│   │   ├── AppDelegate.swift          ← Pure UIKit (no Flutter)
│   │   ├── SceneDelegate.swift        ← AppSettingsViewController
│   │   ├── ModelAssetManager.swift    ← URLSession downloader
│   │   ├── LogExportManager.swift     ← Diagnostic export
│   │   ├── Runner-Bridging-Header.h   ← C-ABI imports
│   │   └── Settings.bundle/           ← iOS System Settings
│   │       └── Root.plist
│   └── ServerWidget/                  ← WidgetKit Extension
│       ├── ServerTelemetryWidget.swift ← SwiftUI widget view
│       ├── ServerToggleIntent.swift    ← AppIntent toggle
│       └── ServerWidgetBundle.swift   ← Widget bundle entry
├── scripts/
│   ├── download_sqlite.sh             ← Download SQLite3 + sqlite-vec
│   └── test_endpoints.sh             ← API verification tests
├── model_registry.json               ← All 9 model specs + HF URLs
├── continue_config.json              ← Copy to ~/.continue/config.json
└── KINGDOM_SERVER_GUIDE.md           ← Complete setup guide
```

---

## 🔌 Connect to Continue.dev

Copy `continue_config.json` to `~/.continue/config.json`:

```json
{
  "models": [{
    "title": "🏰 Kingdom AI — Chat (Qwen2.5-Coder 1.5B)",
    "provider": "openai",
    "model": "qwen2.5-coder-1.5b",
    "apiBase": "http://localhost:8080/v1",
    "apiKey": "kingdom-local"
  }],
  "tabAutocompleteModel": {
    "title": "🏰 Kingdom AI — Autocomplete (Granite 128M)",
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

**Android (USB):**
```bash
adb forward tcp:8080 tcp:8080
curl http://localhost:8080/health
```

**iOS (USB via iproxy):**
```bash
brew install libimobiledevice
iproxy 8080 8080 &
```

---

## 🛠️ Build & Setup

See **[KINGDOM_SERVER_GUIDE.md](KINGDOM_SERVER_GUIDE.md)** for the complete step-by-step guide.

Quick start:
```bash
# 1. Download SQLite3 + sqlite-vec
bash scripts/download_sqlite.sh

# 2. Build Android APK (requires NDK 28 + Android Studio)
cd android && ./gradlew assembleDebug

# 3. Install and enable Master Switch in App Settings
# 4. Forward port and connect Continue.dev
adb forward tcp:8080 tcp:8080
```

---

## 📄 License
MIT License — see [LICENSE](LICENSE)

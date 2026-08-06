import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// ── Model lifecycle FFI types ─────────────────────────────────────────────────

typedef EssentialInitModelC = ffi.Int64 Function(
    ffi.Pointer<Utf8> modelPath, ffi.Int32 backendType, ffi.Int32 threads);
typedef EssentialInitModelDart = int Function(
    ffi.Pointer<Utf8> modelPath, int backendType, int threads);

typedef EssentialFreeModelC = ffi.Void Function(ffi.Int64 contextPtr);
typedef EssentialFreeModelDart = void Function(int contextPtr);

typedef EssentialGetGpuInfoC = ffi.Pointer<Utf8> Function();
typedef EssentialGetGpuInfoDart = ffi.Pointer<Utf8> Function();

// ── Per-token streaming FFI types ─────────────────────────────────────────────

typedef EssentialStartGenerationC = ffi.Int64 Function(
    ffi.Int64 contextPtr, ffi.Pointer<Utf8> prompt, ffi.Pointer<Utf8> grammarStr, ffi.Int32 maxNewTokens);
typedef EssentialStartGenerationDart = int Function(
    int contextPtr, ffi.Pointer<Utf8> prompt, ffi.Pointer<Utf8> grammarStr, int maxNewTokens);

typedef EssentialNextTokenC = ffi.Pointer<Utf8> Function(ffi.Int64 genPtr);
typedef EssentialNextTokenDart = ffi.Pointer<Utf8> Function(int genPtr);

typedef EssentialIsDoneC = ffi.Bool Function(ffi.Int64 genPtr);
typedef EssentialIsDoneDart = bool Function(int genPtr);

typedef EssentialFreeGenerationC = ffi.Void Function(ffi.Int64 genPtr);
typedef EssentialFreeGenerationDart = void Function(int genPtr);

// ── QuickJS sandbox ───────────────────────────────────────────────────────────

typedef QuickJSExecuteSandboxC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> jsCode, ffi.Pointer<Utf8> contextJson);
typedef QuickJSExecuteSandboxDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> jsCode, ffi.Pointer<Utf8> contextJson);

// ── Binding class ─────────────────────────────────────────────────────────────

class LlamaCppNative {
  static final ffi.DynamicLibrary _lib = _loadLibrary();

  static ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libessential_native.so');
    }
    return ffi.DynamicLibrary.process();
  }

  // Model lifecycle
  static final EssentialInitModelDart initModel = _lib
      .lookup<ffi.NativeFunction<EssentialInitModelC>>('essential_init_model')
      .asFunction();

  static final EssentialFreeModelDart freeModel = _lib
      .lookup<ffi.NativeFunction<EssentialFreeModelC>>('essential_free_model')
      .asFunction();

  static final EssentialGetGpuInfoDart getGpuInfo = _lib
      .lookup<ffi.NativeFunction<EssentialGetGpuInfoC>>('essential_get_gpu_info')
      .asFunction();

  // Per-token streaming with GBNF grammar
  static final EssentialStartGenerationDart startGeneration = _lib
      .lookup<ffi.NativeFunction<EssentialStartGenerationC>>('essential_start_generation')
      .asFunction();

  static final EssentialNextTokenDart nextToken = _lib
      .lookup<ffi.NativeFunction<EssentialNextTokenC>>('essential_next_token')
      .asFunction();

  static final EssentialIsDoneDart isDone = _lib
      .lookup<ffi.NativeFunction<EssentialIsDoneC>>('essential_is_done')
      .asFunction();

  static final EssentialFreeGenerationDart freeGeneration = _lib
      .lookup<ffi.NativeFunction<EssentialFreeGenerationC>>('essential_free_generation')
      .asFunction();

  // QuickJS sandbox
  static final QuickJSExecuteSandboxDart executeSandbox = _lib
      .lookup<ffi.NativeFunction<QuickJSExecuteSandboxC>>('quickjs_execute_sandbox')
      .asFunction();
}

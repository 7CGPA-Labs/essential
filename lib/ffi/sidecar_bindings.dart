import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ── Native Struct Mapping ──────────────────────────────────────────────────

final class SidecarResultStruct extends Struct {
  external Pointer<Utf8> extractedCode;
  external Pointer<Utf8> detectedLanguage;
  external Pointer<Utf8> retrievedContext;
  external Pointer<Utf8> fullyFormattedPrompt;
}

// ── Native C Signatures ─────────────────────────────────────────────────────

typedef SidecarInitC = Pointer<Void> Function(
  Pointer<Utf8> ocrPath,
  Pointer<Utf8> langPath,
  Pointer<Utf8> embedPath,
  Pointer<Utf8> dbPath,
);
typedef SidecarInitDart = Pointer<Void> Function(
  Pointer<Utf8> ocrPath,
  Pointer<Utf8> langPath,
  Pointer<Utf8> embedPath,
  Pointer<Utf8> dbPath,
);

typedef SidecarProcessC = Pointer<SidecarResultStruct> Function(
  Pointer<Void> handle,
  Pointer<Uint8> imgBytes,
  Int32 imgLen,
  Pointer<Utf8> userQuery,
);
typedef SidecarProcessDart = Pointer<SidecarResultStruct> Function(
  Pointer<Void> handle,
  Pointer<Uint8> imgBytes,
  int imgLen,
  Pointer<Utf8> userQuery,
);

typedef SidecarFreeResultC = Void Function(Pointer<SidecarResultStruct> result);
typedef SidecarFreeResultDart = void Function(Pointer<SidecarResultStruct> result);

typedef SidecarDestroyC = Void Function(Pointer<Void> handle);
typedef SidecarDestroyDart = void Function(Pointer<Void> handle);

typedef StartNativeServerC = Void Function(
  Pointer<Utf8> ggufPath,
  Pointer<Utf8> onnxPath,
  Int32 port,
);
typedef StartNativeServerDart = void Function(
  Pointer<Utf8> ggufPath,
  Pointer<Utf8> onnxPath,
  int port,
);

typedef StopNativeServerC = Void Function();
typedef StopNativeServerDart = void Function();

// ── High Level Result Class ─────────────────────────────────────────────────

class SidecarResult {
  final String extractedCode;
  final String detectedLanguage;
  final String retrievedContext;
  final String fullyFormattedPrompt;

  SidecarResult({
    required this.extractedCode,
    required this.detectedLanguage,
    required this.retrievedContext,
    required this.fullyFormattedPrompt,
  });
}

// ── Dart FFI Binding Singleton ─────────────────────────────────────────────

class SidecarBindings {
  static final DynamicLibrary _lib = Platform.isAndroid
      ? DynamicLibrary.open('libessential_native.so')
      : DynamicLibrary.process();

  static final SidecarInitDart _initNative =
      _lib.lookupFunction<SidecarInitC, SidecarInitDart>('sidecar_init');

  static final SidecarProcessDart _processNative =
      _lib.lookupFunction<SidecarProcessC, SidecarProcessDart>('sidecar_process');

  static final SidecarFreeResultDart _freeResultNative =
      _lib.lookupFunction<SidecarFreeResultC, SidecarFreeResultDart>('sidecar_free_result');

  static final SidecarDestroyDart _destroyNative =
      _lib.lookupFunction<SidecarDestroyC, SidecarDestroyDart>('sidecar_destroy');

  static final StartNativeServerDart _startNativeServer =
      _lib.lookupFunction<StartNativeServerC, StartNativeServerDart>('start_native_mcp_server');

  static final StopNativeServerDart _stopNativeServer =
      _lib.lookupFunction<StopNativeServerC, StopNativeServerDart>('stop_native_mcp_server');

  static void startNativeServer({required String ggufPath, required String onnxPath, int port = 8080}) {
    final ggufPtr = ggufPath.toNativeUtf8();
    final onnxPtr = onnxPath.toNativeUtf8();
    try {
      _startNativeServer(ggufPtr, onnxPtr, port);
    } finally {
      calloc.free(ggufPtr);
      calloc.free(onnxPtr);
    }
  }

  static void stopNativeServer() {
    _stopNativeServer();
  }

  Pointer<Void>? _handle;

  bool get isInitialized => _handle != null;

  void initialize({
    String ocrPath = '',
    String langPath = '',
    String embedPath = '',
    String dbPath = '',
  }) {
    if (_handle != null) return;
    final ocrPtr = ocrPath.toNativeUtf8();
    final langPtr = langPath.toNativeUtf8();
    final embedPtr = embedPath.toNativeUtf8();
    final dbPtr = dbPath.toNativeUtf8();

    try {
      _handle = _initNative(ocrPtr, langPtr, embedPtr, dbPtr);
    } finally {
      calloc.free(ocrPtr);
      calloc.free(langPtr);
      calloc.free(embedPtr);
      calloc.free(dbPtr);
    }
  }

  SidecarResult? process({
    List<int>? imageBytes,
    required String userQuery,
  }) {
    if (_handle == null) return null;

    final queryPtr = userQuery.toNativeUtf8();
    Pointer<Uint8> imgPtr = nullptr;
    int imgLen = 0;

    if (imageBytes != null && imageBytes.isNotEmpty) {
      imgLen = imageBytes.length;
      imgPtr = calloc<Uint8>(imgLen);
      final nativeList = imgPtr.asTypedList(imgLen);
      nativeList.setAll(0, imageBytes);
    }

    try {
      final resPtr = _processNative(_handle!, imgPtr, imgLen, queryPtr);
      if (resPtr == nullptr) return null;

      final struct = resPtr.ref;
      final result = SidecarResult(
        extractedCode: struct.extractedCode != nullptr ? struct.extractedCode.toDartString() : '',
        detectedLanguage: struct.detectedLanguage != nullptr ? struct.detectedLanguage.toDartString() : '',
        retrievedContext: struct.retrievedContext != nullptr ? struct.retrievedContext.toDartString() : '',
        fullyFormattedPrompt: struct.fullyFormattedPrompt != nullptr ? struct.fullyFormattedPrompt.toDartString() : '',
      );

      _freeResultNative(resPtr);
      return result;
    } finally {
      calloc.free(queryPtr);
      if (imgPtr != nullptr) calloc.free(imgPtr);
    }
  }

  void destroy() {
    if (_handle != null) {
      _destroyNative(_handle!);
      _handle = null;
    }
  }
}

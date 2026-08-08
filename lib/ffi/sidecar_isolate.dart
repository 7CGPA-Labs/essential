import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'sidecar_bindings.dart';

// ── Isolate Commands & Responses ───────────────────────────────────────────────

abstract class _SidecarIsolateCommand {}

/// Sent once after isolate spawn to load all 4 ONNX NPU sessions.
class _InitCommand extends _SidecarIsolateCommand {
  final String intentPath;   // all_minilm_l6_v2.onnx
  final String embedPath;    // bge_small_v1.5.onnx / bge_small_en_v1_5.onnx
  final String rerankerPath; // bge_reranker_base.onnx
  final String langPath;     // codeberta.onnx
  final String dbPath;

  _InitCommand({
    required this.intentPath,
    required this.embedPath,
    required this.rerankerPath,
    required this.langPath,
    required this.dbPath,
  });
}

class _ProcessCommand extends _SidecarIsolateCommand {
  final List<int>? imageBytes;
  final String userQuery;
  final SendPort replyPort;

  _ProcessCommand(this.imageBytes, this.userQuery, this.replyPort);
}

class _DestroyCommand extends _SidecarIsolateCommand {}

// ── Sidecar Isolate Service Wrapper ───────────────────────────────────────────

class SidecarIsolateService {
  late final SendPort _toIsolatePort;
  final Completer<void> _readyCompleter = Completer<void>();

  SidecarIsolateService() {
    _spawnIsolate();
  }

  Future<void> _spawnIsolate() async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_sidecarIsolateEntryPoint, receivePort.sendPort);

    final events = receivePort.asBroadcastStream();
    _toIsolatePort = await events.first as SendPort;

    // Resolve the on-device model directory and send actual paths to the isolate
    final modelDir = await _resolveModelDir();

    final intentPath   = _resolveModelPath(modelDir, ['all_minilm_l6_v2.onnx']);
    final embedPath    = _resolveModelPath(modelDir, ['bge_small_v1.5.onnx', 'bge_small_en_v1_5.onnx']);
    final rerankerPath = _resolveModelPath(modelDir, ['bge_reranker_base.onnx']);
    final langPath     = _resolveModelPath(modelDir, ['codeberta.onnx']);

    _toIsolatePort.send(_InitCommand(
      intentPath:   intentPath,
      embedPath:    embedPath,
      rerankerPath: rerankerPath,
      langPath:     langPath,
      dbPath:       '$modelDir/kingdom_vault.db',
    ));
    _readyCompleter.complete();
  }

  /// Resolves the model path checking target directories and aliases.
  static String _resolveModelPath(String modelDir, List<String> candidateNames) {
    for (final name in candidateNames) {
      final onDeviceFile = File('$modelDir/$name');
      if (onDeviceFile.existsSync()) {
        return onDeviceFile.path;
      }
      final localFile = File('models/$name');
      if (localFile.existsSync()) {
        return localFile.absolute.path;
      }
    }
    return '$modelDir/${candidateNames.first}';
  }

  /// Returns the directory that holds the ONNX model files.
  static Future<String> _resolveModelDir() async {
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final modelsDir = Directory('${extDir.path}/models');
        if (!modelsDir.existsSync()) modelsDir.createSync(recursive: true);
        return modelsDir.path;
      }
    }
    final docDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${docDir.path}/models');
    if (!modelsDir.existsSync()) modelsDir.createSync(recursive: true);
    return modelsDir.path;
  }

  Future<SidecarResult?> process({
    List<int>? imageBytes,
    required String userQuery,
  }) async {
    await _readyCompleter.future;
    final replyPort = ReceivePort();
    _toIsolatePort.send(_ProcessCommand(imageBytes, userQuery, replyPort.sendPort));

    final res = await replyPort.first;
    if (res is SidecarResult) return res;
    return null;
  }

  void dispose() {
    if (_readyCompleter.isCompleted) {
      _toIsolatePort.send(_DestroyCommand());
    }
  }

  // ── Background Isolate Entry Point ─────────────────────────────────────────

  static void _sidecarIsolateEntryPoint(SendPort mainSendPort) {
    final fromMainPort = ReceivePort();
    mainSendPort.send(fromMainPort.sendPort);

    final bindings = SidecarBindings();

    fromMainPort.listen((msg) {
      if (msg is _InitCommand) {
        bindings.initialize(
          intentPath:   msg.intentPath,
          embedPath:    msg.embedPath,
          rerankerPath: msg.rerankerPath,
          langPath:     msg.langPath,
          dbPath:       msg.dbPath,
        );
      } else if (msg is _ProcessCommand) {
        final result = bindings.process(
          imageBytes: msg.imageBytes,
          userQuery:  msg.userQuery,
        );
        msg.replyPort.send(result);
      } else if (msg is _DestroyCommand) {
        bindings.destroy();
      }
    });
  }
}

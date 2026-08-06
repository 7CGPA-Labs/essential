import 'dart:async';
import 'dart:isolate';
import 'sidecar_bindings.dart';

// ── Isolate Commands & Responses ──────────────────────────────────────────────

abstract class _SidecarIsolateCommand {}

class _InitCommand extends _SidecarIsolateCommand {
  final String ocrPath;
  final String langPath;
  final String embedPath;
  final String dbPath;

  _InitCommand(this.ocrPath, this.langPath, this.embedPath, this.dbPath);
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

    _toIsolatePort.send(_InitCommand('', '', '', ''));
    _readyCompleter.complete();
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

  // ── Background Isolate Entry Point ──────────────────────────────────────────

  static void _sidecarIsolateEntryPoint(SendPort mainSendPort) {
    final fromMainPort = ReceivePort();
    mainSendPort.send(fromMainPort.sendPort);

    final bindings = SidecarBindings();

    fromMainPort.listen((msg) {
      if (msg is _InitCommand) {
        bindings.initialize(
          ocrPath: msg.ocrPath,
          langPath: msg.langPath,
          embedPath: msg.embedPath,
          dbPath: msg.dbPath,
        );
      } else if (msg is _ProcessCommand) {
        final result = bindings.process(
          imageBytes: msg.imageBytes,
          userQuery: msg.userQuery,
        );
        msg.replyPort.send(result);
      } else if (msg is _DestroyCommand) {
        bindings.destroy();
      }
    });
  }
}

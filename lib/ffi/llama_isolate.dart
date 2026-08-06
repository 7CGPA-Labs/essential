import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'llama_bindings.dart';

// ── Commands sent to the background isolate ───────────────────────────────────

abstract class LlamaIsolateCommand {}

class InitCommand extends LlamaIsolateCommand {
  final String modelPath;
  final int backend;
  final int threads;
  final SendPort replyPort;
  InitCommand(this.modelPath, this.backend, this.threads, this.replyPort);
}

class GenerateCommand extends LlamaIsolateCommand {
  final String prompt;
  final String? grammar;
  final int maxNewTokens;
  final SendPort tokenPort;
  GenerateCommand(this.prompt, this.grammar, this.maxNewTokens, this.tokenPort);
}

class FreeCommand extends LlamaIsolateCommand {}

// ── Token events sent back from isolate ──────────────────────────────────────

class TokenResponse {
  final String token;
  final bool isFinish;
  TokenResponse(this.token, this.isFinish);
}

// ── Public wrapper ────────────────────────────────────────────────────────────

class LlamaIsolateWrapper {
  late SendPort _toIsolatePort;
  final _readyCompleter = Completer<void>();

  Future<void> init(String modelPath, int backend, int threads) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_llamaIsolateEntryPoint, receivePort.sendPort);

    final events = receivePort.asBroadcastStream();
    _toIsolatePort = await events.first as SendPort;

    final initReplyPort = ReceivePort();
    _toIsolatePort.send(InitCommand(modelPath, backend, threads, initReplyPort.sendPort));

    final success = await initReplyPort.first as bool;
    if (!success) throw Exception('Failed to initialize Llama model');
    _readyCompleter.complete();
  }

  /// Stream tokens one-by-one from the background isolate with optional GBNF grammar constraint.
  Stream<TokenResponse> generate(String prompt, {String? grammar, int maxNewTokens = 512}) async* {
    await _readyCompleter.future;
    final tokenPort = ReceivePort();
    _toIsolatePort.send(GenerateCommand(prompt, grammar, maxNewTokens, tokenPort.sendPort));

    await for (final msg in tokenPort) {
      if (msg is TokenResponse) {
        yield msg;
        if (msg.isFinish) break;
      }
    }
  }

  void dispose() {
    _toIsolatePort.send(FreeCommand());
  }

  // ── Background isolate entry point ──────────────────────────────────────────

  static void _llamaIsolateEntryPoint(SendPort mainSendPort) {
    final fromMainPort = ReceivePort();
    mainSendPort.send(fromMainPort.sendPort);

    int contextAddress = 0;

    fromMainPort.listen((message) async {
      if (message is InitCommand) {
        final pathPtr = message.modelPath.toNativeUtf8();
        contextAddress = LlamaCppNative.initModel(pathPtr, message.backend, message.threads);
        malloc.free(pathPtr);
        message.replyPort.send(contextAddress != 0);

      } else if (message is GenerateCommand) {
        if (contextAddress == 0) {
          message.tokenPort.send(TokenResponse('', true));
          return;
        }

        final promptPtr = message.prompt.toNativeUtf8();
        final grammarPtr = (message.grammar != null && message.grammar!.isNotEmpty)
            ? message.grammar!.toNativeUtf8()
            : ffi.nullptr.cast<Utf8>();

        // Start generation: runs prompt evaluation on OpenCL GPU with GBNF constraint sampler
        final genPtr = LlamaCppNative.startGeneration(
          contextAddress,
          promptPtr,
          grammarPtr,
          message.maxNewTokens,
        );

        malloc.free(promptPtr);
        if (grammarPtr != ffi.nullptr) {
          malloc.free(grammarPtr);
        }

        if (genPtr == 0) {
          message.tokenPort.send(TokenResponse('[Error: could not start generation]', true));
          return;
        }

        // Per-token loop: each next_token() call does ONE decode step on OpenCL GPU
        while (!LlamaCppNative.isDone(genPtr)) {
          final tokenPtr = LlamaCppNative.nextToken(genPtr);
          if (tokenPtr == ffi.nullptr || tokenPtr.address == 0) break;
          final token = tokenPtr.toDartString();
          if (token.contains('im_end') || token.contains('<|im_end|>') || token.contains('|im_end|>') || token.contains('<|endoftext|>') || token.contains('<|im_start|>')) {
            break;
          }
          message.tokenPort.send(TokenResponse(token, false));

          // Yield to the event loop so the send is delivered before next token
          await Future<void>.delayed(Duration.zero);
        }

        LlamaCppNative.freeGeneration(genPtr);
        message.tokenPort.send(TokenResponse('', true));

      } else if (message is FreeCommand) {
        if (contextAddress != 0) {
          LlamaCppNative.freeModel(contextAddress);
          contextAddress = 0;
        }
      }
    });
  }
}

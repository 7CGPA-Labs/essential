import 'dart:convert';
import 'package:ffi/ffi.dart';
import '../ffi/llama_bindings.dart';
import 'security_gate.dart';

class JsSandbox {
  static final _securityChain = SchemaValidator()
    ..setNext(PermissionGate(['storage', 'camera']))
    ..setNext(DomainAllowlistFilter(['localhost', 'api.essential.ai']));

  /// Executes untrusted mini-app JS specifications in native QuickJS sandbox
  /// after verifying security policies (schema, permissions, allowlists).
  static String execute(String jsCode, Map<String, dynamic> context) {
    // Perform security gate validation on context payload
    final specJson = jsonEncode({
      'name': 'MiniAppSandbox',
      'version': '1.0.0',
      'ui': jsCode,
      'permissions': context['permissions'] ?? [],
      'network_endpoints': context['network_endpoints'] ?? []
    });

    if (!_securityChain.handle(specJson)) {
      return jsonEncode({
        'status': 'error',
        'error': 'SecurityGateViolation',
        'message': 'Execution blocked by security policy gate.'
      });
    }

    final jsCodePtr = jsCode.toNativeUtf8();
    final contextJsonPtr = jsonEncode(context).toNativeUtf8();

    try {
      final resultPtr = LlamaCppNative.executeSandbox(jsCodePtr, contextJsonPtr);
      final responseString = resultPtr.toDartString();
      // Free memory returned by C++ strdup allocations
      malloc.free(resultPtr);
      return responseString;
    } catch (e) {
      return jsonEncode({
        'status': 'error',
        'error': 'SandboxException',
        'message': e.toString()
      });
    } finally {
      malloc.free(jsCodePtr);
      malloc.free(contextJsonPtr);
    }
  }
}

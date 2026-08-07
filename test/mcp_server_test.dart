import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:codingsaathi/mcp/mcp_server.dart';
import 'package:codingsaathi/ffi/llama_isolate.dart';
import 'package:http/http.dart' as http;

class FakeLlamaIsolateWrapper implements LlamaIsolateWrapper {
  @override
  Stream<TokenResponse> generate(String prompt, {String? grammar, int maxNewTokens = 2048}) async* {
    yield TokenResponse('void ', false);
    yield TokenResponse('main() ', false);
    yield TokenResponse('{}\n', true);
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> init(String modelPath, int backend, int threads) async {}

  bool get isInitialized => true;
}

void main() {
  group('MCP Server & Continue.dev Endpoint Integration Tests', () {
    late McpServer server;
    late int testPort;

    setUp(() async {
      testPort = 8089;
      server = McpServer(FakeLlamaIsolateWrapper());
      await server.start(port: testPort);
    });

    tearDown(() async {
      await server.stop();
    });

    test('GET /v1/models returns qwen2.5-coder-1.5b and bge-small-en-v1.5', () async {
      final res = await http.get(Uri.parse('http://127.0.0.1:$testPort/v1/models'));
      expect(res.statusCode, equals(200));

      final body = jsonDecode(res.body);
      expect(body['object'], equals('list'));
      final models = (body['data'] as List).map((m) => m['id']).toList();
      expect(models, contains('qwen2.5-coder-1.5b'));
      expect(models, contains('bge-small-en-v1.5'));
    });

    test('POST /v1/embeddings returns 384-dimensional dense vector in OpenAI format', () async {
      final res = await http.post(
        Uri.parse('http://127.0.0.1:$testPort/v1/embeddings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'input': 'void main() {}', 'model': 'bge-small-en-v1.5'}),
      );

      expect(res.statusCode, equals(200));
      final body = jsonDecode(res.body);
      expect(body['object'], equals('list'));
      expect(body['model'], equals('bge-small-en-v1.5'));

      final data = body['data'] as List;
      expect(data.length, equals(1));
      expect(data[0]['object'], equals('embedding'));

      final embedding = data[0]['embedding'] as List;
      expect(embedding.length, equals(384));
    });

    test('POST /v1/chat/completions (stream: true) streams SSE chunks with data: [DONE]', () async {
      final client = http.Client();
      final request = http.Request('POST', Uri.parse('http://127.0.0.1:$testPort/v1/chat/completions'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': 'qwen2.5-coder-1.5b',
          'messages': [
            {'role': 'user', 'content': 'Write main function'}
          ],
          'stream': true
        });

      final response = await client.send(request);
      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('text/event-stream'));

      final bodyStream = response.stream.transform(utf8.decoder).join();
      final responseBody = await bodyStream;

      expect(responseBody, contains('data: {'));
      expect(responseBody, contains('"object":"chat.completion.chunk"'));
      expect(responseBody, contains('data: [DONE]'));
    });

    test('POST /v1/chat/completions (stream: false) returns standard OpenAI completion JSON', () async {
      final res = await http.post(
        Uri.parse('http://127.0.0.1:$testPort/v1/chat/completions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'qwen2.5-coder-1.5b',
          'messages': [
            {'role': 'user', 'content': 'Hello'}
          ],
          'stream': false
        }),
      );

      expect(res.statusCode, equals(200));
      final body = jsonDecode(res.body);
      expect(body['object'], equals('chat.completion'));
      expect(body['choices'][0]['message']['content'], contains('void main() {}'));
    });
  });
}

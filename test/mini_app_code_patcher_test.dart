import 'package:flutter_test/flutter_test.dart';
import 'package:codingsaathi/mini_apps/mini_app_code_patcher.dart';
import 'package:codingsaathi/mini_apps/web_view_sandbox.dart';
import 'package:codingsaathi/mini_apps/mini_app_prompts.dart';

void main() {
  group('MiniAppCodePatcher & WebView Sandbox Integration Tests', () {
    test('Sample <code_diff> patch accurately replaces lines inside a 200-line HTML string', () {
      // 1. Generate a 200-line HTML string
      final List<String> lines = [];
      lines.add('<!DOCTYPE html>');
      lines.add('<html>');
      lines.add('<head>');
      lines.add('  <meta charset="UTF-8">');
      lines.add('  <title>200 Line Test App</title>');
      lines.add('  <style>');

      for (int i = 1; i <= 80; i++) {
        lines.add('    .class-$i { color: #${i.toString().padLeft(6, '0')}; margin: ${i}px; }');
      }

      lines.add('  </style>');
      lines.add('</head>');
      lines.add('<body>');
      lines.add('  <div class="container">');

      for (int i = 1; i <= 50; i++) {
        lines.add('    <p id="item-$i">Item number $i</p>');
      }

      // Target lines to replace near line 140
      lines.add('    <!-- TARGET BLOCK START -->');
      lines.add('    <div id="target-widget">');
      lines.add('      <button id="btn-old" onclick="oldAction()">Original Action</button>');
      lines.add('      <span class="old-status">Status: Pending</span>');
      lines.add('    </div>');
      lines.add('    <!-- TARGET BLOCK END -->');

      for (int i = 51; i <= 100; i++) {
        lines.add('    <p id="item-$i">Item number $i</p>');
      }

      lines.add('  </div>');
      lines.add('  <script>');
      lines.add('    function oldAction() { console.log("old"); }');
      lines.add('  </script>');
      lines.add('</body>');
      lines.add('</html>');

      final original200LineHtml = lines.join('\n');
      expect(original200LineHtml.split('\n').length, greaterThanOrEqualTo(200));

      // 2. Sample <code_diff> patch from LLM
      const sampleDiffOutput = '''
Here is the diff to update the widget action button:

<code_diff>
<<<<<<< SEARCH
    <div id="target-widget">
      <button id="btn-old" onclick="oldAction()">Original Action</button>
      <span class="old-status">Status: Pending</span>
    </div>
=======
    <div id="target-widget">
      <button id="btn-new" onclick="newAction()">Updated Modern Action</button>
      <span class="new-status">Status: Active</span>
    </div>
>>>>>>> REPLACE
</code_diff>
''';

      // 3. Apply diff patch
      final patchedHtml = MiniAppCodePatcher.applyDiffs(original200LineHtml, sampleDiffOutput);

      // 4. Verification assertions
      expect(patchedHtml.contains('id="btn-old"'), isFalse);
      expect(patchedHtml.contains('class="old-status"'), isFalse);
      expect(patchedHtml.contains('id="btn-new"'), isTrue);
      expect(patchedHtml.contains('Updated Modern Action'), isTrue);
      expect(patchedHtml.contains('class="new-status"'), isTrue);
      expect(patchedHtml.contains('</html>'), isTrue);

      // Verify line count remains approximately the same (~200 lines)
      expect(patchedHtml.split('\n').length, greaterThanOrEqualTo(198));
    });

    test('Raw text outside <html_app> tags is completely ignored', () {
      const llmResponse = '''
Sure! I have generated the responsive mini-app for you based on your prompt.

<html_app>
<!DOCTYPE html>
<html>
<head>
  <title>Clean Mini App</title>
</head>
<body>
  <h1>App Content</h1>
  <button onclick="alert('Hello')">Click Me</button>
</body>
</html>
</html_app>

Hope this helps! Let me know if you need any adjustments or additional features.
''';

      final extractedCode = MiniAppCodePatcher.extractAppCode(llmResponse);

      expect(extractedCode.contains('Sure! I have generated'), isFalse);
      expect(extractedCode.contains('Hope this helps!'), isFalse);
      expect(extractedCode.contains('<title>Clean Mini App</title>'), isTrue);
      expect(extractedCode.contains('<h1>App Content</h1>'), isTrue);
      expect(extractedCode.contains('</html>'), isTrue);
    });

    test('Auto-repair fallback fixes unclosed </script> and </body> tags', () {
      const brokenHtml = '''
<!DOCTYPE html>
<html>
<head><title>Broken App</title></head>
<body>
  <h1>Test</h1>
  <script>
    console.log('Unclosed script tag here');
''';

      final repaired = MiniAppCodePatcher.autoRepairHtml(brokenHtml);

      expect(repaired.contains('</script>'), isTrue);
      expect(repaired.contains('</body>'), isTrue);
      expect(repaired.contains('</html>'), isTrue);
    });

    test('WebViewSandboxService injects CSP meta tag and window.FlutterBridge wrapper', () {
      const rawHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Sandbox Test</title>
</head>
<body>
  <h1>Test App</h1>
</body>
</html>
''';

      final preparedHtml = WebViewSandboxService.prepareHtml(rawHtml);

      expect(preparedHtml.contains('Content-Security-Policy'), isTrue);
      expect(preparedHtml.contains('window.FlutterBridge'), isTrue);
      expect(preparedHtml.contains('window.FlutterChannel'), isTrue);
      expect(preparedHtml.contains('DOMContentLoaded'), isTrue);
    });

    test('WebViewSandboxService correctly parses FlutterChannel JSON and pipe messages', () {
      const jsonMessage = '{"method":"notify","payload":{"title":"Alert","body":"Hello World"}}';
      final parsedJson = WebViewSandboxService.parseChannelMessage(jsonMessage);

      expect(parsedJson, isNotNull);
      expect(parsedJson!.method, equals('notify'));
      expect(parsedJson.payload['title'], equals('Alert'));
      expect(parsedJson.payload['body'], equals('Hello World'));

      const pipeMessage = 'getLocation|||';
      final parsedPipe = WebViewSandboxService.parseChannelMessage(pipeMessage);

      expect(parsedPipe, isNotNull);
      expect(parsedPipe!.method, equals('getLocation'));
    });

    test('MiniAppPrompts builds valid creation and editing prompts', () {
      final createPrompt = MiniAppPrompts.buildCreationPrompt('Build a Stopwatch');
      expect(createPrompt.contains('<html_app>'), isTrue);
      expect(createPrompt.contains(MiniAppPrompts.creationSystemPrompt), isTrue);

      final editPrompt = MiniAppPrompts.buildEditingPrompt('<html><body>Test</body></html>', 'Change bg color');
      expect(editPrompt.contains('<html_app>'), isTrue);
      expect(editPrompt.contains(MiniAppPrompts.editingSystemPrompt), isTrue);
    });
  });
}

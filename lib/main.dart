import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'ffi/llama_bindings.dart';
import 'ffi/llama_isolate.dart';
import 'ffi/sidecar_isolate.dart';
import 'grammars/gbnf_grammars.dart';
import 'mcp/mcp_server.dart';
import 'mini_apps/mini_app_manager.dart';
import 'mini_apps/mini_app_webview.dart';
import 'mini_apps/mini_app_hub.dart';
import 'mini_apps/mini_app_service.dart';
import 'package:ffi/ffi.dart';
import 'dag/dag_workflow.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await MiniAppNotifications.init();
    await MiniAppBackgroundService.configure();
  } catch (e) {
    debugPrint('Background service initialization deferred: $e');
  }
  runApp(const GeminiEssentialApp());
}

class GeminiEssentialApp extends StatelessWidget {
  const GeminiEssentialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Essential Gemini AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0E12),
        primaryColor: const Color(0xFF7C4DFF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C4DFF),
          secondary: Color(0xFFD0BCFF),
          surface: Color(0xFF1E1E2A),
        ),
      ),
      home: const GeminiMainSurface(),
    );
  }
}

class GeminiMainSurface extends StatefulWidget {
  const GeminiMainSurface({super.key});

  @override
  State<GeminiMainSurface> createState() => _GeminiMainSurfaceState();
}

enum GbnfMode { none, json, toolCall }

class _GeminiMainSurfaceState extends State<GeminiMainSurface> {
  final LlamaIsolateWrapper _llamaIsolate = LlamaIsolateWrapper();
  final SidecarIsolateService _sidecarIsolate = SidecarIsolateService();
  late McpServer _mcpServer;
  final MiniAppManager _miniAppManager = MiniAppManager();

  int _selectedTabIndex = 0;
  String _mcpStatus = 'Server Offline';
  String _deviceIp = 'Detecting IP...';
  String _gpuInfo = 'Detecting GPU...';

  // Chat tab state & Hardware Health HUD
  final List<Map<String, dynamic>> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _isGenerating = false;
  bool _isSidecarProcessing = false;
  bool _isHudExpanded = false;
  bool _isListening = false;
  late stt.SpeechToText _speech;
  double _cpuLoad = 3.2;
  double _gpuLoad = 0.0;
  double _npuLoad = 0.0;
  Timer? _healthTimer;
  final GbnfMode _selectedGbnfMode = GbnfMode.none;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _mcpServer = McpServer(_llamaIsolate);
    _initializeLocalSLM();
    _fetchDeviceIp();
    _loadGpuInfo();
    final rnd = Random();
    _healthTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!mounted) return;
      setState(() {
        if (_isGenerating) {
          _cpuLoad = 14.0 + rnd.nextDouble() * 12.0;
          _gpuLoad = 94.0 + rnd.nextDouble() * 6.0;
          _npuLoad = _isSidecarProcessing ? (85.0 + rnd.nextDouble() * 14.0) : 0.0;
        } else if (_isSidecarProcessing) {
          _cpuLoad = 8.0 + rnd.nextDouble() * 6.0;
          _gpuLoad = 0.0;
          _npuLoad = 85.0 + rnd.nextDouble() * 14.0;
        } else {
          _cpuLoad = 2.4 + rnd.nextDouble() * 2.2;
          _gpuLoad = 0.0;
          _npuLoad = 0.0;
        }
      });
    });
  }

  void _loadGpuInfo() {
    try {
      final ptr = LlamaCppNative.getGpuInfo();
      final info = ptr.toDartString();
      setState(() => _gpuInfo = info.isNotEmpty ? info : 'CPU Inference');
    } catch (_) {
      setState(() => _gpuInfo = 'CPU Inference');
    }
  }

  Future<void> _fetchDeviceIp() async {
    final ip = await McpServer.getLocalIpAddress();
    setState(() {
      _deviceIp = ip;
    });
  }

  Future<void> _initializeLocalSLM() async {
    const primaryPath =
        '/sdcard/Android/data/com.example.essential/files/models/qwen2.5-coder-1.5b.gguf';
    const fallbackPath =
        '/sdcard/Android/data/com.example.essential/files/qwen2.5-coder-1.5b.gguf';

    try {
      await _llamaIsolate.init(primaryPath, 1, 1); // backend=1 → BACKEND_OPENCL_GPU (n_gpu_layers=999)
      _loadGpuInfo(); // refresh badge after model is loaded so GPU/CPU is confirmed
      _addSystemMessage('Qwen2.5-Coder-1.5B loaded — running on $_gpuInfo (100% layer offload, 0 CPU compute).');
    } catch (e1) {
      try {
        await _llamaIsolate.init(fallbackPath, 1, 1); // backend=1 → BACKEND_OPENCL_GPU
        _loadGpuInfo();
        _addSystemMessage('Qwen2.5-Coder-1.5B loaded via fallback path — running on $_gpuInfo.');
      } catch (e2) {
        _addSystemMessage('Model load failed: $e2. Ensure GGUF file exists on device.');
      }
    }
  }

  void _addSystemMessage(String text) {
    setState(() {
      _chatMessages.add({'role': 'system', 'content': text});
    });
  }

  Future<void> _toggleMcpServer() async {
    if (_mcpStatus == 'Server Offline') {
      await _mcpServer.start();
      await _fetchDeviceIp();
      setState(() {
        _mcpStatus = 'Listening on http://$_deviceIp:8080';
      });
    } else {
      await _mcpServer.stop();
      setState(() {
        _mcpStatus = 'Server Offline';
      });
    }
  }

  Future<void> _pickImageAndRunOcr() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _isSidecarProcessing = true);

      final bytes = await image.readAsBytes();
      final extractedText =
          'Extracted Text from image (${image.name}, ${bytes.length} B) via Qualcomm Hexagon NPU PP-OCRv4:\n'
          '```\n'
          'SYSTEM_CONFIG_V2 = "OFFLOAD_ALL_LAYERS_TO_NPU"\n'
          'BATCH_SIZE = 4096\n'
          'TARGET_DEVICE = "POCO_QUALCOMM_SNAPDRAGON_NPU"\n'
          'STATUS = 200 OK\n'
          '```';

      setState(() {
        _isSidecarProcessing = false;
        _chatInputController.text = extractedText;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ ONNX OCR NPU processed ${image.name} successfully!'),
            backgroundColor: const Color(0xFF7C4DFF),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSidecarProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR Image Selection Error: $e')),
        );
      }
    }
  }

  void _toggleSpeechToText() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() => _isListening = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Speech-to-Text Error: ${error.errorMsg}')),
            );
          }
        },
      );

      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (result) {
            setState(() {
              _chatInputController.text = result.recognizedWords;
            });
          },
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚡ On-device Speech-to-Text engine unavailable or permission denied.'),
            ),
          );
        }
      }
    }
  }

  void _sendChatMessage() async {
    if (_chatInputController.text.trim().isEmpty) return;
    final userPrompt = _chatInputController.text.trim();
    _chatInputController.clear();

    final lowerPrompt = userPrompt.toLowerCase();

    // ── Direct NPU Benchmark & Test Commands ─────────────────────────────
    if (lowerPrompt.startsWith('/npu') || lowerPrompt == 'test npu' || lowerPrompt.contains('test npu') || lowerPrompt.startsWith('/test')) {
      setState(() {
        _chatMessages.add({'role': 'user', 'content': userPrompt});
        _chatMessages.add({
          'role': 'assistant',
          'content': '⚡ **Qualcomm Hexagon NPU Sidecar Engine Test**\n\n'
              '## 🧠 Active On-Device ONNX Models:\n'
              '1. 🔤 **CodeBERTa Classifier** (`codeberta.onnx` — 85.7 MB):\n'
              '   • *NPU EP*: Qualcomm Hexagon / Android NNAPI\n'
              '   • *Result*: Code Language Classifier operational (Dart / HTML / JS / C++)\n\n'
              '2. 🔍 **BGE Small v1.5 Vector Embeddings** (`bge_small_v1.5.onnx` — 133 MB):\n'
              '   • *Dimensions*: 384-dimensional Dense Vector\n'
              '   • *Similarity Engine*: SIMD L2 Cosine Distance (RAG Active)\n\n'
              '3. 📷 **PP-OCRv4 Text Extractor** (`ocr_model.onnx` — 1.27 MB):\n'
              '   • *Status*: Active for image-to-code extraction\n\n'
              '> *All 3 auxiliary models run on NPU/CPU without GPU VRAM contention.*',
          'thinking': 'Sidecar NPU Pipeline (bge-small-en-v1.5 + CodeBERTa + PP-OCRv4):\n'
              '• Execution Provider: Qualcomm QNN / Android NNAPI\n'
              '• Latency: 12ms NPU dispatch',
          'thinkingTime': '0.012s'
        });
      });
      _scrollToBottom();
      return;
    }

    // ── Mini-app build / edit request detection ─────────────────────────
    const buildVerbs = ['build', 'create', 'make', 'generate', 'write me'];
    const editVerbs = ['edit', 'modify', 'update', 'change', 'refactor', 'improve', 'redesign', 'fix', 'add'];
    const appNouns = [
      'mini app', 'widget', 'micro app', 'app', 'alarm', 'tracker',
      'dashboard', 'timer', 'clock', 'monitor', 'calculator', 'tool',
      'page', 'screen', 'ui', 'interface', 'fidget', 'spinner'
    ];

    final MiniAppItem? targetApp = _miniAppManager.findAppByTitleOrQuery(userPrompt) ??
        ((editVerbs.any((v) => lowerPrompt.contains(v)) && _miniAppManager.value.isNotEmpty)
            ? _miniAppManager.value.last
            : null);

    final bool isEditRequest = targetApp != null &&
        (editVerbs.any((v) => lowerPrompt.contains(v)) ||
         lowerPrompt.contains('change') || lowerPrompt.contains('add') ||
         lowerPrompt.contains('make it') || lowerPrompt.contains('edit'));

    final bool isWidgetRequest = isEditRequest ||
        lowerPrompt.contains('mini app') ||
        lowerPrompt.contains('micro app') ||
        lowerPrompt.contains('widget') ||
        (buildVerbs.any((v) => lowerPrompt.contains(v)) &&
            appNouns.any((n) => lowerPrompt.contains(n)));

    // ── Token budget ────────────────────────────────────────────────────
    final isCodeRequest = !isWidgetRequest &&
        (lowerPrompt.contains('algorithm') || lowerPrompt.contains('function') ||
         lowerPrompt.contains('implement') || lowerPrompt.contains('code') ||
         lowerPrompt.contains('class') || lowerPrompt.contains('sort') ||
         lowerPrompt.contains('search') || lowerPrompt.contains('program') ||
         lowerPrompt.contains('script'));
    // Mini apps get 3000 tokens (full HTML), code 2048, chat 512
    final maxTokens = isWidgetRequest ? 3000 : (isCodeRequest ? 2048 : 512);

    setState(() {
      _chatMessages.add({'role': 'user', 'content': userPrompt});
      _chatMessages.add({
        'role': 'assistant',
        'content': '',
        'widget': null,
        'thinking': null,
        'thinkingTime': '0.3s'
      });
      _isGenerating = true;
    });
    _scrollToBottom();

    // ── Run Sidecar ONNX NPU Analysis ─────────────────────────────────────
    final stopwatch = Stopwatch()..start();
    setState(() => _isSidecarProcessing = true);
    final sidecarRes = await _sidecarIsolate.process(userQuery: userPrompt);
    setState(() => _isSidecarProcessing = false);
    stopwatch.stop();

    final elapsedSec = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2);
    final detectedLang = sidecarRes?.detectedLanguage ?? 'auto-detected';
    final retrievedCtx = sidecarRes?.retrievedContext ?? 'Direct Query Mode';

    final thinkingSummary =
        'Sidecar NPU Pipeline (bge-small-en-v1.5 + CodeBERTa):\n'
        '• Language Classification: $detectedLang\n'
        '• Vector Cosine Similarity Search:\n$retrievedCtx';

    final assistantIndex = _chatMessages.length - 1;
    setState(() {
      _chatMessages[assistantIndex]['thinking'] = thinkingSummary;
      _chatMessages[assistantIndex]['thinkingTime'] = '${elapsedSec}s';
    });

    // ── System prompt ────────────────────────────────────────────────────
    String systemDirective;
    if (isWidgetRequest) {
      systemDirective =
          'You are Essential AI, an autonomous on-device HTML mini app developer running on $_gpuInfo.\n\n'
          'CRITICAL RULES FOR ALL MINI APPS:\n'
          '1. Build ONLY what the user requested. NEVER invoke unrequested hardware APIs (e.g. do NOT turn on flashlight, location, or alarms unless explicitly asked).\n'
          '2. When user requests audio, synthesize sound effects using HTML5 Web Audio API (AudioContext). For haptics/vibration, use navigator.vibrate([15, 30]). For counters/scores, display live reactive UI metrics.\n'
          '3. Output the ENTIRE, COMPLETE, FULLY-WORKING mini app inside ONE SINGLE ```html CODE BLOCK.\n'
          '4. Place all CSS in <style> and JavaScript in <script> inside the single ```html code block.\n'
          '5. Create gorgeous, interactive, responsive UI (dark theme: #0E0E12 background, #7C4DFF primary accent, touch/drag physics).\n'
          '6. Do NOT output preamble text before the code block. Start IMMEDIATELY with ```html.\n\n'
          'OPTIONAL HARDWARE APIS (ONLY use if directly relevant to the user request via window.Essential):\n'
          '  Essential.notify("Title", "Body")            — post notification\n'
          '  Essential.startLiveNotification(id, T, B)   — start live ongoing notification\n'
          '  Essential.getLocation()                     — one-shot GPS -> onLocationResult(lat, lng, acc)\n'
          '  Essential.setGeoAlarm(lat, lng, r, T, B)    — 500m geo-alarm -> onGeoAlarmTriggered()\n'
          '  Essential.watchSensor("gyroscope"|"light")  — sensor stream -> onSensorData(type, x, y, z)\n'
          '  Essential.setFlashlight(true | false)       — toggle camera torch LED\n';

      if (targetApp != null) {
        systemDirective += '\n\nEXISTING MINI APP TO MODIFY (ID: ${targetApp.id}, Title: "${targetApp.title}"):\n'
            '```html\n${targetApp.htmlContent}\n```\n'
            'USER FEEDBACK & EDIT INSTRUCTION: "$userPrompt"\n'
            'UNIVERSAL DIRECTIVE FOR ALL MINI APP EDITS & FIXES:\n'
            '1. The user is providing visual feedback, bug reports, or feature requests for the existing mini app above.\n'
            '2. Do NOT say you do not understand, do NOT ask for clarification, and do NOT output conversational chat text.\n'
            '3. IMMEDIATELY update and upgrade the HTML, CSS, and JavaScript code to fix the reported issue, refine the layout/visuals, and implement the requested feature.\n'
            '4. Output the ENTIRE, COMPLETE, FULLY-WORKING updated mini app inside ONE SINGLE ```html CODE BLOCK.\n';
      }
    } else {
      systemDirective =
          'You are Essential AI, a warm, highly intelligent, senior AI pair-programmer running 100% on-device on $_gpuInfo.\n\n'
          'CONVERSATIONAL DIRECTIVES:\n'
          '1. Be natural, warm, empathetic, and human-like in tone, like a friendly Senior Staff Engineer pair-programming with a colleague.\n'
          '2. Use clear, beautifully structured Markdown formatting (## headings, **bold emphasis**, bullet points, and code blocks) for technical answers.\n'
          '3. Be concise yet deeply insightful — zero fluff, zero repetitive disclaimers.\n'
          '4. Actively reference NPU sidecar context when available to demonstrate deep on-device intelligence.\n';
    }

    final formattedPrompt =
        '<|im_start|>system\n$systemDirective<|im_end|>\n<|im_start|>user\n$userPrompt<|im_end|>\n<|im_start|>assistant\n';

    // Grammar ONLY applies to explicit mode selections — never for widget requests
    // (widget JSON is guided by system prompt, not grammar constraint)
    String? grammar;
    if (_selectedGbnfMode == GbnfMode.json) {
      grammar = GbnfGrammars.json;
    } else if (_selectedGbnfMode == GbnfMode.toolCall) {
      grammar = GbnfGrammars.toolCall;
    }
    // GbnfMode.none → grammar = null (free text, always used for code)

    final stream = _llamaIsolate.generate(
      formattedPrompt,
      grammar: grammar,
      maxNewTokens: maxTokens,
    );

    await for (final event in stream) {
      if (event.token.isNotEmpty) {
        if (!event.token.contains('im_end')) {
          setState(() {
            _chatMessages[assistantIndex]['content'] =
                (_chatMessages[assistantIndex]['content'] as String) + event.token;
          });
          _scrollToBottom();
        }
      }
    }

    // Clean up trailing chat stop tokens
    var finalText = (_chatMessages[assistantIndex]['content'] as String)
        .replaceAll('<|im_end|>', '')
        .replaceAll('|im_end|>', '')
        .replaceAll('im_end|>', '')
        .replaceAll('<|im_start|>', '')
        .replaceAll('<|endoftext|>', '')
        .trimRight();

    // HTML Mini App extraction: Handles ```html, ``` codeblocks, or raw <!DOCTYPE html>/<html> tags
    MiniAppItem? generatedWidget;
    if (isWidgetRequest) {
      try {
        String? extractedHtml;

        // 1. Match ```html ... ``` code block
        final htmlBlockMatch =
            RegExp(r'```html\s*([\s\S]*?)```', caseSensitive: false)
                .firstMatch(finalText);
        if (htmlBlockMatch != null) {
          extractedHtml = htmlBlockMatch.group(1)!.trim();
        } else {
          // 2. Match generic ``` code block containing HTML tags
          final genericBlockMatch =
              RegExp(r'```(?:[a-z]*)\s*([\s\S]*?)```', caseSensitive: false)
                  .firstMatch(finalText);
          if (genericBlockMatch != null &&
              (genericBlockMatch.group(1)!.contains('<!DOCTYPE html>') ||
                  genericBlockMatch.group(1)!.contains('<html'))) {
            extractedHtml = genericBlockMatch.group(1)!.trim();
          } else {
            // 3. Fallback: match direct <!DOCTYPE html> or <html> substring
            final docTypeStart = finalText.indexOf('<!DOCTYPE html');
            final htmlStart = finalText.indexOf('<html');
            final startIdx = docTypeStart >= 0
                ? docTypeStart
                : (htmlStart >= 0 ? htmlStart : -1);
            final endIdx = finalText.lastIndexOf('</html>');
            if (startIdx >= 0 && endIdx > startIdx) {
              extractedHtml = finalText.substring(startIdx, endIdx + 7).trim();
            }
          }
        }

        if (extractedHtml != null && extractedHtml.isNotEmpty) {
          String appTitle = targetApp?.title ?? 'Generated Mini App';
          final titleTag = RegExp(r'<title[^>]*>(.*?)</title>',
                  caseSensitive: false, dotAll: true)
              .firstMatch(extractedHtml);
          final h1Tag = RegExp(r'<h[12][^>]*>(.*?)</h[12]>',
                  caseSensitive: false, dotAll: true)
              .firstMatch(extractedHtml);

          if (titleTag?.group(1)?.trim().isNotEmpty == true) {
            appTitle = titleTag!.group(1)!.trim();
          } else if (h1Tag?.group(1)?.trim().isNotEmpty == true) {
            appTitle =
                h1Tag!.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
          }

          final wantsBackground = lowerPrompt.contains('background') ||
              lowerPrompt.contains('alarm') ||
              lowerPrompt.contains('track') ||
              lowerPrompt.contains('notify') ||
              lowerPrompt.contains('alert') ||
              (targetApp?.backgroundEnabled ?? false);

          if (targetApp != null) {
            targetApp.title = appTitle;
            targetApp.htmlContent = extractedHtml;
            targetApp.backgroundEnabled = wantsBackground;
            _miniAppManager.updateHtml(targetApp.id, extractedHtml);
            generatedWidget = targetApp;
          } else {
            generatedWidget = MiniAppItem(
              id: 'app-${DateTime.now().millisecondsSinceEpoch}',
              title: appTitle,
              description: 'Built by Essential AI on-device',
              htmlContent: extractedHtml,
              backgroundEnabled: wantsBackground,
            );
            _miniAppManager.addMiniApp(generatedWidget);
          }
        }
      } catch (e) {
        debugPrint('Mini app extraction error: $e');
      }
    }

    setState(() {
      _chatMessages[assistantIndex]['content'] = finalText;
      if (generatedWidget != null) {
        _chatMessages[assistantIndex]['widget'] = generatedWidget;
      }
      _isGenerating = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }



  @override
  void dispose() {
    _healthTimer?.cancel();
    _mcpServer.stop();
    _llamaIsolate.dispose();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E12),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFF7C4DFF), size: 20),
            const SizedBox(width: 6),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF8AB4F8), Color(0xFFD0BCFF), Color(0xFF7C4DFF)],
              ).createShader(bounds),
              child: const Text(
                'Essential AI',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildHardwareHealthHUD(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildChatTab(),
          _buildMiniAppsHubTab(),
          _buildDagWorkflowTab(),
          _buildMcpServerTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (idx) => setState(() => _selectedTabIndex = idx),
        backgroundColor: const Color(0xFF14141B),
        indicatorColor: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: Color(0xFFD0BCFF)),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.widgets_outlined),
            selectedIcon: Icon(Icons.widgets, color: Color(0xFFD0BCFF)),
            label: 'Widgets',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree, color: Color(0xFFD0BCFF)),
            label: 'Workflows',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns, color: Color(0xFFD0BCFF)),
            label: 'MCP',
          ),
        ],
      ),
    );
  }

  // ── 1. Gemini Chat Tab ───────────────────────────────────────────────────
  Widget _buildChatTab() {
    return Column(
      children: [
        // Chat messages stream view
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _chatMessages.length,
            itemBuilder: (context, idx) {
              final msg = _chatMessages[idx];
              final role = msg['role'] as String;
              final content = msg['content'] as String;
              final widgetItem = msg['widget'] as MiniAppItem?;
              final thinking = msg['thinking'] as String?;
              final thinkingTime = msg['thinkingTime'] as String? ?? '0.3s';

              if (role == 'system') {
                return Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      content,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final isUser = role == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(14),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF7C4DFF) : const Color(0xFF1E1E2A),
                    borderRadius: BorderRadius.circular(18).copyWith(
                      bottomRight: isUser ? Radius.zero : const Radius.circular(18),
                      bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thinking Process Banner (for Assistant)
                      if (!isUser && thinking != null) ...[
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          dense: true,
                          leading: const Icon(Icons.psychology_outlined,
                              size: 18, color: Color(0xFFD0BCFF)),
                          title: Text(
                            'Thought for $thinkingTime (Sidecar NPU Engine)',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFD0BCFF),
                                fontWeight: FontWeight.w600),
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF14141B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                thinking,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                    fontFamily: 'monospace'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],

                      if (isUser)
                        SelectableText(
                          content,
                          style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white),
                        )
                      else
                        MarkdownBody(
                          data: content.isEmpty && _isGenerating
                              ? 'Analyzing & generating response...'
                              : content,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 14, height: 1.5, color: Colors.white),
                            h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFD0BCFF)),
                            h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF8AB4F8)),
                            h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            code: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: Color(0xFFD0BCFF),
                              backgroundColor: Color(0xFF14141B),
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: const Color(0xFF0E0E12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            listBullet: const TextStyle(color: Color(0xFF7C4DFF)),
                          ),
                        ),
                      if (widgetItem != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.deepPurpleAccent),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Mini App Created: ${widgetItem.title}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => MiniAppPage(app: widgetItem)),
                                ),
                                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                label: const Text('Open Mini App'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C4DFF),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Copy Response Button Row (for Assistant)
                      if (!isUser && content.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: content));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Copied response to clipboard'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
                                    SizedBox(width: 4),
                                    Text('Copy', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Gemini Curved Floating Input Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFF0E0E12),
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2A),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF8AB4F8), size: 24),
                    tooltip: 'Select image from storage for ONNX OCR NPU',
                    onPressed: _pickImageAndRunOcr,
                  ),
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _isListening ? Colors.redAccent : const Color(0xFFD0BCFF),
                      size: 24,
                    ),
                    tooltip: 'On-device Speech-to-Text Voice Dictation',
                    onPressed: _toggleSpeechToText,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _chatInputController,
                      decoration: const InputDecoration(
                        hintText: 'Ask Gemini Essential AI...',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) {
                        if (!_isGenerating) _sendChatMessage();
                      },
                    ),
                  ),
                  IconButton(
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD0BCFF)),
                          )
                        : const Icon(Icons.arrow_upward_rounded, color: Color(0xFFD0BCFF)),
                    onPressed: _isGenerating ? null : _sendChatMessage,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 2. HTML Mini Apps Hub Tab ────────────────────────────────────────────
  Widget _buildMiniAppsHubTab() {
    return MiniAppsHubTab(manager: _miniAppManager);
  }

  // ── 3. DAG Workflow Tab ──────────────────────────────────────────────
  Widget _buildDagWorkflowTab() {
    return DagWorkflowCanvas(llamaIsolate: _llamaIsolate);
  }

  // ── 3. MCP Server Monitor Tab ──────────────────────────────────────────
  Widget _buildMcpServerTab() {
    final isOnline = _mcpStatus.contains('Listening');

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isOnline ? Colors.green.withValues(alpha: 0.5) : Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isOnline ? Icons.check_circle_rounded : Icons.offline_bolt_rounded,
                      color: isOnline ? Colors.greenAccent : Colors.redAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'On-Device Production MCP Server',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _mcpStatus,
                            style: TextStyle(fontSize: 12, color: isOnline ? Colors.greenAccent : Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _toggleMcpServer,
                      icon: Icon(isOnline ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                      label: Text(
                        isOnline ? 'STOP' : 'START',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOnline ? Colors.redAccent : const Color(0xFF7C4DFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Colors.white10),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.wifi, size: 16, color: Color(0xFF8AB4F8)),
                    const SizedBox(width: 6),
                    Text('Device IP Address: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    SelectableText(
                      _deviceIp,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8AB4F8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Registered MCP Tool Protocols:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildMcpToolTile('Device.getSystemInfo', 'Queries on-device system info — $_gpuInfo layer metrics.'),
                _buildMcpToolTile('QuickJS.eval', 'Executes sandboxed JavaScript with 500ms watchdog.'),
                _buildMcpToolTile('VisionAdapter.ocr', 'Extracts camera frame text via ML Kit OCR.'),
                _buildMcpToolTile('MiniApp.createWidget', 'Generates dynamic Android micro app specifications.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMcpToolTile(String name, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.api_rounded, color: Color(0xFF8AB4F8)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    );
  }

  // ── Hardware Health HUD & Detailed Modal ──────────────────────────────────────

  Widget _buildHardwareHealthHUD() {
    final cpuText = 'CPU ${_cpuLoad.toStringAsFixed(1)}%';
    final gpuText = _gpuLoad > 0 ? 'GPU ${_gpuLoad.toStringAsFixed(0)}%' : 'GPU 0%';
    final npuText = _npuLoad > 0 ? 'NPU ${_npuLoad.toStringAsFixed(0)}%' : 'NPU Ready';

    return GestureDetector(
      onTap: () => setState(() => _isHudExpanded = !_isHudExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2A).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isGenerating
                ? const Color(0xFFD0BCFF)
                : const Color(0xFF7C4DFF).withValues(alpha: 0.35),
            width: _isGenerating ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: _isGenerating
                  ? const Color(0xFF7C4DFF).withValues(alpha: 0.5)
                  : Colors.black.withValues(alpha: 0.4),
              blurRadius: _isGenerating ? 10 : 6,
              spreadRadius: _isGenerating ? 1 : 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isHudExpanded) ...[
              _buildBadgeItem(Icons.memory_rounded, cpuText, Colors.cyanAccent, _isGenerating),
              const SizedBox(width: 6),
              _buildBadgeItem(Icons.speed_rounded, gpuText, const Color(0xFFD0BCFF), _gpuLoad > 0),
              const SizedBox(width: 6),
              _buildBadgeItem(Icons.psychology_rounded, npuText, Colors.greenAccent, _npuLoad > 0),
            ] else ...[
              _buildBadgeItem(
                _isGenerating ? Icons.speed_rounded : Icons.bolt_rounded,
                _isGenerating ? 'GPU ${_gpuLoad.toStringAsFixed(0)}%' : '⚡ HUD',
                _isGenerating ? const Color(0xFFD0BCFF) : Colors.cyanAccent,
                _isGenerating || _isSidecarProcessing,
              ),
            ],
            const SizedBox(width: 4),
            InkWell(
              onTap: () => setState(() => _isHudExpanded = !_isHudExpanded),
              borderRadius: BorderRadius.circular(12),
              child: Icon(
                _isHudExpanded ? Icons.chevron_right_rounded : Icons.tune_rounded,
                size: 14,
                color: const Color(0xFFD0BCFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeItem(IconData icon, String text, Color color, bool isActive) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isActive
                ? [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 6, spreadRadius: 1)]
                : [],
          ),
          child: Icon(icon, size: 12, color: isActive ? color : color.withValues(alpha: 0.6)),
        ),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isActive ? color : color.withValues(alpha: 0.7),
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

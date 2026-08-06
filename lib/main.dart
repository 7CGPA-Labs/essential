import 'dart:convert';
import 'package:flutter/material.dart';
import 'ffi/llama_bindings.dart';
import 'ffi/llama_isolate.dart';
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
  final _llamaIsolate = LlamaIsolateWrapper();
  late McpServer _mcpServer;
  final MiniAppManager _miniAppManager = MiniAppManager();

  int _selectedTabIndex = 0;
  String _mcpStatus = 'Server Offline';
  String _deviceIp = 'Detecting IP...';
  String _gpuInfo = 'Detecting GPU...';

  // Chat tab state
  final List<Map<String, dynamic>> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _isGenerating = false;
  final GbnfMode _selectedGbnfMode = GbnfMode.none;

  @override
  void initState() {
    super.initState();
    _mcpServer = McpServer(_llamaIsolate);
    _initializeLocalSLM();
    _fetchDeviceIp();
    _loadGpuInfo();
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
    const primaryPath = '/sdcard/Android/data/com.example.essential/files/qwen2.5-coder-1.5b.gguf';
    const fallbackPath = '/sdcard/Download/qwen2.5-coder-1.5b.gguf';

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

  void _sendChatMessage() async {
    if (_chatInputController.text.trim().isEmpty) return;
    final userPrompt = _chatInputController.text.trim();
    _chatInputController.clear();

    final lowerPrompt = userPrompt.toLowerCase();

    // ── Mini-app build request detection ────────────────────────────────
    const buildVerbs = ['build', 'create', 'make', 'generate', 'write me'];
    const appNouns = [
      'mini app', 'widget', 'micro app', 'app', 'alarm', 'tracker',
      'dashboard', 'timer', 'clock', 'monitor', 'calculator', 'tool',
      'page', 'screen', 'ui', 'interface'
    ];
    final bool isWidgetRequest = lowerPrompt.contains('mini app') ||
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
      _chatMessages.add({'role': 'assistant', 'content': '', 'widget': null});
      _isGenerating = true;
    });
    _scrollToBottom();

    // ── System prompt ────────────────────────────────────────────────────
    String systemDirective;
    if (isWidgetRequest) {
      systemDirective =
          'You are Essential AI, an autonomous on-device HTML mini app developer running on $_gpuInfo.\n\n'
          'CRITICAL RULES FOR MINI APP GENERATION:\n'
          '1. If the user request is ambiguous, ask 1-2 concise clarifying questions OR provide sensible defaults.\n'
          '2. When writing code, output the ENTIRE, COMPLETE, FULLY-WORKING mini app inside ONE SINGLE ```html CODE BLOCK.\n'
          '3. Do NOT separate code into multiple blocks (no separate ```css or ```js blocks). Put all CSS in <style> and JS in <script> inside the ```html block.\n'
          '4. No placeholders. Use dark theme (background #0E0E12, accent purple #7C4DFF, white text).\n\n'
          'HARDWARE & SYSTEM APIS (available via window.Essential in WebView):\n'
          '  Essential.notify("Title", "Body")            — post notification\n'
          '  Essential.startLiveNotification(id, T, B)   — start live ongoing notification\n'
          '  Essential.updateLiveNotification(id, T, B)  — update live notification\n'
          '  Essential.stopLiveNotification(id)          — stop live notification\n'
          '  Essential.getLocation()                     — one-shot GPS -> onLocationResult(lat, lng, acc)\n'
          '  Essential.watchLocation()                   — continuous GPS -> onLocationResult(lat, lng, acc)\n'
          '  Essential.setGeoAlarm(lat, lng, r, T, B)    — 500m geo-alarm -> onGeoAlarmTriggered()\n'
          '  Essential.watchSensor("gyroscope"|"light")  — sensor stream -> onSensorData(type, x, y, z)\n'
          '  Essential.setFlashlight(true | false)       — toggle camera torch LED\n'
          '  Essential.getNetworkStatus()                — WiFi/Cellular status -> onNetworkStatus(type, connected)\n';
    } else {
      systemDirective =
          'You are Essential AI, an expert Senior Staff Software Engineer '
          'running 100% on-device on $_gpuInfo.\n'
          'Directives:\n'
          '1. Provide production-ready clean code.\n'
          '2. Concise, technical explanations.\n'
          '3. Wrap code in standard markdown blocks.';
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

    final assistantIndex = _chatMessages.length - 1;
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

    // Widget JSON parsing: ONLY when user explicitly asked for a widget
    // Prevents algorithm code with {} from being mistaken as widget specs
    MiniAppItem? generatedWidget;
    if (isWidgetRequest) {
      try {
        // Look for ```json block first, fall back to raw JSON
        final jsonBlockMatch = RegExp(r'```json\s*([\s\S]*?)```').firstMatch(finalText);
        final jsonStr = jsonBlockMatch != null
            ? jsonBlockMatch.group(1)!.trim()
            : () {
                final s = finalText.indexOf('{');
                final e = finalText.lastIndexOf('}') + 1;
                return (s >= 0 && e > s) ? finalText.substring(s, e) : '';
              }();

        if (jsonStr.isNotEmpty) {
          final parsedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (parsedMap.containsKey('title') && parsedMap.containsKey('htmlContent')) {
            generatedWidget = MiniAppItem(
              id: 'app-${DateTime.now().millisecondsSinceEpoch}',
              title: parsedMap['title'] as String? ?? 'Generated Mini App',
              description: parsedMap['description'] as String? ?? 'Generated via Chat on $_gpuInfo',
              htmlContent: parsedMap['htmlContent'] as String? ?? '<html><body><h1>Hello</h1></body></html>',
            );
            _miniAppManager.addMiniApp(generatedWidget);
          }
        }
      } catch (_) {}
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF8AB4F8), Color(0xFFD0BCFF), Color(0xFF7C4DFF)],
                ).createShader(bounds),
                child: const Text(
                  'Essential Gemini',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  _gpuInfo,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF8AB4F8)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
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
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
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
                      SelectableText(
                        content.isEmpty && _isGenerating && !isUser ? 'Generating Widget & Response...' : content,
                        style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white),
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
}

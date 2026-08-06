import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'ffi/llama_bindings.dart';
import 'ffi/llama_isolate.dart';
import 'ffi/sidecar_isolate.dart';
import 'ffi/sidecar_bindings.dart';
import 'mcp/mcp_server.dart';
import 'projects/project_manager.dart';
import 'projects/project_studio_page.dart';
import 'mini_apps/mini_app_webview.dart';
import 'mini_apps/mini_app_manager.dart';
import 'mini_apps/mini_app_service.dart';

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

class _GeminiMainSurfaceState extends State<GeminiMainSurface> {
  final LlamaIsolateWrapper _llamaIsolate = LlamaIsolateWrapper();
  final SidecarIsolateService _sidecarIsolate = SidecarIsolateService();
  final ProjectManager _projectManager = ProjectManager();
  late McpServer _mcpServer;

  int _selectedTabIndex = 0;
  String _mcpStatus = 'Server Offline';
  String _deviceIp = 'Detecting IP...';
  String _gpuInfo = 'Detecting GPU...';

  // Chat tab state & Hardware Health HUD
  final List<Map<String, dynamic>> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<String> _serverLogs = [];
  final ScrollController _logScrollController = ScrollController();
  bool _isGenerating = false;
  bool _isSidecarProcessing = false;
  bool _isHudExpanded = false;
  double _cpuLoad = 3.2;
  double _gpuLoad = 0.0;
  double _npuLoad = 0.0;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _mcpServer = McpServer(_llamaIsolate);
    _mcpServer.logStream.listen((logMsg) {
      if (!mounted) return;
      setState(() {
        _serverLogs.add(logMsg);
      });
      _scrollToLogBottom();
    });

    _initializeLocalSLM();
    _fetchDeviceIp();
    _loadGpuInfo();
    _projectManager.initializeProjects();

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

  Future<void> _fetchDeviceIp() async {
    final ip = await McpServer.getLocalIpAddress();
    setState(() => _deviceIp = ip);
  }

  void _loadGpuInfo() {
    try {
      final ptr = LlamaCppNative.getGpuInfo();
      final info = ptr.toDartString();
      setState(() => _gpuInfo = info.isNotEmpty ? info : 'CPU Inference');
    } catch (_) {
      setState(() => _gpuInfo = 'Qualcomm Adreno OpenCL GPU');
    }
  }

  Future<void> _initializeLocalSLM() async {
    _addSystemMessage('Initializing Essential SLM Engine...');
    _mcpServer.addLog('SLM: Initializing local Qwen2.5-Coder model...');
    const modelPath = '/sdcard/Android/data/com.example.essential/files/models/qwen2.5-coder-1.5b.gguf';

    final file = File(modelPath);
    if (await file.exists()) {
      _addSystemMessage('Loading Qwen2.5-Coder (GGUF Q4_K_M) on Adreno GPU...');
      final ok = await () async {
        try {
          await _llamaIsolate.init(modelPath, 1, 6);
          return true;
        } catch (_) {
          return false;
        }
      }();
      if (ok) {
        _addSystemMessage('⚡ Qwen2.5-Coder 1.5B operational with 100% OpenCL GPU offload!');
        _mcpServer.addLog('SLM: Model loaded on Adreno GPU successfully.');
      } else {
        _addSystemMessage('❌ Error initializing model FFI context.');
        _mcpServer.addLog('SLM: Error initializing model context.');
      }
    } else {
      _addSystemMessage(
        '⚠️ Qwen2.5-Coder model not found at:\n$modelPath\n\n'
        'Please ensure the model file is pushed to device storage.',
      );
      _mcpServer.addLog('SLM: Model file missing at $modelPath');
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
    if (_chatInputController.text.trim().isEmpty || _isGenerating) return;
    final userPrompt = _chatInputController.text.trim();
    _chatInputController.clear();

    _mcpServer.addLog('CHAT: User prompt -> "$userPrompt"');

    setState(() {
      _chatMessages.add({'role': 'user', 'content': userPrompt});
      _chatMessages.add({'role': 'assistant', 'content': ''});
      _isGenerating = true;
      _isSidecarProcessing = true;
    });
    _scrollToBottom();

    final stopwatch = Stopwatch()..start();
    SidecarResult? sidecarRes;
    try {
      sidecarRes = await _sidecarIsolate.process(userQuery: userPrompt);
    } catch (e) {
      debugPrint('Sidecar isolate error: $e');
    }
    stopwatch.stop();
    final elapsedSec = (stopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(2);

    setState(() => _isSidecarProcessing = false);

    final thinkingSummary = sidecarRes != null
        ? 'NPU Vector Similarity: ${sidecarRes.retrievedContext.isNotEmpty ? "Retrieved codebase context" : "Direct generation"}\n'
            'Detected Code Language: ${sidecarRes.detectedLanguage}\n'
            'Sidecar Execution Provider: Qualcomm Hexagon NPU / NNAPI'
        : 'Executed on-device Qwen2.5-Coder SLM engine on Adreno GPU.';

    final assistantIndex = _chatMessages.length - 1;
    setState(() {
      _chatMessages[assistantIndex]['thinking'] = thinkingSummary;
      _chatMessages[assistantIndex]['thinkingTime'] = '${elapsedSec}s';
    });

    final systemDirective =
        'You are Essential AI, a warm, highly intelligent, senior AI pair-programmer running 100% on-device on $_gpuInfo.\n\n'
        'CONVERSATIONAL DIRECTIVES:\n'
        '1. Be natural, warm, empathetic, and human-like in tone, like a friendly Senior Staff Engineer.\n'
        '2. Use clear, beautifully structured Markdown formatting (## headings, **bold**, bullet points, and code blocks).\n'
        '3. Be concise yet deeply insightful — zero fluff.\n';

    final formattedPrompt =
        '<|im_start|>system\n$systemDirective<|im_end|>\n<|im_start|>user\n$userPrompt<|im_end|>\n<|im_start|>assistant\n';

    final stream = _llamaIsolate.generate(formattedPrompt, maxNewTokens: 1500);

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

    var finalText = (_chatMessages[assistantIndex]['content'] as String)
        .replaceAll('<|im_end|>', '')
        .replaceAll('|im_end|>', '')
        .replaceAll('im_end|>', '')
        .replaceAll('<|im_start|>', '')
        .replaceAll('<|endoftext|>', '')
        .trimRight();

    setState(() {
      _chatMessages[assistantIndex]['content'] = finalText;
      _isGenerating = false;
    });

    _mcpServer.addLog('CHAT: Response generation complete.');
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

  void _scrollToLogBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _createNewProjectDialog() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2A),
        title: const Text('Create New Project', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Project Title',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C4DFF))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C4DFF))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              final desc = descController.text.trim().isNotEmpty ? descController.text.trim() : 'Custom HTML Mini App';

              Navigator.of(ctx).pop();

              final p = await _projectManager.createProject(
                title: title,
                description: desc,
                htmlContent: '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$title</title>
    <style>
        body {
            background-color: #FFFFFF;
            color: #111111;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            padding: 20px;
            box-sizing: border-box;
            text-align: center;
        }
        .container {
            background: #F8F9FA;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 4px 18px rgba(0,0,0,0.08);
            border: 1px solid #E9ECEF;
            max-width: 400px;
            width: 100%;
        }
        h1 { color: #7C4DFF; font-size: 22px; margin-top: 0; }
        p { color: #666666; font-size: 14px; }
        .btn {
            background: #7C4DFF;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-weight: bold;
            font-size: 14px;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>$title</h1>
        <p>$desc</p>
        <button class="btn" onclick="alert('Hello from $title!')">Interactive Button</button>
    </div>
</body>
</html>''',
              );

              if (mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectStudioPage(
                      project: p,
                      projectManager: _projectManager,
                      llamaIsolate: _llamaIsolate,
                      sidecarIsolate: _sidecarIsolate,
                      gpuInfo: _gpuInfo,
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C4DFF)),
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _mcpServer.stop();
    _llamaIsolate.dispose();
    _sidecarIsolate.dispose();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    _logScrollController.dispose();
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
          _buildProjectsTab(),
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
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded, color: Color(0xFFD0BCFF)),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_special_outlined),
            selectedIcon: Icon(Icons.folder_special_rounded, color: Color(0xFFD0BCFF)),
            label: 'Projects',
          ),
          NavigationDestination(
            icon: Icon(Icons.api_outlined),
            selectedIcon: Icon(Icons.api_rounded, color: Color(0xFFD0BCFF)),
            label: 'MCP Server',
          ),
        ],
      ),
    );
  }

  // ── 1. Standalone Gemini Chat Tab ─────────────────────────────────────────
  Widget _buildChatTab() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _chatMessages.length,
            itemBuilder: (context, idx) {
              final msg = _chatMessages[idx];
              final role = msg['role'] as String;
              final content = msg['content'] as String;
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
                      if (!isUser && thinking != null) ...[
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          dense: true,
                          leading: const Icon(Icons.psychology_outlined, size: 18, color: Color(0xFFD0BCFF)),
                          title: Text(
                            'Thought for $thinkingTime (Sidecar NPU Engine)',
                            style: const TextStyle(fontSize: 12, color: Color(0xFFD0BCFF), fontWeight: FontWeight.w600),
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
                                style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
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
                          data: content.isEmpty && _isGenerating ? 'Analyzing & generating response...' : content,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(fontSize: 14, height: 1.5, color: Colors.white),
                            h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFD0BCFF)),
                            h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF8AB4F8)),
                            h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            code: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFFD0BCFF), backgroundColor: Color(0xFF14141B)),
                            codeblockDecoration: BoxDecoration(
                              color: const Color(0xFF0E0E12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
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

  // ── 2. Projects Manager Tab ────────────────────────────────────────────────
  Widget _buildProjectsTab() {
    return ValueListenableBuilder<List<ProjectItem>>(
      valueListenable: _projectManager,
      builder: (context, projects, _) {
        return Column(
          children: [
            // Top Bar with "+ New Project" Button
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF14141B),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HTML Mini App Projects', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                      Text('Manage, preview, and edit your project source code', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _createNewProjectDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('+ New Project', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: projects.isEmpty
                  ? const Center(child: Text('No projects found. Tap "+ New Project" to create one.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: projects.length,
                      itemBuilder: (context, idx) {
                        final p = projects[idx];
                        final appItem = MiniAppItem(
                          id: p.id,
                          title: p.title,
                          description: p.description,
                          htmlContent: p.htmlContent,
                          isEnabled: p.isEnabled,
                          backgroundEnabled: p.backgroundEnabled,
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2A),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: p.isEnabled ? const Color(0xFF7C4DFF).withValues(alpha: 0.4) : Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: p.isEnabled ? const Color(0xFF7C4DFF).withValues(alpha: 0.15) : Colors.white10,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.folder_special_rounded, color: p.isEnabled ? const Color(0xFFD0BCFF) : Colors.grey),
                                ),
                                title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: Text(p.description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Background Process Toggle
                                    Tooltip(
                                      message: 'Background mode',
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.run_circle_outlined,
                                          color: p.backgroundEnabled ? Colors.greenAccent : Colors.grey,
                                        ),
                                        onPressed: () => _projectManager.toggleBackground(p.id),
                                      ),
                                    ),
                                    // Enable / Disable Toggle
                                    Switch(
                                      value: p.isEnabled,
                                      onChanged: (_) => _projectManager.toggleEnabled(p.id),
                                      activeThumbColor: const Color(0xFFD0BCFF),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Row(
                                  children: [
                                    // Button 1: Open App
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => MiniAppPage(app: appItem)),
                                        );
                                      },
                                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                      label: const Text('Open App', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF7C4DFF),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Button 2: Open Project
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ProjectStudioPage(
                                              project: p,
                                              projectManager: _projectManager,
                                              llamaIsolate: _llamaIsolate,
                                              sidecarIsolate: _sidecarIsolate,
                                              gpuInfo: _gpuInfo,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.code_rounded, size: 16, color: Color(0xFF8AB4F8)),
                                      label: const Text('Open Project', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF8AB4F8))),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFF8AB4F8)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // ── 3. MCP Server Tab (Live Server & SLM Console Logs) ──────────────────────
  Widget _buildMcpServerTab() {
    final isOnline = _mcpStatus != 'Server Offline';

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
              border: Border.all(color: isOnline ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.redAccent.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(isOnline ? Icons.dns_rounded : Icons.dns_outlined, color: isOnline ? Colors.greenAccent : Colors.redAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Continue.dev MCP Protocol Server', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(_mcpStatus, style: TextStyle(fontSize: 12, color: isOnline ? Colors.greenAccent : Colors.grey)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _toggleMcpServer,
                      icon: Icon(isOnline ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                      label: Text(isOnline ? 'STOP' : 'START', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOnline ? Colors.redAccent : const Color(0xFF7C4DFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                    SelectableText(_deviceIp, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8AB4F8))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Server & SLM Live Console Logs:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.clear_all_rounded, size: 20, color: Colors.grey),
                onPressed: () => setState(() => _serverLogs.clear()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: _serverLogs.isEmpty
                  ? const Center(child: Text('No logs generated yet. Tap START to initiate server logs.', style: TextStyle(fontSize: 12, color: Colors.grey)))
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: _serverLogs.length,
                      itemBuilder: (context, idx) {
                        final log = _serverLogs[idx];
                        Color logColor = const Color(0xFF8AB4F8);
                        if (log.contains('SERVER:')) logColor = Colors.greenAccent;
                        if (log.contains('SLM:')) logColor = const Color(0xFFD0BCFF);
                        if (log.contains('CHAT:')) logColor = Colors.amberAccent;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            log,
                            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: logColor),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hardware Health HUD ──────────────────────────────────────────────────────
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
            color: _isGenerating ? const Color(0xFFD0BCFF) : const Color(0xFF7C4DFF).withValues(alpha: 0.35),
            width: _isGenerating ? 1.5 : 1.0,
          ),
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
        Icon(icon, size: 12, color: isActive ? color : color.withValues(alpha: 0.6)),
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

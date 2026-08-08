import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../mini_apps/mini_app_webview.dart';
import '../mini_apps/mini_app_prompts.dart';
import '../mini_apps/mini_app_code_patcher.dart';
import '../orchestration/pipeline_orchestrator.dart';
import 'project_manager.dart';

class ProjectStudioPage extends StatefulWidget {
  final ProjectItem project;
  final ProjectManager projectManager;
  final PipelineOrchestrator orchestrator;
  final String gpuInfo;

  const ProjectStudioPage({
    super.key,
    required this.project,
    required this.projectManager,
    required this.orchestrator,
    required this.gpuInfo,
  });

  @override
  State<ProjectStudioPage> createState() => _ProjectStudioPageState();
}

class _ProjectStudioPageState extends State<ProjectStudioPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    for (final m in widget.project.chatHistory) {
      _messages.add({'role': m['role'], 'content': m['content']});
    }
  }

  void _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;
    _inputController.clear();

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _messages.add({'role': 'assistant', 'content': ''});
      _isGenerating = true;
    });
    _scrollToBottom();

    widget.projectManager.addChatMessageToProject(widget.project.id, 'user', text);

    final editingPrompt = MiniAppPrompts.buildEditingPrompt(
      widget.project.htmlContent,
      text,
    );

    final systemDirective =
        'You are CodingSaathi AI, an expert HTML mini app pair-programmer running 100% on-device on ${widget.gpuInfo}.\n'
        'NPU Pipeline: all-MiniLM-L6-v2 (Intent) → bge-small-v1.5 (Embeddings) → bge-reranker-base (Reranker) → Qwen2.5-Coder (GPU).\n'
        'If you need additional codebase context mid-generation, emit <<NPU_QUERY:your sub-query>>.\n\n'
        '$editingPrompt';

    final assistantIndex = _messages.length - 1;
    try {
      final stream = widget.orchestrator.generate(
        userPrompt:    text,
        systemContext: systemDirective,
        maxNewTokens:  3500,
      );

      await for (final event in stream) {
        if (event.token.isNotEmpty && !event.token.contains('im_end')) {
          setState(() {
            _messages[assistantIndex]['content'] =
                (_messages[assistantIndex]['content'] as String) + event.token;
          });
          _scrollToBottom();
        }
      }

      var finalText = (_messages[assistantIndex]['content'] as String)
          .replaceAll('<|im_end|>', '')
          .replaceAll('|im_end|>', '')
          .replaceAll('im_end|>', '')
          .replaceAll('<|im_start|>', '')
          .replaceAll('<|endoftext|>', '')
          .trimRight();

      if (finalText.isEmpty) {
        finalText = '⚠️ Model is initializing or produced an empty response. Please tap send again.';
      }

      String updatedHtml = MiniAppCodePatcher.extractAppCode(finalText);
      if (updatedHtml.isEmpty || updatedHtml == finalText) {
        if (finalText.contains('<<<<<<< SEARCH') || finalText.contains('<code_diff>')) {
          updatedHtml = MiniAppCodePatcher.applyDiffs(widget.project.htmlContent, finalText);
        }
      }

      if (updatedHtml.isNotEmpty && updatedHtml != widget.project.htmlContent) {
        widget.project.htmlContent = updatedHtml;
        await widget.projectManager.updateProjectHtml(widget.project.id, updatedHtml);
      }

      setState(() {
        _messages[assistantIndex]['content'] = finalText;
      });

      widget.projectManager.addChatMessageToProject(widget.project.id, 'assistant', finalText);
    } catch (e) {
      final errorMsg = '❌ Error during generation: $e. Please verify Qwen model is initialized.';
      setState(() {
        _messages[assistantIndex]['content'] = errorMsg;
      });
      widget.projectManager.addChatMessageToProject(widget.project.id, 'assistant', errorMsg);
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _cleanDisplayContent(String content) {
    String clean = content
        .replaceAll(RegExp(r'<html_app>[\s\S]*?</html_app>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<code_diff>[\s\S]*?</code_diff>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<html_app>[\s\S]*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'<code_diff>[\s\S]*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'<<<<<<<\s*SEARCH[\s\S]*?>>>>>>>\s*REPLACE', caseSensitive: false), '')
        .trim();

    if (clean.isEmpty) {
      return '✨ Project code updated and applied to live preview!';
    }
    return clean;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Text('Project Studio', style: TextStyle(fontSize: 10, color: Color(0xFFD0BCFF))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Reload WebView Preview',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.white,
              child: MiniAppWebViewWidget(
                key: ValueKey('${widget.project.id}_${widget.project.htmlContent.hashCode}'),
                htmlContent: widget.project.htmlContent,
              ),
            ),
          ),
          Container(
            height: 2,
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
          ),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, idx) {
                      final msg = _messages[idx];
                      final isUser = msg['role'] == 'user';
                      final rawContent = msg['content'] as String;

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF7C4DFF) : const Color(0xFF1E1E2A),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: isUser
                              ? SelectableText(rawContent, style: const TextStyle(fontSize: 12, color: Colors.white))
                              : MarkdownBody(
                                  data: rawContent.isEmpty && _isGenerating
                                      ? 'Refining project code...'
                                      : _cleanDisplayContent(rawContent),
                                  styleSheet: MarkdownStyleSheet(
                                    p: const TextStyle(fontSize: 12, height: 1.4, color: Colors.white),
                                    h1: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFD0BCFF)),
                                    h2: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF8AB4F8)),
                                    code: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFFD0BCFF)),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: const Color(0xFF14141B),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Request code changes for this project...',
                            hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      IconButton(
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD0BCFF)),
                              )
                            : const Icon(Icons.send_rounded, color: Color(0xFFD0BCFF)),
                        onPressed: _isGenerating ? null : _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

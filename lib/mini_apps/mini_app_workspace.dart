import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Workspace model for individual HTML Mini Apps with persistent memory & source state.
class MiniAppWorkspace {
  final String id;
  final String title;
  final String directoryPath;
  String htmlContent;
  Map<String, dynamic> stateJson;
  List<Map<String, String>> chatHistory;
  DateTime updatedAt;

  MiniAppWorkspace({
    required this.id,
    required this.title,
    required this.directoryPath,
    required this.htmlContent,
    required this.stateJson,
    required this.chatHistory,
    required this.updatedAt,
  });

  String get indexPath => '$directoryPath/index.html';
  String get statePath => '$directoryPath/state.json';
  String get memoryPath => '$directoryPath/memory.json';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'directoryPath': directoryPath,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// Manager handling isolated workspace storage, persistence, and SLM context anchoring.
class MiniAppWorkspaceManager extends ValueNotifier<List<MiniAppWorkspace>> {
  MiniAppWorkspace? _activeWorkspace;

  MiniAppWorkspaceManager() : super([]);

  MiniAppWorkspace? get activeWorkspace => _activeWorkspace;

  void setActiveWorkspace(MiniAppWorkspace? workspace) {
    _activeWorkspace = workspace;
    notifyListeners();
  }

  Future<void> initializeWorkspaces() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final workspacesDir = Directory('${appDir.path}/workspaces');
      if (!await workspacesDir.exists()) {
        await workspacesDir.create(recursive: true);
      }

      final List<MiniAppWorkspace> loaded = [];
      final entities = workspacesDir.listSync();

      for (final entity in entities) {
        if (entity is Directory) {
          final indexFile = File('${entity.path}/index.html');
          final stateFile = File('${entity.path}/state.json');
          final memoryFile = File('${entity.path}/memory.json');

          if (await indexFile.exists()) {
            final html = await indexFile.readAsString();
            final title = _extractTitle(html, entity.path.split('/').last);

            Map<String, dynamic> stateMap = {};
            if (await stateFile.exists()) {
              try {
                stateMap = jsonDecode(await stateFile.readAsString());
              } catch (_) {}
            }

            List<Map<String, String>> historyList = [];
            if (await memoryFile.exists()) {
              try {
                final raw = jsonDecode(await memoryFile.readAsString()) as List;
                historyList = raw.map((e) => Map<String, String>.from(e as Map)).toList();
              } catch (_) {}
            }

            final ws = MiniAppWorkspace(
              id: entity.path.split('/').last,
              title: title,
              directoryPath: entity.path,
              htmlContent: html,
              stateJson: stateMap,
              chatHistory: historyList,
              updatedAt: indexFile.lastModifiedSync(),
            );
            loaded.add(ws);
          }
        }
      }

      if (loaded.isEmpty) {
        final defaultWs = await createWorkspace(
          title: 'Live Digital Clock',
          htmlContent: '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Live Clock</title>
    <style>
        body { display: flex; flex-direction: column; justify-content: center; align-items: center; height: 100vh; background: #0E0E12; color: #7C4DFF; font-family: monospace; }
        .time { font-size: 48px; font-weight: bold; text-shadow: 0 0 20px rgba(124, 77, 255, 0.6); }
        .date { font-size: 16px; color: #8AB4F8; margin-top: 8px; }
    </style>
</head>
<body>
    <div class="time" id="clock">00:00:00</div>
    <div class="date" id="date">Loading...</div>
    <script>
        function update() {
            const now = new Date();
            document.getElementById('clock').innerText = now.toLocaleTimeString();
            document.getElementById('date').innerText = now.toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
        }
        setInterval(update, 1000);
        update();
    </script>
</body>
</html>''',
        );
        loaded.add(defaultWs);
      }

      value = loaded;
      _activeWorkspace = loaded.first;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing MiniApp workspaces: $e');
    }
  }

  Future<MiniAppWorkspace> createWorkspace({
    required String title,
    required String htmlContent,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final id = 'app_${DateTime.now().millisecondsSinceEpoch}';
    final dirPath = '${appDir.path}/workspaces/$id';

    final dir = Directory(dirPath);
    await dir.create(recursive: true);

    final indexFile = File('$dirPath/index.html');
    await indexFile.writeAsString(htmlContent);

    final stateFile = File('$dirPath/state.json');
    await stateFile.writeAsString(jsonEncode({'version': 1, 'id': id, 'title': title}));

    final memoryFile = File('$dirPath/memory.json');
    await memoryFile.writeAsString(jsonEncode([]));

    final ws = MiniAppWorkspace(
      id: id,
      title: title,
      directoryPath: dirPath,
      htmlContent: htmlContent,
      stateJson: {'version': 1, 'id': id, 'title': title},
      chatHistory: [],
      updatedAt: DateTime.now(),
    );

    value = [...value, ws];
    _activeWorkspace = ws;
    notifyListeners();
    return ws;
  }

  Future<void> updateWorkspaceHtml(String id, String newHtml) async {
    final index = value.indexWhere((w) => w.id == id);
    if (index == -1) return;

    final ws = value[index];
    ws.htmlContent = newHtml;
    ws.updatedAt = DateTime.now();

    final file = File(ws.indexPath);
    await file.writeAsString(newHtml);

    if (_activeWorkspace?.id == id) {
      _activeWorkspace = ws;
    }

    value = List.from(value);
    notifyListeners();
  }

  Future<void> addChatMessageToActiveWorkspace(String role, String content) async {
    if (_activeWorkspace == null) return;
    _activeWorkspace!.chatHistory.add({'role': role, 'content': content});

    final file = File(_activeWorkspace!.memoryPath);
    await file.writeAsString(jsonEncode(_activeWorkspace!.chatHistory));
    notifyListeners();
  }

  String _extractTitle(String html, String fallback) {
    final match = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(html);
    if (match != null && match.group(1)!.trim().isNotEmpty) {
      return match.group(1)!.trim();
    }
    return fallback;
  }
}

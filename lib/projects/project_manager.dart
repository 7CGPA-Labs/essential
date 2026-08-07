import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ProjectItem {
  final String id;
  String title;
  String description;
  final String directoryPath;
  String htmlContent;
  bool isEnabled;
  bool backgroundEnabled;
  List<Map<String, String>> chatHistory;
  DateTime updatedAt;

  ProjectItem({
    required this.id,
    required this.title,
    required this.description,
    required this.directoryPath,
    required this.htmlContent,
    this.isEnabled = true,
    this.backgroundEnabled = false,
    required this.chatHistory,
    required this.updatedAt,
  });

  String get indexPath => '$directoryPath/index.html';
  String get configPath => '$directoryPath/project.json';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'isEnabled': isEnabled,
        'backgroundEnabled': backgroundEnabled,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class ProjectManager extends ValueNotifier<List<ProjectItem>> {
  ProjectManager() : super([]);

  Future<void> initializeProjects() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final projectsDir = Directory('${appDir.path}/projects');
      if (!await projectsDir.exists()) {
        await projectsDir.create(recursive: true);
      }

      final List<ProjectItem> loaded = [];
      final entities = projectsDir.listSync();

      for (final entity in entities) {
        if (entity is Directory) {
          final indexFile = File('${entity.path}/index.html');
          final configFile = File('${entity.path}/project.json');

          if (await indexFile.exists()) {
            final html = await indexFile.readAsString();
            Map<String, dynamic> config = {};
            if (await configFile.exists()) {
              try {
                config = jsonDecode(await configFile.readAsString());
              } catch (_) {}
            }

            final title = config['title'] as String? ?? _extractTitle(html, entity.path.split('/').last);
            final desc = config['description'] as String? ?? 'Custom HTML Project';
            final enabled = config['isEnabled'] as bool? ?? true;
            final bg = config['backgroundEnabled'] as bool? ?? false;
            final rawHistory = config['chatHistory'] as List? ?? [];
            final historyList = rawHistory.map((e) => Map<String, String>.from(e as Map)).toList();

            loaded.add(ProjectItem(
              id: entity.path.split('/').last,
              title: title,
              description: desc,
              directoryPath: entity.path,
              htmlContent: html,
              isEnabled: enabled,
              backgroundEnabled: bg,
              chatHistory: historyList,
              updatedAt: indexFile.lastModifiedSync(),
            ));
          }
        }
      }

      if (loaded.isEmpty) {
        final defaultProject = await createProject(
          title: 'Starter HTML App',
          description: 'White background default mini app template',
          htmlContent: '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Starter HTML App</title>
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
        .card {
            background: #F8F9FA;
            padding: 30px;
            border-radius: 16px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
            border: 1px solid #E9ECEF;
            max-width: 400px;
            width: 100%;
        }
        h1 { color: #7C4DFF; margin-top: 0; font-size: 24px; }
        p { color: #555555; line-height: 1.5; font-size: 14px; }
        button {
            background: #7C4DFF;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-weight: bold;
            font-size: 14px;
            cursor: pointer;
            transition: transform 0.1s ease;
        }
        button:active { transform: scale(0.96); }
    </style>
</head>
<body>
    <div class="card">
        <h1>CodingSaathi HTML Mini App</h1>
        <p>This is a clean, responsive HTML mini app running on white background default canvas.</p>
        <button onclick="countUp()">Taps: <span id="counter">0</span></button>
    </div>
    <script>
        let count = 0;
        function countUp() {
            count++;
            document.getElementById('counter').innerText = count;
            if (navigator.vibrate) navigator.vibrate([15, 30]);
        }
    </script>
</body>
</html>''',
        );
        loaded.add(defaultProject);
      }

      value = loaded;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing projects: $e');
    }
  }

  Future<ProjectItem> createProject({
    required String title,
    String description = 'Created via Project Manager',
    required String htmlContent,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final id = 'project_${DateTime.now().millisecondsSinceEpoch}';
    final dirPath = '${appDir.path}/projects/$id';

    final dir = Directory(dirPath);
    await dir.create(recursive: true);

    final indexFile = File('$dirPath/index.html');
    await indexFile.writeAsString(htmlContent);

    final item = ProjectItem(
      id: id,
      title: title,
      description: description,
      directoryPath: dirPath,
      htmlContent: htmlContent,
      chatHistory: [],
      updatedAt: DateTime.now(),
    );

    final configFile = File('$dirPath/project.json');
    await configFile.writeAsString(jsonEncode(item.toJson()));

    value = [...value, item];
    notifyListeners();
    return item;
  }

  Future<void> updateProjectHtml(String id, String newHtml) async {
    final index = value.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final p = value[index];
    p.htmlContent = newHtml;
    p.updatedAt = DateTime.now();

    final file = File(p.indexPath);
    await file.writeAsString(newHtml);

    final configFile = File(p.configPath);
    await configFile.writeAsString(jsonEncode(p.toJson()));

    value = List.from(value);
    notifyListeners();
  }

  Future<void> toggleEnabled(String id) async {
    final index = value.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final p = value[index];
    p.isEnabled = !p.isEnabled;

    final configFile = File(p.configPath);
    await configFile.writeAsString(jsonEncode(p.toJson()));

    value = List.from(value);
    notifyListeners();
  }

  Future<void> toggleBackground(String id) async {
    final index = value.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final p = value[index];
    p.backgroundEnabled = !p.backgroundEnabled;

    final configFile = File(p.configPath);
    await configFile.writeAsString(jsonEncode(p.toJson()));

    value = List.from(value);
    notifyListeners();
  }

  Future<void> addChatMessageToProject(String id, String role, String content) async {
    final index = value.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final p = value[index];
    p.chatHistory.add({'role': role, 'content': content});

    final configFile = File(p.configPath);
    await configFile.writeAsString(jsonEncode(p.toJson()));
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

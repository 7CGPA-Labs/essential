import 'package:flutter/foundation.dart';

class MiniAppItem {
  final String id;
  final String title;
  final String description;
  final String iconName;
  final String jsCode;
  final List<String> inputs;
  bool isEnabled;
  final DateTime createdAt;

  MiniAppItem({
    required this.id,
    required this.title,
    required this.description,
    required this.iconName,
    required this.jsCode,
    required this.inputs,
    this.isEnabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'iconName': iconName,
        'jsCode': jsCode,
        'inputs': inputs,
        'isEnabled': isEnabled,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MiniAppItem.fromJson(Map<String, dynamic> json) => MiniAppItem(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        iconName: json['iconName'] as String? ?? 'widgets',
        jsCode: json['jsCode'] as String,
        inputs: (json['inputs'] as List).map((e) => e.toString()).toList(),
        isEnabled: json['isEnabled'] as bool? ?? true,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class MiniAppManager extends ValueNotifier<List<MiniAppItem>> {
  static final MiniAppManager _instance = MiniAppManager._internal();
  factory MiniAppManager() => _instance;

  MiniAppManager._internal()
      : super([
          MiniAppItem(
            id: 'widget-calc',
            title: 'QuickJS Calculator',
            description: 'Evaluates dynamic mathematical expressions in sandboxed QuickJS',
            iconName: 'calculate',
            inputs: ['a', 'b'],
            jsCode: 'var res = a * b + 42; "Output: " + res;',
          ),
          MiniAppItem(
            id: 'widget-gpu-meter',
            title: 'GPU Offload Status',
            description: 'Checks GPU layer offload percentage — works on any Android device',
            iconName: 'memory',
            inputs: ['layerCount'],
            jsCode: 'var offloaded = layerCount >= 28 ? "100% GPU Offload" : layerCount > 0 ? "Partial Offload (" + layerCount + " layers)" : "CPU Only Mode"; offloaded;',
          ),
          MiniAppItem(
            id: 'widget-unit-converter',
            title: 'Temperature Converter',
            description: 'Converts Celsius to Fahrenheit safely in JavaScript',
            iconName: 'thermostat',
            inputs: ['celsius'],
            jsCode: 'var f = (celsius * 9/5) + 32; celsius + " °C = " + f + " °F";',
          ),
        ]);

  void addMiniApp(MiniAppItem app) {
    value = [...value, app];
  }

  void removeMiniApp(String id) {
    value = value.where((app) => app.id != id).toList();
  }

  void toggleMiniApp(String id) {
    value = value.map((app) {
      if (app.id == id) {
        app.isEnabled = !app.isEnabled;
      }
      return app;
    }).toList();
  }

  void updateMiniAppCode(String id, String newJsCode) {
    value = value.map((app) {
      if (app.id == id) {
        return MiniAppItem(
          id: app.id,
          title: app.title,
          description: app.description,
          iconName: app.iconName,
          jsCode: newJsCode,
          inputs: app.inputs,
          isEnabled: app.isEnabled,
          createdAt: app.createdAt,
        );
      }
      return app;
    }).toList();
  }
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:torch_light/torch_light.dart';
import '../ffi/llama_isolate.dart';
import '../sandbox/js_sandbox.dart';
import '../mini_apps/mini_app_webview.dart';

// ── Node Types ────────────────────────────────────────────────────────────────

enum DagNodeType {
  input,
  gpsTrigger,
  sensorTrigger,
  llm,
  jsTransform,
  condition,
  notificationAction,
  flashAction,
  output,
}

extension DagNodeTypeX on DagNodeType {
  String get label => switch (this) {
        DagNodeType.input => 'Input',
        DagNodeType.gpsTrigger => 'GPS Trigger',
        DagNodeType.sensorTrigger => 'Gyro Sensor',
        DagNodeType.llm => 'LLM Inference',
        DagNodeType.jsTransform => 'JS Transform',
        DagNodeType.condition => 'Condition',
        DagNodeType.notificationAction => 'Notify Action',
        DagNodeType.flashAction => 'Flashlight Action',
        DagNodeType.output => 'Output',
      };

  IconData get icon => switch (this) {
        DagNodeType.input => Icons.input_rounded,
        DagNodeType.gpsTrigger => Icons.location_on_outlined,
        DagNodeType.sensorTrigger => Icons.screen_rotation_outlined,
        DagNodeType.llm => Icons.smart_toy_outlined,
        DagNodeType.jsTransform => Icons.code_rounded,
        DagNodeType.condition => Icons.call_split_rounded,
        DagNodeType.notificationAction => Icons.notifications_active_outlined,
        DagNodeType.flashAction => Icons.flashlight_on_outlined,
        DagNodeType.output => Icons.output_rounded,
      };

  Color get color => switch (this) {
        DagNodeType.input => const Color(0xFF4CAF50),
        DagNodeType.gpsTrigger => const Color(0xFF00E676),
        DagNodeType.sensorTrigger => const Color(0xFF1DE9B6),
        DagNodeType.llm => const Color(0xFF7C4DFF),
        DagNodeType.jsTransform => const Color(0xFF00BCD4),
        DagNodeType.condition => const Color(0xFFFF9800),
        DagNodeType.notificationAction => const Color(0xFFFFC107),
        DagNodeType.flashAction => const Color(0xFFFF5722),
        DagNodeType.output => const Color(0xFFE91E63),
      };
}

// ── DAG Node Model ────────────────────────────────────────────────────────────

class DagNode {
  final String id;
  final DagNodeType type;
  String label;
  String config; // prompt, jsCode, condition expr, value, target coords
  Offset position;
  String? outputValue; // result after execution
  bool isRunning = false;
  bool isDone = false;
  bool hasError = false;

  DagNode({
    required this.id,
    required this.type,
    required this.label,
    required this.position,
    this.config = '',
    this.outputValue,
  });
}

// ── DAG Edge Model ────────────────────────────────────────────────────────────

class DagEdge {
  final String fromNodeId;
  final String toNodeId;
  DagEdge({required this.fromNodeId, required this.toNodeId});
}

// ── DAG Workflow State ────────────────────────────────────────────────────────

class DagWorkflowState extends ChangeNotifier {
  final List<DagNode> nodes = [];
  final List<DagEdge> edges = [];

  String? _pendingEdgeFrom;
  String? get pendingEdgeFrom => _pendingEdgeFrom;

  void refresh() => notifyListeners();

  void addNode(DagNode node) {
    nodes.add(node);
    notifyListeners();
  }

  void removeNode(String id) {
    nodes.removeWhere((n) => n.id == id);
    edges.removeWhere((e) => e.fromNodeId == id || e.toNodeId == id);
    notifyListeners();
  }

  void moveNode(String id, Offset delta) {
    final n = nodes.firstWhere((n) => n.id == id, orElse: () => nodes.first);
    n.position += delta;
    notifyListeners();
  }

  void startEdge(String fromId) {
    _pendingEdgeFrom = fromId;
    notifyListeners();
  }

  void connectEdge(String toId) {
    if (_pendingEdgeFrom != null && _pendingEdgeFrom != toId) {
      final exists = edges.any(
          (e) => e.fromNodeId == _pendingEdgeFrom && e.toNodeId == toId);
      if (!exists) {
        edges.add(DagEdge(fromNodeId: _pendingEdgeFrom!, toNodeId: toId));
      }
    }
    _pendingEdgeFrom = null;
    notifyListeners();
  }

  void cancelEdge() {
    _pendingEdgeFrom = null;
    notifyListeners();
  }

  void removeEdge(String fromId, String toId) {
    edges.removeWhere((e) => e.fromNodeId == fromId && e.toNodeId == toId);
    notifyListeners();
  }

  void updateNodeConfig(String id, String config) {
    final n = nodes.firstWhere((n) => n.id == id);
    n.config = config;
    notifyListeners();
  }

  void updateNodeLabel(String id, String label) {
    final n = nodes.firstWhere((n) => n.id == id);
    n.label = label;
    notifyListeners();
  }

  void resetExecution() {
    for (final n in nodes) {
      n.outputValue = null;
      n.isDone = false;
      n.isRunning = false;
      n.hasError = false;
    }
    notifyListeners();
  }

  List<DagNode> topologicalOrder() {
    final inDegree = {for (final n in nodes) n.id: 0};
    for (final e in edges) {
      inDegree[e.toNodeId] = (inDegree[e.toNodeId] ?? 0) + 1;
    }

    final queue = nodes.where((n) => inDegree[n.id] == 0).toList();
    final result = <DagNode>[];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      result.add(current);
      for (final e in edges.where((e) => e.fromNodeId == current.id)) {
        inDegree[e.toNodeId] = (inDegree[e.toNodeId] ?? 1) - 1;
        if (inDegree[e.toNodeId] == 0) {
          final next = nodes.firstWhere((n) => n.id == e.toNodeId);
          queue.add(next);
        }
      }
    }
    return result;
  }

  String? getInputFor(String nodeId) {
    final incoming = edges.where((e) => e.toNodeId == nodeId);
    final parts = <String>[];
    for (final e in incoming) {
      final src = nodes.firstWhere((n) => n.id == e.fromNodeId,
          orElse: () => nodes.first);
      if (src.outputValue != null) parts.add(src.outputValue!);
    }
    return parts.isEmpty ? null : parts.join('\n');
  }
}

// ── DAG Executor ─────────────────────────────────────────────────────────────

class DagExecutor {
  final DagWorkflowState state;
  final LlamaIsolateWrapper llamaIsolate;

  DagExecutor({required this.state, required this.llamaIsolate});

  Future<void> run() async {
    state.resetExecution();
    final order = state.topologicalOrder();

    for (final node in order) {
      node.isRunning = true;
      state.refresh();

      try {
        final input = state.getInputFor(node.id);

        switch (node.type) {
          case DagNodeType.input:
            node.outputValue = node.config.isNotEmpty ? node.config : 'Start Payload';

          case DagNodeType.gpsTrigger:
            var perm = await Geolocator.checkPermission();
            if (perm == LocationPermission.denied) {
              perm = await Geolocator.requestPermission();
            }
            if (perm == LocationPermission.denied ||
                perm == LocationPermission.deniedForever) {
              node.outputValue = 'GPS Permission Denied';
            } else {
              final pos = await Geolocator.getCurrentPosition(
                  locationSettings:
                      const LocationSettings(accuracy: LocationAccuracy.high));
              node.outputValue =
                  'GPS Lat: ${pos.latitude.toStringAsFixed(5)}, Lng: ${pos.longitude.toStringAsFixed(5)}';
            }

          case DagNodeType.sensorTrigger:
            node.outputValue = 'Sensor Trigger Active (Gyro/Accel)';

          case DagNodeType.llm:
            final prompt = node.config.isNotEmpty
                ? node.config
                : (input ?? 'Summarize input');
            final systemPrompt = input != null && node.config.isNotEmpty
                ? '${node.config}\n\nInput Context: $input'
                : prompt;

            final formatted =
                '<|im_start|>system\nYou are a helpful workflow AI assistant. Be concise.<|im_end|>\n<|im_start|>user\n$systemPrompt<|im_end|>\n<|im_start|>assistant\n';

            final sb = StringBuffer();
            await for (final event
                in llamaIsolate.generate(formatted, maxNewTokens: 512)) {
              if (!event.token.contains('im_end')) {
                sb.write(event.token);
              }
            }
            node.outputValue = sb
                .toString()
                .replaceAll('<|im_end|>', '')
                .replaceAll('<|im_start|>', '')
                .trimRight();

          case DagNodeType.jsTransform:
            final code = node.config.isNotEmpty
                ? node.config
                : 'input.toUpperCase()';
            final ctx = {'input': input ?? ''};
            node.outputValue = JsSandbox.execute(code, ctx);

          case DagNodeType.condition:
            final expr = node.config.isNotEmpty
                ? node.config
                : 'input.length > 0';
            final ctx = {'input': input ?? ''};
            final result = JsSandbox.execute(expr, ctx);
            node.outputValue = 'Gate Pass: $result\nPayload: ${input ?? ""}';

          case DagNodeType.notificationAction:
            final notifText = node.config.isNotEmpty
                ? node.config
                : (input ?? 'Essential Workflow Notification');
            await MiniAppNotifications.show(
              appId: node.id,
              title: 'Essential Action',
              body: notifText,
            );
            node.outputValue = 'Notification Fired: "$notifText"';

          case DagNodeType.flashAction:
            final enable = node.config.toLowerCase() != 'false';
            try {
              if (enable) {
                await TorchLight.enableTorch();
                await Future.delayed(const Duration(seconds: 2));
                await TorchLight.disableTorch();
              } else {
                await TorchLight.disableTorch();
              }
              node.outputValue = 'Torch Flashed Successfully';
            } catch (e) {
              node.outputValue = 'Flashlight unavailable: $e';
            }

          case DagNodeType.output:
            node.outputValue = input ?? '(no input)';
        }

        node.isDone = true;
        node.isRunning = false;
      } catch (e) {
        node.hasError = true;
        node.outputValue = 'Error: $e';
        node.isRunning = false;
      }

      state.refresh();
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }
}

// ── Edge Painter ──────────────────────────────────────────────────────────────

class _EdgePainter extends CustomPainter {
  final List<DagEdge> edges;
  final List<DagNode> nodes;
  static const double nodeW = 160;
  static const double nodeH = 72;

  _EdgePainter(this.edges, this.nodes);

  Offset _center(DagNode n) =>
      n.position + const Offset(nodeW / 2, nodeH / 2);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7C4DFF).withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final arrowPaint = Paint()
      ..color = const Color(0xFF7C4DFF).withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    for (final edge in edges) {
      try {
        final from = nodes.firstWhere((n) => n.id == edge.fromNodeId);
        final to = nodes.firstWhere((n) => n.id == edge.toNodeId);
        final start = _center(from);
        final end = _center(to);

        final cp1 = Offset(start.dx + (end.dx - start.dx) * 0.5, start.dy);
        final cp2 = Offset(start.dx + (end.dx - start.dx) * 0.5, end.dy);
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

        canvas.drawPath(path, paint);

        final angle = atan2(end.dy - cp2.dy, end.dx - cp2.dx);
        final arrowLen = 12.0;
        final p1 = end;
        final p2 = Offset(end.dx - arrowLen * cos(angle - 0.4),
            end.dy - arrowLen * sin(angle - 0.4));
        final p3 = Offset(end.dx - arrowLen * cos(angle + 0.4),
            end.dy - arrowLen * sin(angle + 0.4));
        canvas.drawPath(
            Path()..moveTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..lineTo(p3.dx, p3.dy)..close(),
            arrowPaint);
      } catch (_) {}
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

// ── Node Card Widget ──────────────────────────────────────────────────────────

class _DagNodeCard extends StatelessWidget {
  final DagNode node;
  final bool isConnecting;
  final VoidCallback onDragStart;
  final void Function(Offset delta) onDrag;
  final VoidCallback onTap;
  final VoidCallback onConnectTap;
  final VoidCallback onDelete;

  const _DagNodeCard({
    super.key,
    required this.node,
    required this.isConnecting,
    required this.onDragStart,
    required this.onDrag,
    required this.onTap,
    required this.onConnectTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = node.type.color;
    final borderColor = node.hasError
        ? Colors.redAccent
        : node.isDone
            ? Colors.greenAccent.withValues(alpha: 0.8)
            : node.isRunning
                ? color
                : color.withValues(alpha: 0.4);

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: GestureDetector(
        onPanUpdate: (d) => onDrag(d.delta),
        onTap: onTap,
        child: Container(
          width: 160,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: node.isRunning ? 2.5 : 1.5,
            ),
            boxShadow: node.isRunning
                ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)]
                : null,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 8, top: 8, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(node.type.icon, size: 14, color: color),
                        const SizedBox(width: 4),
                        Text(
                          node.type.label,
                          style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: onConnectTap,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: isConnecting
                                  ? color
                                  : color.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isConnecting ? Icons.link_rounded : Icons.arrow_forward_rounded,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: onDelete,
                          child: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      node.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (node.isDone && node.outputValue != null)
                      Text(
                        node.outputValue!.replaceAll('\n', ' '),
                        style: const TextStyle(fontSize: 9, color: Colors.greenAccent),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      )
                    else if (node.isRunning)
                      const SizedBox(
                        height: 8,
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation(Color(0xFF7C4DFF)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Node Config Bottom Sheet ──────────────────────────────────────────────────

void _showNodeConfig(BuildContext context, DagNode node, DagWorkflowState state) {
  final labelCtrl = TextEditingController(text: node.label);
  final configCtrl = TextEditingController(text: node.config);

  final hint = switch (node.type) {
    DagNodeType.input => 'Enter static input text / value',
    DagNodeType.gpsTrigger => 'Target GPS coords or description',
    DagNodeType.sensorTrigger => 'Gyroscope sensitivity / axis',
    DagNodeType.llm => 'System prompt / instruction for this LLM node',
    DagNodeType.jsTransform => 'JS expression. Use `input` variable.\nExample: input.toUpperCase()',
    DagNodeType.condition => 'JS condition. Returns true/false.\nExample: input.length > 10',
    DagNodeType.notificationAction => 'Notification message text',
    DagNodeType.flashAction => 'true to enable flash, false to disable',
    DagNodeType.output => 'Label for this output node',
  };

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14141B),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(node.type.icon, color: node.type.color, size: 20),
              const SizedBox(width: 8),
              Text(
                'Configure: ${node.type.label}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: labelCtrl,
            decoration: InputDecoration(
              labelText: 'Node Label',
              filled: true,
              fillColor: const Color(0xFF1E1E2A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: configCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Configuration',
              hintText: hint,
              hintMaxLines: 3,
              filled: true,
              fillColor: const Color(0xFF1E1E2A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                state.updateNodeLabel(node.id, labelCtrl.text);
                state.updateNodeConfig(node.id, configCtrl.text);
                Navigator.pop(ctx);
              },
              child: const Text('Save Node'),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Main DAG Canvas Widget ────────────────────────────────────────────────────

class DagWorkflowCanvas extends StatefulWidget {
  final LlamaIsolateWrapper llamaIsolate;
  const DagWorkflowCanvas({super.key, required this.llamaIsolate});

  @override
  State<DagWorkflowCanvas> createState() => _DagWorkflowCanvasState();
}

class _DagWorkflowCanvasState extends State<DagWorkflowCanvas> {
  final DagWorkflowState _state = DagWorkflowState();
  bool _isRunning = false;
  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _state.addListener(() => setState(() {}));
    _seedStarterWorkflow();
  }

  void _seedStarterWorkflow() {
    _state.addNode(DagNode(
      id: 'n1',
      type: DagNodeType.gpsTrigger,
      label: 'GPS Sensor',
      position: const Offset(40, 80),
      config: 'Auto-reads current GPS location',
    ));
    _state.addNode(DagNode(
      id: 'n2',
      type: DagNodeType.llm,
      label: 'On-Device LLM',
      position: const Offset(260, 80),
      config: 'Summarize location data and create status update',
    ));
    _state.addNode(DagNode(
      id: 'n3',
      type: DagNodeType.notificationAction,
      label: 'Push Notif',
      position: const Offset(480, 80),
      config: 'GPS Workflow Update',
    ));
    _state.addNode(DagNode(
      id: 'n4',
      type: DagNodeType.output,
      label: 'Final Output',
      position: const Offset(700, 80),
      config: '',
    ));
    _state.edges.add(DagEdge(fromNodeId: 'n1', toNodeId: 'n2'));
    _state.edges.add(DagEdge(fromNodeId: 'n2', toNodeId: 'n3'));
    _state.edges.add(DagEdge(fromNodeId: 'n3', toNodeId: 'n4'));
  }

  void _addNode(DagNodeType type) {
    final id = 'node-${DateTime.now().millisecondsSinceEpoch}';
    final rng = Random();
    _state.addNode(DagNode(
      id: id,
      type: type,
      label: type.label,
      position: Offset(60 + rng.nextDouble() * 200, 200 + rng.nextDouble() * 200),
      config: '',
    ));
  }

  Future<void> _runWorkflow() async {
    setState(() => _isRunning = true);
    try {
      final executor = DagExecutor(state: _state, llamaIsolate: widget.llamaIsolate);
      await executor.run();
    } finally {
      setState(() => _isRunning = false);
    }
  }

  void _showAddNodeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Hardware / Logic Node',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: DagNodeType.values.map((type) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _addNode(type);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: type.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: type.color.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(type.icon, color: type.color, size: 18),
                        const SizedBox(width: 8),
                        Text(type.label,
                            style: TextStyle(
                                color: type.color, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildResultPanel() {
    final outputs = _state.nodes
        .where((n) => n.outputValue != null && n.isDone)
        .toList();
    if (outputs.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 16),
            SizedBox(width: 6),
            Text('Workflow Execution Live Summary',
                style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          ...outputs.map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${n.label}: ${n.outputValue!.replaceAll('\n', ' ')}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontFamily: 'monospace'),
                ),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF14141B),
          child: Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DAG Workflows',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  Text('Sensor Trigger → SLM Logic → Action',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.grey, size: 20),
                tooltip: 'Reset results',
                onPressed: _isRunning ? null : _state.resetExecution,
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF8AB4F8), size: 22),
                tooltip: 'Add node',
                onPressed: _showAddNodeSheet,
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: _isRunning ? null : _runWorkflow,
                icon: _isRunning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(_isRunning ? 'Running...' : 'Run All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_state.pendingEdgeFrom != null) _state.cancelEdge();
            },
            child: InteractiveViewer(
              transformationController: _transformCtrl,
              boundaryMargin: const EdgeInsets.all(500),
              minScale: 0.3,
              maxScale: 2.5,
              child: SizedBox(
                width: 1200,
                height: 900,
                child: Stack(
                  children: [
                    CustomPaint(
                      size: const Size(1200, 900),
                      painter: _GridPainter(),
                    ),
                    CustomPaint(
                      size: const Size(1200, 900),
                      painter: _EdgePainter(_state.edges, _state.nodes),
                    ),
                    ..._state.nodes.map((node) => _DagNodeCard(
                          key: ValueKey(node.id),
                          node: node,
                          isConnecting: _state.pendingEdgeFrom == node.id,
                          onDragStart: () {},
                          onDrag: (delta) => _state.moveNode(node.id, delta),
                          onTap: () {
                            if (_state.pendingEdgeFrom != null) {
                              _state.connectEdge(node.id);
                            } else {
                              _showNodeConfig(context, node, _state);
                            }
                          },
                          onConnectTap: () {
                            if (_state.pendingEdgeFrom == node.id) {
                              _state.cancelEdge();
                            } else {
                              _state.startEdge(node.id);
                            }
                          },
                          onDelete: () => _state.removeNode(node.id),
                        )),
                    if (_state.pendingEdgeFrom != null)
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C4DFF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Tap another node to connect → or canvas to cancel',
                              style: TextStyle(fontSize: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildResultPanel(),
      ],
    );
  }
}

// ── Grid Background Painter ───────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;

    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter _) => false;
}

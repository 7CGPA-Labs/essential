import 'package:flutter/material.dart';
import 'js_sandbox.dart';
import 'mini_app_manager.dart';

/// Interactive Renderer & Manager Card for Custom Android Mini-Apps & Micro Widgets.
class MiniAppWidgetCard extends StatefulWidget {
  final MiniAppItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const MiniAppWidgetCard({
    super.key,
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<MiniAppWidgetCard> createState() => _MiniAppWidgetCardState();
}

class _MiniAppWidgetCardState extends State<MiniAppWidgetCard> {
  final Map<String, TextEditingController> _inputControllers = {};
  String _executionResult = 'Tap Run to execute in QuickJS sandbox';
  bool _isExecuting = false;
  bool _isExpanded = false;

  bool _isTextInput(String name) {
    const textHints = ['place', 'city', 'name', 'query', 'url', 'text', 'word',
        'country', 'address', 'location', 'search', 'keyword', 'phrase', 'string',
        'message', 'input', 'label', 'tag'];
    final lower = name.toLowerCase();
    return textHints.any((h) => lower.contains(h));
  }

  @override
  void initState() {
    super.initState();
    for (final inputName in widget.item.inputs) {
      _inputControllers[inputName] = TextEditingController(
        text: _isTextInput(inputName) ? '' : '10',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _inputControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _runMiniApp() {
    setState(() {
      _isExecuting = true;
    });

    final Map<String, dynamic> contextData = {};
    for (final entry in _inputControllers.entries) {
      final numVal = num.tryParse(entry.value.text);
      contextData[entry.key] = numVal ?? entry.value.text;
    }

    final resultStr = JsSandbox.execute(widget.item.jsCode, contextData);

    setState(() {
      _executionResult = resultStr;
      _isExecuting = false;
    });
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'calculate':
        return Icons.calculate_outlined;
      case 'memory':
        return Icons.memory_outlined;
      case 'thermostat':
        return Icons.thermostat_outlined;
      default:
        return Icons.widgets_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.item.isEnabled;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isEnabled ? const Color(0xFF1E1E2A) : const Color(0xFF14141B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled ? Colors.deepPurpleAccent.withValues(alpha: 0.4) : Colors.white10,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: isEnabled ? Colors.deepPurpleAccent.withValues(alpha: 0.2) : Colors.white12,
              child: Icon(_getIconData(widget.item.iconName), color: isEnabled ? const Color(0xFFD0BCFF) : Colors.grey),
            ),
            title: Text(
              widget.item.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isEnabled ? Colors.white : Colors.grey,
              ),
            ),
            subtitle: Text(
              widget.item.description,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: isEnabled,
                    onChanged: (_) => widget.onToggle(),
                    activeThumbColor: const Color(0xFFD0BCFF),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  ),
                ),
              ],
            ),
          ),
          if (_isExpanded && isEnabled) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: Colors.white10),
                  const SizedBox(height: 12),
                  // Inputs Section
                  if (widget.item.inputs.isNotEmpty) ...[
                    const Text('Widget Input Parameters:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...widget.item.inputs.map((inputName) {
                      final isText = _isTextInput(inputName);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: TextField(
                          controller: _inputControllers[inputName],
                          keyboardType: isText
                              ? TextInputType.text
                              : const TextInputType.numberWithOptions(decimal: true),
                          textCapitalization: isText
                              ? TextCapitalization.words
                              : TextCapitalization.none,
                          decoration: InputDecoration(
                            labelText: inputName,
                            hintText: isText ? 'Enter $inputName...' : 'Enter number',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: const Color(0xFF14141B),
                            prefixIcon: Icon(
                              isText ? Icons.text_fields_rounded : Icons.numbers_rounded,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 8),
                  // Execute Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isExecuting ? null : _runMiniApp,
                      icon: _isExecuting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(_isExecuting ? 'Running...' : 'Execute Widget'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C4DFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Result Display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E0E12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('QuickJS Output:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        SelectableText(
                          _executionResult,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF8AB4F8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      label: const Text('Delete Widget', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

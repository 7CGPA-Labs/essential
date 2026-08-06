import 'package:flutter/material.dart';
import 'mini_app_manager.dart';
import 'mini_app_webview.dart';
import 'mini_app_service.dart';

class MiniAppsHubTab extends StatelessWidget {
  final MiniAppManager manager;
  const MiniAppsHubTab({super.key, required this.manager});

  void _showCreateSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final htmlCtrl = TextEditingController(text: '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  body { background:#0E0E12; color:#fff; font-family:sans-serif;
         display:flex; flex-direction:column; align-items:center;
         justify-content:center; min-height:100vh; gap:16px; }
  h1 { color:#D0BCFF; }
  button { padding:12px 28px; background:#7C4DFF; color:#fff;
           border:none; border-radius:20px; font-size:16px; cursor:pointer; }
</style>
</head>
<body>
  <h1>My Mini App</h1>
  <p>Edit this HTML to build your app.</p>
  <button onclick="notify()">Send Notification</button>
<script>
  function notify() {
    Essential.notify("Hello!", "This is from my mini app.");
  }
</script>
</body>
</html>''');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: ListView(
            controller: scroll,
            children: [
              const Text('Create HTML Mini App',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'App Title',
                  filled: true,
                  fillColor: const Color(0xFF1E1E2A),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: 'Description',
                  filled: true,
                  fillColor: const Color(0xFF1E1E2A),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: TextField(
                  controller: htmlCtrl,
                  maxLines: 18,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'HTML + CSS + JS Source',
                    labelStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Bridge API hint
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
                ),
                child: const Text(
                  '💡 Essential Bridge API:\n'
                  'Essential.notify("Title", "Body")  — push notification\n'
                  'Essential.getLocation()  — GPS coords → onLocationResult(lat, lng, acc)\n'
                  'Essential.log("msg")  — console log',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8AB4F8), height: 1.6),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  if (titleCtrl.text.trim().isEmpty) return;
                  manager.addMiniApp(MiniAppItem(
                    id: 'app-${DateTime.now().millisecondsSinceEpoch}',
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim().isNotEmpty
                        ? descCtrl.text.trim()
                        : 'Custom HTML Mini App',
                    htmlContent: htmlCtrl.text,
                  ));
                  Navigator.pop(ctx);
                },
                child: const Text('Create Mini App'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MiniAppItem>>(
      valueListenable: manager,
      builder: (ctx, apps, _) {
        final active = apps.where((a) => a.isEnabled).length;
        final bg = apps.where((a) => a.backgroundEnabled && a.isEnabled).length;

        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              color: const Color(0xFF14141B),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('HTML Mini Apps',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      Text(
                        '$active active${bg > 0 ? " · $bg in background" : ""}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Background service status
                      FutureBuilder<bool>(
                        future: MiniAppBackgroundService.isRunning(),
                        builder: (_, snap) {
                          final running = snap.data ?? false;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: running
                                  ? Colors.greenAccent.withValues(alpha: 0.1)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: running
                                      ? Colors.greenAccent.withValues(alpha: 0.4)
                                      : Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle,
                                    size: 7,
                                    color: running
                                        ? Colors.greenAccent
                                        : Colors.grey),
                                const SizedBox(width: 5),
                                Text(running ? 'Service Active' : 'Service Off',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: running
                                            ? Colors.greenAccent
                                            : Colors.grey)),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      // Create button
                      ElevatedButton.icon(
                        onPressed: () => _showCreateSheet(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Create'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C4DFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // App list
            Expanded(
              child: apps.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.web_outlined,
                              size: 64, color: Colors.white12),
                          const SizedBox(height: 12),
                          const Text('No mini apps yet',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.grey)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _showCreateSheet(context),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create your first mini app'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C4DFF),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: apps.length,
                      itemBuilder: (_, i) {
                        final app = apps[i];
                        return MiniAppCard(
                          app: app,
                          manager: manager,
                          onLaunch: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => MiniAppPage(app: app)),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

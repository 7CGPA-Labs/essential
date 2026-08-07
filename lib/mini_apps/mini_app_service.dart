import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'mini_app_webview.dart';

// ── Background Service for Mini Apps ─────────────────────────────────────────
//
// When a mini app has backgroundEnabled = true, this foreground service
// keeps a persistent notification and can execute JS-like Dart logic
// while the app is in background.
//
// Architecture:
//   main isolate ──[startService()]──> BackgroundService (foreground service)
//                <──[invoke('data', ...)]── background isolate
//
// The foreground service shows a persistent notification per running app.

class MiniAppBackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Call once at app startup to configure the background service.
  static Future<void> configure() async {
    await MiniAppNotifications.init();
    final androidConfig = AndroidConfiguration(
      onStart: _onBackgroundStart,
      autoStart: false,
      isForegroundMode: false,
      notificationChannelId: 'mini_apps_bg_channel',
      initialNotificationTitle: 'CodingSaathi Mini Apps',
      initialNotificationContent: 'Running mini apps in background',
      foregroundServiceNotificationId: 9900,
    );

    final iosConfig = IosConfiguration(autoStart: false);

    await _service.configure(
      androidConfiguration: androidConfig,
      iosConfiguration: iosConfig,
    );
  }

  static Future<void> startForApp(String appId, String appTitle) async {
    final running = await _service.isRunning();
    if (!running) await _service.startService();
    _service.invoke('registerApp', {'id': appId, 'title': appTitle});
  }

  static Future<void> stopForApp(String appId) async {
    _service.invoke('unregisterApp', {'id': appId});
  }

  static Future<bool> isRunning() => _service.isRunning();
}

/// Entry point for the background isolate — must be a top-level function.
@pragma('vm:entry-point')
void _onBackgroundStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notifications = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(const InitializationSettings(android: androidInit));

  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        'mini_apps_bg_channel',
        'Mini Apps Background Service',
        description: 'Persistent background service for CodingSaathi Mini Apps',
        importance: Importance.low,
      ));


  // Track which apps are registered
  final Set<String> runningApps = {};

  service.on('registerApp').listen((data) {
    if (data == null) return;
    final id = data['id'] as String? ?? '';
    final title = data['title'] as String? ?? 'Mini App';
    runningApps.add(id);

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'CodingSaathi — ${runningApps.length} app(s) running',
        content: runningApps.length == 1 ? title : '${runningApps.length} mini apps active',
      );
    }
  });

  service.on('unregisterApp').listen((data) {
    if (data == null) return;
    final id = data['id'] as String? ?? '';
    runningApps.remove(id);

    if (runningApps.isEmpty) {
      service.stopSelf();
    } else if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'CodingSaathi — ${runningApps.length} app(s) running',
        content: '${runningApps.length} mini apps active in background',
      );
    }
  });

  // Periodic heartbeat every 30s — can trigger scheduled JS logic here
  Timer.periodic(const Duration(seconds: 30), (_) {
    if (runningApps.isEmpty) return;
    // Post a silent status update (can be extended to run JS callbacks)
    service.invoke('heartbeat', {
      'timestamp': DateTime.now().toIso8601String(),
      'apps': runningApps.toList(),
    });
  });
}

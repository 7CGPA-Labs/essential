import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:torch_light/torch_light.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'mini_app_manager.dart';

// ── Notification Helper ────────────────────────────────────────────────────────

class MiniAppNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );

    // Standard static notifications channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'mini_apps_channel',
          'Mini Apps Alerts',
          description: 'Static notifications from HTML mini apps',
          importance: Importance.defaultImportance,
        ));

    // Live Ongoing notifications channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'mini_apps_live_channel',
          'Mini Apps Live Status',
          description: 'Ongoing live notifications for active mini app tasks',
          importance: Importance.high,
          showBadge: true,
        ));

    // Background Service notification channel
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'mini_apps_bg_channel',
          'Mini Apps Background Service',
          description: 'Persistent background service for Essential Mini Apps',
          importance: Importance.low,
        ));

    _initialized = true;
  }

  static Future<void> show({
    required String appId,
    required String title,
    required String body,
  }) async {
    await init();
    await Permission.notification.request();
    await _plugin.show(
      appId.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'mini_apps_channel',
          'Mini Apps Alerts',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  // ── Live Ongoing Notification APIs ──────────────────────────────────────────

  static Future<void> startLiveNotification({
    required String liveId,
    required String title,
    required String body,
  }) async {
    await init();
    await Permission.notification.request();
    await _plugin.show(
      liveId.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'mini_apps_live_channel',
          'Mini Apps Live Status',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  static Future<void> updateLiveNotification({
    required String liveId,
    required String title,
    required String body,
  }) async {
    await startLiveNotification(liveId: liveId, title: title, body: body);
  }

  static Future<void> stopLiveNotification(String liveId) async {
    await init();
    await _plugin.cancel(liveId.hashCode);
  }
}

// ── Full-Screen Mini App WebView Page ─────────────────────────────────────────

class MiniAppPage extends StatefulWidget {
  final MiniAppItem app;
  const MiniAppPage({super.key, required this.app});

  @override
  State<MiniAppPage> createState() => _MiniAppPageState();
}

class _MiniAppPageState extends State<MiniAppPage> {
  late final WebViewController _controller;
  bool _loading = true;

  // Stream Subscriptions
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<GyroscopeEvent>? _gyroStream;
  StreamSubscription<UserAccelerometerEvent>? _accelStream;
  StreamSubscription<MagnetometerEvent>? _magStream;

  // Active Geo-Alarm State: {lat, lng, radius, title, body, triggered}
  Map<String, dynamic>? _activeGeoAlarm;

  @override
  void initState() {
    super.initState();
    _buildController();
  }

  void _buildController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0E0E12))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..addJavaScriptChannel(
        'EssentialBridge',
        onMessageReceived: (msg) async {
          try {
            final parts = msg.message.split('|||');
            final action = parts[0];

            switch (action) {
              // 1. Notifications
              case 'notify':
                if (parts.length >= 3) {
                  await MiniAppNotifications.show(
                    appId: widget.app.id,
                    title: parts[1],
                    body: parts[2],
                  );
                }
              case 'startLiveNotification':
                if (parts.length >= 4) {
                  await MiniAppNotifications.startLiveNotification(
                    liveId: parts[1],
                    title: parts[2],
                    body: parts[3],
                  );
                }
              case 'updateLiveNotification':
                if (parts.length >= 4) {
                  await MiniAppNotifications.updateLiveNotification(
                    liveId: parts[1],
                    title: parts[2],
                    body: parts[3],
                  );
                }
              case 'stopLiveNotification':
                if (parts.length >= 2) {
                  await MiniAppNotifications.stopLiveNotification(parts[1]);
                }

              // 2. GPS & Location
              case 'getLocation':
                await _handleGetLocation();
              case 'watchLocation':
                await _startWatchLocation();
              case 'clearWatch':
                await _stopWatchLocation();
              case 'setGeoAlarm':
                if (parts.length >= 6) {
                  await _handleSetGeoAlarm(
                    targetLat: double.tryParse(parts[1]) ?? 0,
                    targetLng: double.tryParse(parts[2]) ?? 0,
                    radiusM: double.tryParse(parts[3]) ?? 500,
                    title: parts[4],
                    body: parts[5],
                  );
                }
              case 'clearGeoAlarm':
                _clearGeoAlarm();

              // 3. Sensors
              case 'watchSensor':
                if (parts.length >= 2) {
                  _startWatchSensor(parts[1]);
                }
              case 'stopSensor':
                if (parts.length >= 2) {
                  _stopWatchSensor(parts[1]);
                }

              // 4. Torch / Flashlight
              case 'setFlashlight':
                if (parts.length >= 2) {
                  final enable = parts[1] == 'true';
                  await _setFlashlight(enable);
                }

              // 5. Network Status
              case 'getNetworkStatus':
                await _getNetworkStatus();
            }
          } catch (_) {}
        },
      )
      ..loadHtmlString(_injectBridge(widget.app.htmlContent));
  }

  /// Injects full Essential JS API into the WebView window
  String _injectBridge(String html) {
    const bridge = '''
<script>
(function() {
  window.Essential = {
    // 1. Notifications
    notify: function(title, body) {
      EssentialBridge.postMessage('notify|||' + title + '|||' + body);
    },
    startLiveNotification: function(id, title, body) {
      EssentialBridge.postMessage('startLiveNotification|||' + id + '|||' + title + '|||' + body);
    },
    updateLiveNotification: function(id, title, body) {
      EssentialBridge.postMessage('updateLiveNotification|||' + id + '|||' + title + '|||' + body);
    },
    stopLiveNotification: function(id) {
      EssentialBridge.postMessage('stopLiveNotification|||' + id);
    },

    // 2. GPS & Geofence
    getLocation: function() {
      EssentialBridge.postMessage('getLocation|||');
    },
    watchLocation: function() {
      EssentialBridge.postMessage('watchLocation|||');
    },
    clearWatch: function() {
      EssentialBridge.postMessage('clearWatch|||');
    },
    setGeoAlarm: function(lat, lng, radiusMeters, notifTitle, notifBody) {
      EssentialBridge.postMessage('setGeoAlarm|||' + lat + '|||' + lng + '|||' +
          radiusMeters + '|||' + notifTitle + '|||' + notifBody);
    },
    clearGeoAlarm: function() {
      EssentialBridge.postMessage('clearGeoAlarm|||');
    },

    // 3. Hardware Sensors (gyroscope, accelerometer, magnetometer)
    watchSensor: function(type) {
      EssentialBridge.postMessage('watchSensor|||' + type);
    },
    stopSensor: function(type) {
      EssentialBridge.postMessage('stopSensor|||' + type);
    },

    // 4. Torch / Flashlight
    setFlashlight: function(enabled) {
      EssentialBridge.postMessage('setFlashlight|||' + enabled);
    },

    // 5. Connectivity
    getNetworkStatus: function() {
      EssentialBridge.postMessage('getNetworkStatus|||');
    },

    log: function(msg) { console.log('[Essential Bridge] ' + msg); }
  };
})();
</script>''';

    if (html.contains('</body>')) {
      return html.replaceFirst('</body>', '$bridge\n</body>');
    }
    return html + bridge;
  }

  // ── Sensor Implementation ──────────────────────────────────────────────────

  void _startWatchSensor(String type) {
    if (type == 'gyroscope') {
      _gyroStream?.cancel();
      _gyroStream = gyroscopeEventStream().listen((e) {
        _controller.runJavaScript(
            'typeof onSensorData === "function" && onSensorData("gyroscope", ${e.x}, ${e.y}, ${e.z})');
      });
    } else if (type == 'accelerometer') {
      _accelStream?.cancel();
      _accelStream = userAccelerometerEventStream().listen((e) {
        _controller.runJavaScript(
            'typeof onSensorData === "function" && onSensorData("accelerometer", ${e.x}, ${e.y}, ${e.z})');
      });
    } else if (type == 'magnetometer') {
      _magStream?.cancel();
      _magStream = magnetometerEventStream().listen((e) {
        _controller.runJavaScript(
            'typeof onSensorData === "function" && onSensorData("magnetometer", ${e.x}, ${e.y}, ${e.z})');
      });
    }
  }

  void _stopWatchSensor(String type) {
    if (type == 'gyroscope') _gyroStream?.cancel();
    if (type == 'accelerometer') _accelStream?.cancel();
    if (type == 'magnetometer') _magStream?.cancel();
  }

  // ── Torch Implementation ───────────────────────────────────────────────────

  Future<void> _setFlashlight(bool enable) async {
    try {
      if (enable) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
    } catch (_) {}
  }

  // ── Network Status Implementation ───────────────────────────────────────────

  Future<void> _getNetworkStatus() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final connected = !results.contains(ConnectivityResult.none);
      final typeStr = results.isNotEmpty ? results.first.name : 'unknown';
      await _controller.runJavaScript(
          'typeof onNetworkStatus === "function" && onNetworkStatus("$typeStr", $connected)');
    } catch (_) {}
  }

  // ── GPS & Geofence Implementation ───────────────────────────────────────────

  Future<void> _handleGetLocation() async {
    try {
      final pos = await _getPermissionedPosition();
      if (pos == null) return;
      await _controller.runJavaScript(
          'typeof onLocationResult === "function" && '
          'onLocationResult(${pos.latitude}, ${pos.longitude}, ${pos.accuracy})');
    } catch (e) {
      await _controller.runJavaScript(
          'typeof onLocationResult === "function" && onLocationResult(0, 0, -1)');
    }
  }

  Future<Position?> _getPermissionedPosition() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high));
  }

  Future<void> _startWatchLocation() async {
    await _stopWatchLocation();
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) async {
      await _controller.runJavaScript(
          'typeof onLocationResult === "function" && '
          'onLocationResult(${pos.latitude}, ${pos.longitude}, ${pos.accuracy})');

      final alarm = _activeGeoAlarm;
      if (alarm != null && alarm['triggered'] != true) {
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          alarm['lat'] as double,
          alarm['lng'] as double,
        );

        await _controller.runJavaScript(
            'typeof onDistanceUpdate === "function" && '
            'onDistanceUpdate(${dist.toStringAsFixed(1)})');

        if (dist <= (alarm['radius'] as double)) {
          alarm['triggered'] = true;
          await _controller.runJavaScript(
              'typeof onGeoAlarmTriggered === "function" && onGeoAlarmTriggered()');
          await MiniAppNotifications.show(
            appId: widget.app.id,
            title: alarm['title'] as String,
            body: alarm['body'] as String,
          );
        }
      }
    });
  }

  Future<void> _stopWatchLocation() async {
    await _positionStream?.cancel();
    _positionStream = null;
  }

  Future<void> _handleSetGeoAlarm({
    required double targetLat,
    required double targetLng,
    required double radiusM,
    required String title,
    required String body,
  }) async {
    _activeGeoAlarm = {
      'lat': targetLat,
      'lng': targetLng,
      'radius': radiusM,
      'title': title,
      'body': body,
      'triggered': false,
    };
    await _startWatchLocation();
  }

  void _clearGeoAlarm() {
    _activeGeoAlarm = null;
    _stopWatchLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _gyroStream?.cancel();
    _accelStream?.cancel();
    _magStream?.cancel();
    TorchLight.disableTorch().catchError((_) {});
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
        title: Text(
          widget.app.title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
            onPressed: () {
              setState(() => _loading = true);
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C4DFF)),
            ),
        ],
      ),
    );
  }
}

// ── Mini App Card (in hub list) ───────────────────────────────────────────────

class MiniAppCard extends StatelessWidget {
  final MiniAppItem app;
  final MiniAppManager manager;
  final VoidCallback onLaunch;

  const MiniAppCard({
    super.key,
    required this.app,
    required this.manager,
    required this.onLaunch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: app.isEnabled
              ? const Color(0xFF7C4DFF).withValues(alpha: 0.4)
              : Colors.white10,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: app.isEnabled
                    ? const Color(0xFF7C4DFF).withValues(alpha: 0.15)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.web_rounded,
                  color: app.isEnabled
                      ? const Color(0xFFD0BCFF)
                      : Colors.grey,
                  size: 24),
            ),
            title: Text(
              app.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: app.isEnabled ? Colors.white : Colors.grey,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              app.description,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Background toggle
                Tooltip(
                  message: 'Background mode',
                  child: GestureDetector(
                    onTap: () => manager.toggleBackground(app.id),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: app.backgroundEnabled
                            ? Colors.greenAccent.withValues(alpha: 0.15)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.run_circle_outlined,
                        size: 18,
                        color: app.backgroundEnabled
                            ? Colors.greenAccent
                            : Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Enable toggle
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: app.isEnabled,
                    onChanged: (_) => manager.toggleEnabled(app.id),
                    activeThumbColor: const Color(0xFFD0BCFF),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          if (app.isEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  if (app.backgroundEnabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 7, color: Colors.greenAccent),
                          SizedBox(width: 4),
                          Text('Background',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.greenAccent)),
                        ],
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => manager.removeMiniApp(app.id),
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: Colors.redAccent),
                    label: const Text('Delete',
                        style:
                            TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    onPressed: onLaunch,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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

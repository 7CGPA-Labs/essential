import 'dart:convert';
import 'mini_app_code_patcher.dart';

/// Secure WebView Controller Service that prepares HTML strings,
/// injects Content Security Policy (CSP) meta tags, window.FlutterBridge wrapper,
/// and performs fallback tag auto-repair before invoking loadHtmlString().
class WebViewSandboxService {
  /// Standard CSP Meta Tag to be injected into mini apps
  static const String cspMetaTag =
      '<meta http-equiv="Content-Security-Policy" content="default-src \'self\' \'unsafe-inline\' \'unsafe-eval\' data: blob: https:;">';

  /// Standard Host Bridge template wrapper injected into the HTML window object
  static const String flutterBridgeShell = '''
<script>
  (function() {
    if (!window.FlutterBridge) {
      window.FlutterBridge = {
        callNative: function(method, payload) {
          if (window.FlutterChannel) {
            var data = (typeof payload === 'object') ? JSON.stringify({ method: method, payload: payload }) : JSON.stringify({ method: method, payload: { raw: payload } });
            window.FlutterChannel.postMessage(data);
          } else if (window.EssentialBridge) {
            window.EssentialBridge.postMessage(method + '|||' + (payload ? JSON.stringify(payload) : ''));
          }
        }
      };
    }

    // Ensure DOMContentLoaded event listener compatibility
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function() {
        console.log('[FlutterBridge] Host Bridge Initialized on DOMContentLoaded');
      });
    } else {
      console.log('[FlutterBridge] Host Bridge Initialized');
    }
  })();
</script>
''';

  /// Essential JS API wrapper built on top of window.FlutterBridge
  static const String essentialBridgeWrapper = '''
<script>
  (function() {
    if (!window.Essential) {
      window.Essential = {
        notify: function(title, body) {
          window.FlutterBridge.callNative('notify', { title: title, body: body });
        },
        startLiveNotification: function(id, title, body) {
          window.FlutterBridge.callNative('startLiveNotification', { id: id, title: title, body: body });
        },
        updateLiveNotification: function(id, title, body) {
          window.FlutterBridge.callNative('updateLiveNotification', { id: id, title: title, body: body });
        },
        stopLiveNotification: function(id) {
          window.FlutterBridge.callNative('stopLiveNotification', { id: id });
        },
        getLocation: function() {
          window.FlutterBridge.callNative('getLocation', {});
        },
        watchLocation: function() {
          window.FlutterBridge.callNative('watchLocation', {});
        },
        clearWatch: function() {
          window.FlutterBridge.callNative('clearWatch', {});
        },
        setGeoAlarm: function(lat, lng, radiusMeters, notifTitle, notifBody) {
          window.FlutterBridge.callNative('setGeoAlarm', { lat: lat, lng: lng, radius: radiusMeters, title: notifTitle, body: notifBody });
        },
        clearGeoAlarm: function() {
          window.FlutterBridge.callNative('clearGeoAlarm', {});
        },
        watchSensor: function(type) {
          window.FlutterBridge.callNative('watchSensor', { type: type });
        },
        stopSensor: function(type) {
          window.FlutterBridge.callNative('stopSensor', { type: type });
        },
        setFlashlight: function(enabled) {
          window.FlutterBridge.callNative('setFlashlight', { enabled: enabled });
        },
        getNetworkStatus: function() {
          window.FlutterBridge.callNative('getNetworkStatus', {});
        },
        log: function(msg) { console.log('[Essential Bridge] ' + msg); }
      };
    }
  })();
</script>
''';

  /// Prepares an HTML string by applying tag auto-repair, injecting CSP, and wrapping with FlutterBridge shell.
  static String prepareHtml(String rawHtml) {
    // 1. Fallback auto-repair for unclosed tags
    String repaired = MiniAppCodePatcher.autoRepairHtml(rawHtml);

    // 2. Inject CSP meta tag if missing
    if (!repaired.toLowerCase().contains('content-security-policy')) {
      if (repaired.toLowerCase().contains('<head>')) {
        repaired = repaired.replaceFirst(
          RegExp(r'<head>', caseSensitive: false),
          '<head>\n  $cspMetaTag',
        );
      } else if (repaired.toLowerCase().contains('<html>')) {
        repaired = repaired.replaceFirst(
          RegExp(r'<html>', caseSensitive: false),
          '<html>\n<head>\n  $cspMetaTag\n</head>',
        );
      } else {
        repaired = '$cspMetaTag\n$repaired';
      }
    }

    // 3. Inject FlutterBridge and Essential shell scripts
    final fullBridge = '$flutterBridgeShell\n$essentialBridgeWrapper';
    if (repaired.toLowerCase().contains('</head>')) {
      repaired = repaired.replaceFirst(
        RegExp(r'</head>', caseSensitive: false),
        '$fullBridge\n</head>',
      );
    } else if (repaired.toLowerCase().contains('<body>')) {
      repaired = repaired.replaceFirst(
        RegExp(r'<body>', caseSensitive: false),
        '<body>\n$fullBridge',
      );
    } else {
      repaired = '$fullBridge\n$repaired';
    }

    return repaired;
  }

  /// Parses JSON payload received from FlutterChannel
  static NativeBridgeMessage? parseChannelMessage(String messageText) {
    try {
      final decoded = jsonDecode(messageText);
      if (decoded is Map<String, dynamic>) {
        final method = decoded['method'] as String? ?? '';
        final payload = decoded['payload'];
        Map<String, dynamic> payloadMap = {};
        if (payload is Map<String, dynamic>) {
          payloadMap = payload;
        } else if (payload != null) {
          payloadMap = {'data': payload};
        }
        return NativeBridgeMessage(method: method, payload: payloadMap);
      }
    } catch (_) {
      // Fallback for pipe-separated legacy format: method|||arg1|||arg2
      final parts = messageText.split('|||');
      if (parts.isNotEmpty) {
        final method = parts[0];
        final Map<String, dynamic> payloadMap = {};
        for (int i = 1; i < parts.length; i++) {
          payloadMap['arg$i'] = parts[i];
        }
        return NativeBridgeMessage(method: method, payload: payloadMap);
      }
    }
    return null;
  }
}

class NativeBridgeMessage {
  final String method;
  final Map<String, dynamic> payload;

  NativeBridgeMessage({required this.method, required this.payload});
}

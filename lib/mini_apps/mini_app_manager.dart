import 'package:flutter/foundation.dart';

/// A full HTML+CSS+JS mini app that runs in an Android WebView.
/// Can request GPS, fire notifications, and run in background.
class MiniAppItem {
  final String id;
  String title;
  String description;
  String htmlContent; // Full HTML+CSS+JS source
  bool isEnabled;
  bool backgroundEnabled; // Whether this app should run in background
  final DateTime createdAt;

  MiniAppItem({
    required this.id,
    required this.title,
    required this.description,
    required this.htmlContent,
    this.isEnabled = true,
    this.backgroundEnabled = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

// ── Seed Templates ─────────────────────────────────────────────────────────────

String _clockHtml() => '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    background: linear-gradient(135deg, #0E0E12, #1E1E2A);
    color: #fff; font-family: sans-serif;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    min-height: 100vh;
  }
  #clock { font-size: 64px; font-weight: 200; letter-spacing: 4px; color: #D0BCFF; }
  #date  { font-size: 18px; color: #8AB4F8; margin-top: 8px; }
  button {
    margin-top: 24px; padding: 10px 28px;
    background: #7C4DFF; color: #fff;
    border: none; border-radius: 24px; font-size: 15px; cursor: pointer;
  }
</style>
</head>
<body>
  <div id="clock">--:--:--</div>
  <div id="date"></div>
  <button onclick="notify()">🔔 Notify Me</button>
<script>
  function tick() {
    const now = new Date();
    document.getElementById('clock').textContent = now.toLocaleTimeString();
    document.getElementById('date').textContent = now.toDateString();
  }
  tick(); setInterval(tick, 1000);
  function notify() {
    if (typeof Essential !== 'undefined') {
      Essential.notify('Live Clock', 'Current time: ' + new Date().toLocaleTimeString());
    } else { alert('Essential bridge not available'); }
  }
</script>
</body>
</html>''';

String _gpsHtml() => '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    background: linear-gradient(135deg, #0E0E12, #1A1A2E);
    color: #fff; font-family: sans-serif;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    min-height: 100vh; gap: 16px;
  }
  h2 { color: #4CAF50; font-size: 22px; }
  #coords { font-size: 14px; color: #8AB4F8; text-align: center; line-height: 1.8; }
  button {
    padding: 12px 32px; background: #4CAF50;
    color: #fff; border: none; border-radius: 24px; font-size: 15px; cursor: pointer;
  }
  #status { color: #aaa; font-size: 13px; }
</style>
</head>
<body>
  <h2>📍 GPS Tracker</h2>
  <div id="coords">Tap below to get location</div>
  <div id="status"></div>
  <button onclick="getLocation()">Get My Location</button>
<script>
  function getLocation() {
    document.getElementById('status').textContent = 'Fetching GPS...';
    if (typeof Essential !== 'undefined') {
      Essential.getLocation();
    } else if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(showPos, showErr);
    } else {
      document.getElementById('coords').textContent = 'GPS not available';
    }
  }
  function showPos(pos) {
    document.getElementById('coords').innerHTML =
      'Lat: ' + pos.coords.latitude.toFixed(6) + '<br>' +
      'Lng: ' + pos.coords.longitude.toFixed(6) + '<br>' +
      'Accuracy: ±' + Math.round(pos.coords.accuracy) + 'm';
    document.getElementById('status').textContent = 'Location fetched!';
  }
  function showErr(e) {
    document.getElementById('coords').textContent = 'Error: ' + e.message;
    document.getElementById('status').textContent = '';
  }
  // Called by Flutter bridge
  function onLocationResult(lat, lng, acc) {
    showPos({ coords: { latitude: lat, longitude: lng, accuracy: acc } });
    document.getElementById('status').textContent = '';
    if (typeof Essential !== 'undefined') {
      Essential.notify('GPS Location', 'Lat: ' + lat.toFixed(4) + ', Lng: ' + lng.toFixed(4));
    }
  }
</script>
</body>
</html>''';

String _calcHtml() => '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { background:#0E0E12; color:#fff; font-family:sans-serif; display:flex; justify-content:center; align-items:center; min-height:100vh; }
  .calc { background:#1E1E2A; border-radius:24px; padding:24px; width:300px; }
  #display { background:#0E0E12; border-radius:12px; padding:16px; font-size:32px; text-align:right; color:#D0BCFF; min-height:60px; word-break:break-all; margin-bottom:16px; }
  .grid { display:grid; grid-template-columns:repeat(4,1fr); gap:8px; }
  button { padding:16px; border-radius:12px; border:none; font-size:18px; cursor:pointer; background:#2A2A3A; color:#fff; transition:background 0.15s; }
  button:active { background:#7C4DFF; }
  .op { background:#7C4DFF33; color:#D0BCFF; }
  .eq { background:#7C4DFF; color:#fff; grid-column:span 2; }
  .zero { grid-column:span 2; }
</style>
</head>
<body>
<div class="calc">
  <div id="display">0</div>
  <div class="grid">
    <button onclick="clr()">C</button><button onclick="sign()">+/-</button><button onclick="pct()">%</button><button class="op" onclick="op('/')">÷</button>
    <button onclick="dig('7')">7</button><button onclick="dig('8')">8</button><button onclick="dig('9')">9</button><button class="op" onclick="op('*')">×</button>
    <button onclick="dig('4')">4</button><button onclick="dig('5')">5</button><button onclick="dig('6')">6</button><button class="op" onclick="op('-')">−</button>
    <button onclick="dig('1')">1</button><button onclick="dig('2')">2</button><button onclick="dig('3')">3</button><button class="op" onclick="op('+')">+</button>
    <button class="zero" onclick="dig('0')">0</button><button onclick="dot()">.</button><button class="eq" onclick="eq()">=</button>
  </div>
</div>
<script>
  let cur='0', prev='', oper='', fresh=true;
  const d = () => document.getElementById('display');
  function dig(n) { if(fresh||cur==='0'){cur=n;fresh=false;}else{cur+=n;} d().textContent=cur; }
  function op(o) { prev=cur; oper=o; fresh=true; }
  function eq() { if(!oper)return; let r=eval(prev+oper+cur); cur=String(r); d().textContent=cur; oper=''; fresh=true; }
  function clr() { cur='0';prev='';oper='';fresh=true;d().textContent='0'; }
  function sign() { cur=String(-parseFloat(cur));d().textContent=cur; }
  function pct() { cur=String(parseFloat(cur)/100);d().textContent=cur; }
  function dot() { if(!cur.includes('.')){cur+='.';d().textContent=cur;} }
</script>
</body>
</html>''';

// ── Manager ────────────────────────────────────────────────────────────────────

class MiniAppManager extends ValueNotifier<List<MiniAppItem>> {
  MiniAppManager()
      : super([
          MiniAppItem(
            id: 'app-clock',
            title: 'Live Clock',
            description: 'Real-time clock with notification support',
            htmlContent: _clockHtml(),
          ),
          MiniAppItem(
            id: 'app-gps',
            title: 'GPS Tracker',
            description: 'Live GPS location via device hardware bridge',
            htmlContent: _gpsHtml(),
            backgroundEnabled: true,
          ),
          MiniAppItem(
            id: 'app-calc',
            title: 'Calculator',
            description: 'Full-featured calculator running in WebView',
            htmlContent: _calcHtml(),
          ),
        ]);

  void addMiniApp(MiniAppItem app) {
    value = [...value, app];
  }

  void removeMiniApp(String id) {
    value = value.where((a) => a.id != id).toList();
  }

  void toggleEnabled(String id) {
    final updated = value.map((a) {
      if (a.id == id) a.isEnabled = !a.isEnabled;
      return a;
    }).toList();
    value = updated;
  }

  void toggleBackground(String id) {
    final updated = value.map((a) {
      if (a.id == id) a.backgroundEnabled = !a.backgroundEnabled;
      return a;
    }).toList();
    value = updated;
  }

  void updateHtml(String id, String html) {
    final updated = value.map((a) {
      if (a.id == id) a.htmlContent = html;
      return a;
    }).toList();
    value = updated;
  }
}

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Data Models
struct TelemetryEntry: TimelineEntry {
    let date: Date
    let isServerRunning: Bool
    let serverPort: Int
    let wifiIP: String
    let cpuPct: Double
    let ramMB: Double
    let gpuPct: Double
    let npuLatencyMs: Double
}

// MARK: - Provider
struct TelemetryProvider: TimelineProvider {
    func placeholder(in context: Context) -> TelemetryEntry {
        TelemetryEntry(date: Date(), isServerRunning: true, serverPort: 8080, wifiIP: "192.168.1.100", cpuPct: 45.2, ramMB: 1024.0, gpuPct: 30.1, npuLatencyMs: 12.0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TelemetryEntry) -> Void) {
        let entry = readSharedState()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TelemetryEntry>) -> Void) {
        var entries: [TelemetryEntry] = []
        let currentDate = Date()
        
        let currentState = readSharedState()
        
        for offset in 0 ..< 6 {
            let entryDate = Calendar.current.date(byAdding: .second, value: offset * 10, to: currentDate)!
            let entry = TelemetryEntry(
                date: entryDate,
                isServerRunning: currentState.isServerRunning,
                serverPort: currentState.serverPort,
                wifiIP: currentState.wifiIP,
                cpuPct: currentState.cpuPct,
                ramMB: currentState.ramMB,
                gpuPct: currentState.gpuPct,
                npuLatencyMs: currentState.npuLatencyMs
            )
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

// Reads shared data from UserDefaults(suiteName: "group.dev.seven_cgpalabs.codingsaathi")
extension TelemetryProvider {
    func readSharedState() -> TelemetryEntry {
        let defaults = UserDefaults(suiteName: "group.dev.seven_cgpalabs.codingsaathi")
        let isServerRunning = defaults?.bool(forKey: "server_running") ?? false
        let serverPort = defaults?.integer(forKey: "server_port") ?? 8080
        let wifiIP = defaults?.string(forKey: "wifi_ip") ?? "127.0.0.1"
        let cpuPct = defaults?.double(forKey: "cpu_pct") ?? 0.0
        let ramMB = defaults?.double(forKey: "ram_mb") ?? 0.0
        let gpuPct = defaults?.double(forKey: "gpu_pct") ?? 0.0
        let npuLatencyMs = defaults?.double(forKey: "npu_latency_ms") ?? 0.0
        
        return TelemetryEntry(
            date: Date(),
            isServerRunning: isServerRunning,
            serverPort: serverPort,
            wifiIP: wifiIP,
            cpuPct: cpuPct,
            ramMB: ramMB,
            gpuPct: gpuPct,
            npuLatencyMs: npuLatencyMs
        )
    }
}

// MARK: - Widget View
struct ServerTelemetryWidgetView: View {
    let entry: TelemetryEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.18), Color.black]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text("🏰 Kingdom AI")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Circle()
                        .fill(entry.isServerRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
                
                // IP Address
                Text("http://\(entry.wifiIP):\(entry.serverPort)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 0.6, green: 0.8, blue: 1.0))
                
                if family == .systemMedium || family == .systemLarge {
                    // Telemetry grid
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⚡ \(entry.cpuPct, specifier: "%.1f")%")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            Text("💾 \(Int(entry.ramMB)) MB")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("🎮 \(entry.gpuPct, specifier: "%.1f")%")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            Text("⚡ \(Int(entry.npuLatencyMs))ms")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 4)
                    
                    Spacer()
                    
                    // Toggle button
                    Button(intent: ServerToggleIntent(action: .toggle)) {
                        Text(entry.isServerRunning ? "Stop Server" : "Start Server")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(entry.isServerRunning ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                            .cornerRadius(8)
                    }
                } else {
                    // Small widget layout
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CPU: \(entry.cpuPct, specifier: "%.1f")%")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                        Text("RAM: \(Int(entry.ramMB)) MB")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Widget Configuration
struct ServerTelemetryWidget: Widget {
    let kind: String = "ServerTelemetryWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TelemetryProvider()) { entry in
            ServerTelemetryWidgetView(entry: entry)
        }
        .configurationDisplayName("Kingdom AI Server")
        .description("On-device AI server telemetry and control")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

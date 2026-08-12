import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Provider

struct ServerTelemetryEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let serverURL: String
    let cpuPercent: Double
    let ramUsedMB: Int
    let ramTotalMB: Int
    let gpuPercent: Double
    let vramUsedMB: Int
    let vramTotalMB: Int
    let npuLatencyMs: Double
}

struct ServerTelemetryProvider: TimelineProvider {
    func placeholder(in context: Context) -> ServerTelemetryEntry {
        ServerTelemetryEntry(
            date: Date(),
            isRunning: false,
            serverURL: "http://127.0.0.1:8080",
            cpuPercent: 0, ramUsedMB: 0, ramTotalMB: 0,
            gpuPercent: 0, vramUsedMB: 0, vramTotalMB: 0,
            npuLatencyMs: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ServerTelemetryEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ServerTelemetryEntry>) -> Void) {
        // Read current server state from shared UserDefaults
        let defaults = UserDefaults(suiteName: "group.dev.seven_cgpalabs.codingsaathi") ?? .standard
        let running = defaults.bool(forKey: "server_running")
        let cpu = defaults.double(forKey: "telemetry_cpu")
        let ramUsed = defaults.integer(forKey: "telemetry_ram_used")
        let ramTotal = defaults.integer(forKey: "telemetry_ram_total")

        let entry = ServerTelemetryEntry(
            date: Date(),
            isRunning: running,
            serverURL: running ? "http://127.0.0.1:8080" : "Server Offline",
            cpuPercent: cpu,
            ramUsedMB: ramUsed,
            ramTotalMB: ramTotal,
            gpuPercent: 0, vramUsedMB: 0, vramTotalMB: 0,
            npuLatencyMs: 0
        )

        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Toggle Intent (AppIntent)

@available(iOS 17.0, *)
struct ToggleServerIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AI Server"
    static var description = IntentDescription("Start or stop the Kingdom AI Server")

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.dev.seven_cgpalabs.codingsaathi") ?? .standard
        let wasRunning = defaults.bool(forKey: "server_running")
        defaults.set(!wasRunning, forKey: "server_running")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Widget View

struct ServerTelemetryWidgetView: View {
    let entry: ServerTelemetryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Status row
            HStack {
                Text(entry.isRunning ? "🟢 Active" : "🔴 Stopped")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(entry.serverURL)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            // Telemetry gauges
            HStack {
                Text("CPU: \(String(format: "%.1f", entry.cpuPercent))%")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Spacer()
                Text("RAM: \(entry.ramUsedMB)/\(entry.ramTotalMB) MB")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            }

            // Toggle button
            if #available(iOS 17.0, *) {
                Button(intent: ToggleServerIntent()) {
                    Text(entry.isRunning ? "⏹ STOP" : "▶ START")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

// MARK: - Widget Configuration

struct ServerTelemetryWidget: Widget {
    let kind = "ServerTelemetryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ServerTelemetryProvider()) { entry in
            ServerTelemetryWidgetView(entry: entry)
                .containerBackground(Color.black.opacity(0.85), for: .widget)
        }
        .configurationDisplayName("AI Server")
        .description("Kingdom AI Server telemetry and controls")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

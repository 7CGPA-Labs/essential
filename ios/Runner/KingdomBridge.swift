import Foundation
import Combine

struct ServerTelemetry: Codable {
    let cpu_pct: Double
    let ram_mb: Double
    let gpu_pct: Double
    let vram_mb: Double
    let npu_latency_ms: Double
}

final class KingdomState: ObservableObject {
    static let shared = KingdomState()
    @Published var isServerRunning: Bool = false
    @Published var serverPort: Int = 8080
    @Published var telemetry: ServerTelemetry = ServerTelemetry(cpu_pct: 0, ram_mb: 0, gpu_pct: 0, vram_mb: 0, npu_latency_ms: 0)
    @Published var wifiIP: String = "127.0.0.1"
    
    private let defaults = UserDefaults(suiteName: "group.dev.seven_cgpalabs.codingsaathi")
    
    init() {
        updateFromUserDefaults()
    }
    
    func updateFromUserDefaults() {
        if let defaults = defaults {
            isServerRunning = defaults.bool(forKey: "isServerRunning")
            let port = defaults.integer(forKey: "serverPort")
            if port > 0 { serverPort = port }
            wifiIP = Self.getWiFiIPAddress()
        }
    }
    
    func persistState() {
        if let defaults = defaults {
            defaults.set(isServerRunning, forKey: "isServerRunning")
            defaults.set(serverPort, forKey: "serverPort")
        }
    }
    
    static func getWiFiIPAddress() -> String {
        var address: String = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

final class KingdomBridge {
    static let shared = KingdomBridge()
    private var engineHandle: KingdomEngineHandle? = nil
    private let queue = DispatchQueue(label: "dev.seven_cgpalabs.kingdom", qos: .userInitiated)
    
    var isInitialized: Bool { engineHandle != nil }
    var isServerRunning: Bool {
        guard let handle = engineHandle else { return false }
        return kingdom_engine_is_server_running(handle)
    }
    
    func initialize(storageDir: String, llmPath: String) -> Bool {
        // Assume storage_dir and llm_path are converted properly to char* implicitly or use withCString
        return storageDir.withCString { storageCStr in
            return llmPath.withCString { llmCStr in
                engineHandle = kingdom_engine_init(storageCStr, llmCStr)
                return engineHandle != nil
            }
        }
    }
    
    func destroy() {
        if let handle = engineHandle {
            kingdom_engine_destroy(handle)
            engineHandle = nil
        }
    }
    
    @discardableResult func startServer(port: Int = 8080) -> Bool {
        guard let handle = engineHandle else { return false }
        let success = kingdom_engine_start_server(handle, Int32(port))
        if success {
            DispatchQueue.main.async {
                KingdomState.shared.isServerRunning = true
                KingdomState.shared.serverPort = port
                KingdomState.shared.persistState()
                NotificationCenter.default.post(name: NSNotification.Name("KingdomServerStarted"), object: nil)
            }
        }
        return success
    }
    
    func stopServer() {
        guard let handle = engineHandle else { return }
        kingdom_engine_stop_server(handle)
        DispatchQueue.main.async {
            KingdomState.shared.isServerRunning = false
            KingdomState.shared.persistState()
            NotificationCenter.default.post(name: NSNotification.Name("KingdomServerStopped"), object: nil)
        }
    }
    
    func getTelemetry() -> ServerTelemetry? {
        guard let handle = engineHandle else { return nil }
        guard let jsonCStr = kingdom_engine_telemetry_json(handle) else { return nil }
        let jsonStr = String(cString: jsonCStr)
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ServerTelemetry.self, from: data)
    }
    
    func getRecentLogs(maxLines: Int = 100) -> String {
        guard let handle = engineHandle else { return "" }
        guard let logsCStr = kingdom_engine_get_recent_logs(handle, Int32(maxLines)) else { return "" }
        return String(cString: logsCStr)
    }
    
    func getStatusJSON() -> String {
        guard let handle = engineHandle else { return "{}" }
        guard let statusCStr = kingdom_engine_status_json(handle) else { return "{}" }
        return String(cString: statusCStr)
    }
}

import UIKit

final class LogExportManager {
    static let shared = LogExportManager()
    
    func getLogFileURL() -> URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("server.log")
    }
    
    func getRecentLogLines(count: Int = 100) -> [String] {
        guard let url = getLogFileURL(),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        let lines = content.split(separator: "\n").map(String.init)
        return Array(lines.suffix(count))
    }
    
    func createShareableLogBundle() -> URL? {
        guard let url = getLogFileURL(), FileManager.default.fileExists(atPath: url.path) else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Kingdom_Server_Logs.txt")
        try? FileManager.default.copyItem(at: url, to: tempURL)
        return tempURL
    }
    
    func presentShareSheet(from viewController: UIViewController) {
        guard let logURL = createShareableLogBundle() else { return }
        let activityVC = UIActivityViewController(activityItems: [logURL], applicationActivities: nil)
        viewController.present(activityVC, animated: true)
    }
    
    func exportDiagnosticsJSON() -> String {
        let systemVersion = UIDevice.current.systemVersion
        let model = UIDevice.current.model
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let logs = getRecentLogLines(count: 1000)
        
        let dict: [String: Any] = [
            "ios_version": systemVersion,
            "device_model": model,
            "app_version": appVersion,
            "log_lines_count": logs.count,
            "logs_preview": Array(logs.suffix(10))
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }
}

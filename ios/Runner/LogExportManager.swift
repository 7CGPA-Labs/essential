import Foundation
import UIKit

/**
 * LogExportManager
 *
 * Reads the native C++ server.log file from the app's Documents directory
 * and provides diagnostic export/sharing via UIActivityViewController.
 */
class LogExportManager {

    /// Path to the server.log file in the app's documents directory.
    static var logFilePath: String {
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        return (docs as NSString).appendingPathComponent("server.log")
    }

    /// Read the last N lines from the server.log file.
    /// - Parameter maxLines: Maximum number of lines to return (default 100).
    /// - Returns: String containing the last `maxLines` lines, or empty string if no log exists.
    static func recentLogs(maxLines: Int = 100) -> String {
        let path = logFilePath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ""
        }

        let lines = content.components(separatedBy: "\n")
        let startIndex = max(0, lines.count - maxLines)
        return lines[startIndex...].joined(separator: "\n")
    }

    /// Present a share sheet to export the server.log file.
    /// - Parameter viewController: The presenting view controller.
    static func exportLogs(from viewController: UIViewController) {
        let path = logFilePath
        let fileURL = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            let alert = UIAlertController(
                title: "No Logs",
                message: "No server.log file found.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = viewController.view
        viewController.present(activityVC, animated: true)
    }

    /// Full diagnostic report including device info and recent logs.
    static func diagnosticReport() -> String {
        let device = UIDevice.current
        var report = """
        === Kingdom AI Server Diagnostic Report ===
        Device: \(device.model) (\(device.systemName) \(device.systemVersion))
        Name: \(device.name)
        Log File: \(logFilePath)
        Log Exists: \(FileManager.default.fileExists(atPath: logFilePath))

        === Recent Logs ===

        """
        report += recentLogs(maxLines: 200)
        return report
    }
}

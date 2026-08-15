import AppIntents
import Foundation

struct ServerToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle AI Server"
    static var description = IntentDescription("Start or stop the Kingdom AI Server")
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Action")
    var action: ServerAction
    
    init() {
        self.action = .toggle
    }
    
    init(action: ServerAction) {
        self.action = action
    }
    
    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.dev.seven_cgpalabs.codingsaathi")
        let isRunning = defaults?.bool(forKey: "server_running") ?? false
        
        let newState: Bool
        switch action {
        case .start:
            newState = true
        case .stop:
            newState = false
        case .toggle:
            newState = !isRunning
        }
        
        defaults?.set(newState, forKey: "server_running")
        
        // Post notification to inform the main app
        let notificationName = CFNotificationName("dev.seven_cgpalabs.codingsaathi.server_toggle" as CFString)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, notificationName, nil, nil, true)
        
        return .result()
    }
}

enum ServerAction: String, AppEnum {
    case start = "start"
    case stop = "stop"
    case toggle = "toggle"
    
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Server Action")
    static var caseDisplayRepresentations: [ServerAction: DisplayRepresentation] = [
        .start: "Start Server",
        .stop: "Stop Server",
        .toggle: "Toggle Server"
    ]
}

struct KingdomAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ServerToggleIntent(action: .toggle),
            phrases: ["Toggle \(.applicationName)", "Start AI server", "Stop AI server"]
        )
    }
}

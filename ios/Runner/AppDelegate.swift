import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 1. Request notification permission
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("Notifications granted: \(granted)")
        }
        
        // 4. Check if server was running before
        KingdomState.shared.updateFromUserDefaults()
        
        // 5. Initialize KingdomBridge if models are available (simple check for now)
        let llmPath = ModelAssetManager.shared.getLLMPath()
        let storageDir = ModelAssetManager.shared.getModelsDirectory().path
        if FileManager.default.fileExists(atPath: llmPath) {
            _ = KingdomBridge.shared.initialize(storageDir: storageDir, llmPath: llmPath)
            if KingdomState.shared.isServerRunning {
                KingdomBridge.shared.startServer(port: KingdomState.shared.serverPort)
            }
        }
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        if KingdomBridge.shared.isInitialized {
            KingdomBridge.shared.stopServer()
            KingdomBridge.shared.destroy()
        }
    }
    
    // MARK: UISceneSession Lifecycle
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

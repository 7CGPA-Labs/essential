import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        let navController = UINavigationController(rootViewController: AppSettingsViewController())
        navController.navigationBar.prefersLargeTitles = true
        window?.rootViewController = navController
        window?.makeKeyAndVisible()
    }
}

class AppSettingsViewController: UITableViewController {
    let sections = ["Server State", "Model Management", "Diagnostics"]
    var serverSwitch = UISwitch()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kingdom AI Server"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        
        NotificationCenter.default.addObserver(self, selector: #selector(serverStateChanged), name: NSNotification.Name("KingdomServerStarted"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(serverStateChanged), name: NSNotification.Name("KingdomServerStopped"), object: nil)
        
        serverSwitch.isOn = KingdomState.shared.isServerRunning
        serverSwitch.addTarget(self, action: #selector(toggleServer(_:)), for: .valueChanged)
    }
    
    @objc func serverStateChanged() {
        serverSwitch.isOn = KingdomState.shared.isServerRunning
        tableView.reloadData()
    }
    
    @objc func toggleServer(_ sender: UISwitch) {
        if sender.isOn {
            KingdomBridge.shared.startServer(port: KingdomState.shared.serverPort)
        } else {
            KingdomBridge.shared.stopServer()
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section]
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 3 } // Switch, IP, Port
        if section == 1 { return 1 } // Download Models
        if section == 2 { return 1 } // Export Logs
        return 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.selectionStyle = .none
        
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Run Server"
                cell.accessoryView = serverSwitch
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "IP Address"
                cell.detailTextLabel?.text = KingdomState.shared.wifiIP
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Port"
                cell.detailTextLabel?.text = "\(KingdomState.shared.serverPort)"
            }
        } else if indexPath.section == 1 {
            cell.textLabel?.text = "Download Missing Models"
            cell.selectionStyle = .default
        } else if indexPath.section == 2 {
            cell.textLabel?.text = "Export Server Logs"
            cell.selectionStyle = .default
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1 && indexPath.row == 0 {
            Task {
                try? await ModelAssetManager.shared.downloadMissingModels { filename, progress in
                    print("Downloading \(filename): \(progress * 100)%")
                }
            }
        } else if indexPath.section == 2 && indexPath.row == 0 {
            LogExportManager.shared.presentShareSheet(from: self)
        }
    }
}

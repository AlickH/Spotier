import Foundation
import NetworkExtension
import Combine

class VPNManager: ObservableObject, VPNControlling {
    static let shared = VPNManager()
    
    @Published var isConnected = false
    @Published var statusText = "未连接"
    @Published var status: NEVPNStatus = .disconnected
    @Published var isReady = false
    
    var isOnDemandEnabled: Bool {
        manager?.isOnDemandEnabled == true
    }
    
    /// NE 隧道的实际连接时间
    var connectedDate: Date? {
        manager?.connection.connectedDate
    }
    
    private var manager: NETunnelProviderManager?
    private var pendingStartConfigContent: String?
    
    init() {
        loadPreferences()
        
        // 监听状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }
    
    func loadManager() {
        loadPreferences()
    }

    private func loadPreferences() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error loading VPN preferences: \(error)")
                self.statusText = "加载 VPN 配置失败: \(error.localizedDescription)"
                return
            }
            
            guard let existingManager = managers?.first else {
                self.setupVPNProfile()
                return
            }

            self.manager = existingManager
            self.updateStatusSync()
            self.isReady = true
            self.processPendingStartIfNeeded()

            let connectOnStartEnabled = UserDefaults.standard.bool(forKey: "connectOnStart")
            if existingManager.isOnDemandEnabled != connectOnStartEnabled {
                self.applyOnDemandRules(to: existingManager, enabled: connectOnStartEnabled)
                self.saveManager(existingManager) { error in
                    if let error = error {
                        print("VPNManager: Error updating On Demand rules: \(error)")
                    }
                }
            }
        }
    }
    
    private func setupVPNProfile() {
        print("VPNManager: Starting setupVPNProfile...")
        
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "Spotier VPN"
        
        let protocolConfiguration = NETunnelProviderProtocol()
        let extensionBundleID = "com.alick.spotier.SpotierNE"
        protocolConfiguration.providerBundleIdentifier = extensionBundleID
        protocolConfiguration.serverAddress = "Spotier"
        
        manager.protocolConfiguration = protocolConfiguration
        manager.isEnabled = true
        
        // Connect On Demand: 网络可用时系统自动启动 NE
        applyOnDemandRules(to: manager, enabled: UserDefaults.standard.bool(forKey: "connectOnStart"))
        
        saveManager(manager) { [weak self] error in
            if let error = error {
                print("VPNManager: Error saving VPN profile: \(error.localizedDescription)")
                self?.statusText = "创建 VPN 配置失败: \(error.localizedDescription)"
            } else {
                print("VPNManager: VPN Profile saved successfully.")
                self?.loadPreferences()
            }
        }
    }

    private func applyOnDemandRules(to manager: NETunnelProviderManager, enabled: Bool) {
        if enabled {
            let wifiRule = NEOnDemandRuleConnect()
            wifiRule.interfaceTypeMatch = .wiFi

            let ethernetRule = NEOnDemandRuleConnect()
            ethernetRule.interfaceTypeMatch = .ethernet

            manager.onDemandRules = [wifiRule, ethernetRule]
            manager.isOnDemandEnabled = true
        } else {
            manager.onDemandRules = []
            manager.isOnDemandEnabled = false
        }

        print("VPNManager: Connect On Demand \(enabled ? "enabled" : "disabled")")
    }
    
    /// 外部调用：更新 On Demand 设置（设置页切换时调用）
    func updateOnDemand(enabled: Bool) {
        guard let manager = manager else { return }
        
        manager.loadFromPreferences { [weak self, manager] error in
            guard let self else { return }
            if let error = error {
                print("VPNManager: Error loading preferences for On Demand update: \(error)")
                return
            }
            
            self.applyOnDemandRules(to: manager, enabled: enabled)
            
            self.saveManager(manager) { error in
                if let error = error {
                    print("VPNManager: Error updating On Demand: \(error)")
                } else {
                    print("VPNManager: On Demand updated to \(enabled)")
                }
            }
        }
    }
    
    private func saveManager(_ manager: NETunnelProviderManager, completion: @escaping (Error?) -> Void) {
        manager.saveToPreferences(completionHandler: completion)
    }

    func saveConfigToAppGroup(configContent: String) -> Bool {
        guard let groupURL = appGroupContainerURL() else {
            print("Failed to get App Group container")
            return false
        }
        
        let configURL = groupURL.appendingPathComponent("config.toml")
        do {
            try configContent.write(to: configURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("Failed to write config to App Group: \(error)")
            return false
        }
    }

    func startVPN(configContent: String) {
        guard let manager else {
            print("VPN Manager not ready, queue start request")
            pendingStartConfigContent = configContent
            statusText = "VPN 初始化中，已排队启动..."
            loadPreferences()
            return
        }
        performStartVPN(using: manager, configContent: configContent)
    }
    
    func stopVPN() {
        manager?.connection.stopVPNTunnel()
    }
    
    /// 手动关闭：load → 禁用 On Demand → save → stop，防止系统自动重连
    func disableOnDemandAndStop() {
        guard let manager = manager else { return }
        
        // Apple 要求 save 前先 load 最新状态
        manager.loadFromPreferences { [manager] error in
            if let error = error {
                print("VPNManager: Error loading preferences: \(error)")
                // 即使 load 失败也尝试 stop
                manager.connection.stopVPNTunnel()
                return
            }
            
            manager.isOnDemandEnabled = false
            self.saveManager(manager) { error in
                if let error = error {
                    print("VPNManager: Error disabling On Demand: \(error)")
                } else {
                    print("VPNManager: On Demand disabled, now stopping tunnel")
                }
                // save 完成后再 stop
                manager.connection.stopVPNTunnel()
            }
        }
    }
    
    /// Send a message to the running NE provider and get a response
    func sendProviderMessage(_ message: String, completion: @escaping (Data?) -> Void) {
        guard let session = manager?.connection as? NETunnelProviderSession,
              let messageData = message.data(using: .utf8) else {
            completion(nil)
            return
        }
        
        do {
            try session.sendProviderMessage(messageData) { response in
                completion(response)
            }
        } catch {
            print("sendProviderMessage failed: \(error)")
            completion(nil)
        }
    }
    
    /// Request running info JSON from NE via IPC
    func requestRunningInfo(completion: @escaping (String?) -> Void) {
        sendProviderMessage("running_info") { data in
            guard let data, let json = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            completion(json)
        }
    }
    
    @objc private func vpnStatusDidChange(_ notification: Notification) {
        updateStatusSync()
    }
    
    /// 同步更新状态，必须在主线程调用
    private func updateStatusSync() {
        guard let connection = manager?.connection else { return }
        
        status = connection.status

        let state: (Bool, String) = switch connection.status {
        case .connected:
            (true, "已连接")
        case .connecting:
            (false, "连接中...")
        case .disconnected:
            (false, "未连接")
        case .disconnecting:
            (false, "断开中...")
        case .invalid:
            (false, "无效状态")
        case .reasserting:
            (false, "重连中...")
        @unknown default:
            (false, "未知状态")
        }

        isConnected = state.0
        statusText = state.1
    }

    private func processPendingStartIfNeeded() {
        guard let manager, let pendingConfig = pendingStartConfigContent else { return }

        switch manager.connection.status {
        case .connected, .connecting, .reasserting:
            pendingStartConfigContent = nil
            return
        default:
            break
        }

        pendingStartConfigContent = nil
        performStartVPN(using: manager, configContent: pendingConfig)
    }

    private func performStartVPN(using manager: NETunnelProviderManager, configContent: String) {
        // 我们不直接通过 options 传递大文本，而是保存到 App Group
        guard saveConfigToAppGroup(configContent: configContent) else {
            statusText = "保存配置失败"
            return
        }

        let options: [String: NSObject] = [:] // Config is read from App Group file by NE

        do {
            try manager.connection.startVPNTunnel(options: options)
            print("VPN Start requested")
        } catch {
            print("Error starting VPN: \(error)")
            statusText = "启动失败: \(error.localizedDescription)"
        }
    }
}

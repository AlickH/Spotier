import NetworkExtension
import os


let debounceInterval: TimeInterval = 0.5

private struct ConfigHints {
    var ipv4: String?
    var subnet: String?
    var ipv6: String?
    var ipv6Prefix: Int?
    var mtu: Int?
    var magicDNS = false
    var magicDNSZone = "et.net"
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    // Hold a weak reference for C callback bridging
    private static weak var current: PacketTunnelProvider?

    
    private var lastAppliedSettings: SettingsSnapshot?
    private var needReapplySettings = false
    private var debounceTask: Task<Void, Never>?
    private var configHints = ConfigHints()

    private let magicDNSResolver = "100.100.100.101"
    
    // MARK: - Config Loading
    
    private func loadConfig() -> String? {
        guard let groupURL = appGroupContainerURL() else {
            logger.error("无法访问 App Group 容器: \(APP_GROUP_ID)")
            return nil
        }
        let configURL = groupURL.appendingPathComponent("config.toml")
        do {
            let content = try String(contentsOf: configURL, encoding: .utf8)
            logger.info("成功从 App Group 读取配置文件")
            return content
        } catch {
            logger.error("读取配置文件失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Parse ipv4 and mtu from TOML config for initial network settings
    private func parseConfigHints(_ toml: String) {
        var hints = ConfigHints()

        for line in toml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let val = parts[1].replacingOccurrences(of: "\"", with: "")
            
            switch key {
            case "ipv4":
                // e.g. "10.126.126.1/24"
                let cidrParts = val.split(separator: "/")
                if cidrParts.count == 2 {
                    hints.ipv4 = String(cidrParts[0])
                    if let cidr = Int(cidrParts[1]) {
                        hints.subnet = cidrToSubnetMask(cidr)
                    }
                }
            case "ipv6":
                if let parsed = parseIPv6CIDR(val) {
                    hints.ipv6 = parsed.address
                    hints.ipv6Prefix = parsed.prefixLength
                }
            case "mtu":
                hints.mtu = Int(val)
            case "enable_magic_dns", "accept_dns":
                hints.magicDNS = val.lowercased() == "true"
            case "tld_dns_zone":
                let zone = val.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !zone.isEmpty {
                    hints.magicDNSZone = zone
                }
            default:
                break
            }
        }

        configHints = hints
    }
    
    // MARK: - Running Info Callback
    
    private func registerRunningInfoCallback() {
        let callback: @convention(c) () -> Void = {
            PacketTunnelProvider.current?.handleRunningInfoChanged()
        }
        do {
            try EasyTierCore.registerRunningInfoCallback(callback)
            logger.info("已注册 running info callback")
        } catch {
            logger.error("注册 running info callback 失败: \(error)")
        }
    }
    
    private func handleRunningInfoChanged() {
        logger.info("Running info 已变化，触发网络设置更新")
        enqueueSettingsUpdate()
    }
    
    // MARK: - Stop Callback
    
    private func registerStopCallback() {
        let callback: @convention(c) () -> Void = {
            PacketTunnelProvider.current?.handleRustStop()
        }
        do {
            try EasyTierCore.registerStopCallback(callback)
            logger.info("已注册 stop callback")
        } catch {
            logger.error("注册 stop callback 失败: \(error)")
        }
    }
    
    private func handleRustStop() {
        let msg = EasyTierCore.getLatestErrorMessage() ?? ""
        logger.error("Rust Core 已停止: \(msg)")

        Task { @MainActor in
            self.cancelTunnelWithError(NSError(
                domain: "SwiftierNE", code: 2,
                userInfo: [NSLocalizedDescriptionKey: msg]
            ))
        }
    }
    
    // MARK: - Dynamic Network Settings
    
    private func enqueueSettingsUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }
            if self.reasserting {
                logger.info("设置更新已在进行中，排队等待")
                self.needReapplySettings = true
                return
            }
            self.applyNetworkSettings { error in
                if let error {
                    logger.error("设置更新失败: \(error)")
                }
            }
        }
    }
    
    private func applyNetworkSettings(_ completion: @escaping (Error?) -> Void) {
        guard !reasserting else {
            completion(NSError(domain: "SwiftierNE", code: 3, userInfo: [NSLocalizedDescriptionKey: "still in progress"]))
            return
        }
        reasserting = true
        
        needReapplySettings = false
        let settings = buildSettings()
        let newSnapshot = SettingsSnapshot(from: settings)
        
        let wrappedCompletion: (Error?) -> Void = { error in
            Task { @MainActor in
                if error == nil {
                    self.lastAppliedSettings = newSnapshot
                }
                completion(error)
                self.reasserting = false
                if self.needReapplySettings {
                    self.needReapplySettings = false
                    self.applyNetworkSettings(completion)
                }
            }
        }
        
        // Skip if settings haven't changed
        if newSnapshot == lastAppliedSettings {
            logger.info("网络设置未变化，跳过更新")
            wrappedCompletion(nil)
            return
        }
        
        let needSetTunFd = shouldUpdateTunFd(old: lastAppliedSettings, new: newSnapshot)
        logger.info("应用网络设置, needTunFd=\(needSetTunFd)")
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                wrappedCompletion(error)
                return
            }
            if let error {
                logger.error("setTunnelNetworkSettings 失败: \(error)")
                wrappedCompletion(error)
                return
            }
            
            // Pass TUN fd to Rust Core
            if needSetTunFd {
                // Prefer packetFlow fd (the correct NE-created utun)
                let packetFlowFd = self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32
                let scanFd = self.findTunnelFileDescriptor()
                let tunFd = packetFlowFd ?? scanFd
                
                logger.error("TUN fd 诊断: packetFlow=\(packetFlowFd.map { String($0) } ?? "nil", privacy: .public), scan=\(scanFd.map { String($0) } ?? "nil", privacy: .public), chosen=\(tunFd.map { String($0) } ?? "nil", privacy: .public)")
                
                if let fd = tunFd {
                    do {
                        try EasyTierCore.setTunFd(fd)
                        logger.error("TUN fd 已设置: \(fd, privacy: .public)")
                    } catch {
                        logger.error("设置 TUN fd 失败: \(error, privacy: .public)")
                        wrappedCompletion(error)
                        return
                    }
                } else {
                    logger.error("无法获取 TUN fd（packetFlow 和 scan 均失败）")
                    wrappedCompletion(NSError(
                        domain: "SwiftierNE",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "无法获取 TUN 文件描述符"]
                    ))
                    return
                }
            }
            
            logger.info("网络设置已应用")
            wrappedCompletion(nil)
        }
    }
    
    /// Build NEPacketTunnelNetworkSettings dynamically from get_running_info()
    private func buildSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let runningInfo = fetchRunningInfo()

        let runtimeIPv4 = runningInfo?.myNodeInfo?.virtualIPv4
        let ipv4Address = runtimeIPv4?.address.description ?? configHints.ipv4
        let subnetMask = runtimeIPv4
            .flatMap { cidrToSubnetMask($0.networkLength) }
            ?? configHints.subnet

        if let ipv4Address, let subnetMask {
            let ipv4Settings = NEIPv4Settings(addresses: [ipv4Address], subnetMasks: [subnetMask])
            var routes: [NEIPv4Route] = []

            if let info = runningInfo {
                for route in info.routes {
                    for cidrStr in route.proxyCIDRs {
                        if let parsed = parseCIDR(cidrStr) {
                            routes.append(NEIPv4Route(
                                destinationAddress: parsed.address,
                                subnetMask: parsed.mask
                            ))
                        }
                    }
                }

                if let nodeIp = info.myNodeInfo?.virtualIPv4 {
                    let networkAddr = maskedAddress(nodeIp.address, networkLength: nodeIp.networkLength)
                    let netMask = cidrToSubnetMask(nodeIp.networkLength)!
                    routes.append(NEIPv4Route(destinationAddress: networkAddr, subnetMask: netMask))
                }
            }

            if routes.isEmpty {
                let networkAddr = maskedAddressFromStrings(ipv4Address, mask: subnetMask)
                routes.append(NEIPv4Route(destinationAddress: networkAddr, subnetMask: subnetMask))
            }

            if configHints.magicDNS,
               !routes.contains(where: { ipv4RouteContainsAddress(destination: $0.destinationAddress, subnetMask: $0.destinationSubnetMask, address: magicDNSResolver) }) {
                routes.append(NEIPv4Route(destinationAddress: magicDNSResolver, subnetMask: "255.255.255.255"))
            }

            ipv4Settings.includedRoutes = routes
            settings.ipv4Settings = ipv4Settings
        }

        let runtimeIPv6 = runningInfo?.myNodeInfo?.virtualIPv6
        let ipv6Address = runtimeIPv6?.address.description ?? configHints.ipv6
        let ipv6PrefixLength = runtimeIPv6?.networkLength ?? configHints.ipv6Prefix

        if let ipv6Address, let prefixLength = ipv6PrefixLength {
            let ipv6Settings = NEIPv6Settings(
                addresses: [ipv6Address],
                networkPrefixLengths: [NSNumber(value: prefixLength)]
            )
            if let networkAddress = maskedIPv6Address(ipv6Address, networkLength: prefixLength) {
                ipv6Settings.includedRoutes = [
                    NEIPv6Route(
                        destinationAddress: networkAddress,
                        networkPrefixLength: NSNumber(value: prefixLength)
                    )
                ]
            }
            settings.ipv6Settings = ipv6Settings
        }

        if configHints.magicDNS {
            let dnsSettings = NEDNSSettings(servers: [magicDNSResolver])
            dnsSettings.searchDomains = [configHints.magicDNSZone]
            dnsSettings.matchDomains = [configHints.magicDNSZone]
            settings.dnsSettings = dnsSettings
        }

        settings.mtu = NSNumber(value: configHints.mtu ?? 1380)

        if settings.ipv4Settings == nil && settings.ipv6Settings == nil {
            logger.warning("无可用 IP 地址，返回空设置")
        }

        return settings
    }
    
    // MARK: - Tunnel Lifecycle
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("正在启动 VPN Tunnel...")
        PacketTunnelProvider.current = self
        
        // 1. 读取配置
        guard let configToml = loadConfig() else {
            let error = NSError(domain: "SwiftierNE", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取 VPN 配置"])
            completionHandler(error)
            return
        }
        
        // 2. 解析配置中的 IPv4 和 MTU 信息
        parseConfigHints(configToml)
        
        // 3. 初始化 Logger（从 App Group 读取用户设置的日志等级）
        let savedLevel: LogLevel = {
            if let defaults = appGroupDefaults(),
               let raw = defaults.string(forKey: "logLevel"),
               let level = LogLevel(rawValue: raw.lowercased()) {
                return level
            }
            return .info
        }()
        initRustLogger(level: savedLevel)
        
        // 4. 启动 Core（macOS cfg 已 patch，不会自动创建 TUN，通过 set_tun_fd 传入）
        do {
            try EasyTierCore.runNetworkInstance(config: configToml)
            logger.info("EasyTier Core 启动成功")
        } catch {
            logger.error("EasyTier Core 启动失败: \(error)")
            completionHandler(error)
            return
        }
        
        // 5. 注册回调
        registerStopCallback()
        registerRunningInfoCallback()
        
        // 6. 应用网络设置并传入 TUN fd
        applyNetworkSettings(completionHandler)
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("正在停止 VPN Tunnel, reason: \(reason.rawValue)")
        EasyTierCore.stopNetworkInstance()
        PacketTunnelProvider.current = nil
        completionHandler()
    }
    
    // MARK: - App IPC (handleAppMessage)
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let handler = completionHandler else { return }
        
        // Command: "running_info" -> return get_running_info JSON
        if let command = String(data: messageData, encoding: .utf8) {
            switch command {
            case "running_info":
                if let json = EasyTierCore.getRunningInfo(),
                   let data = json.data(using: .utf8) {
                    handler(data)
                } else {
                    handler(nil)
                }
            default:
                handler(nil)
            }
        } else {
            handler(nil)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func wake() {
        // Trigger a settings refresh on wake
        enqueueSettingsUpdate()
    }
    
    // MARK: - Helpers
    
    private func fetchRunningInfo() -> RunningInfo? {
        guard let json = EasyTierCore.getRunningInfo(),
              let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(RunningInfo.self, from: data)
        } catch {
            logger.error("解析 running info 失败: \(error)")
            return nil
        }
    }
    
    /// Find the utun file descriptor by scanning open FDs
    /// Delegates to the shared implementation in TunnelHelper.swift
    private func findTunnelFileDescriptor() -> Int32? {
        logger.info("尝试通过 FD 扫描查找 TUN 接口")
        return tunnelFileDescriptor()
    }
    
    private func shouldUpdateTunFd(old: SettingsSnapshot?, new: SettingsSnapshot) -> Bool {
        // 只要有 IP 地址就应该设置 TUN fd
        guard new.hasIPAddresses else {
            logger.info("shouldUpdateTunFd: new snapshot has no IP addresses")
            return false
        }
        // 每次 setTunnelNetworkSettings 成功后都应该重新设置 TUN fd，
        // 因为系统可能会重建 utun 接口，导致之前的 fd 失效。
        // 只有当设置完全相同时（会被上层 skip），才不需要更新。
        logger.info("shouldUpdateTunFd: hasIP=true, always update tun fd")
        return true
    }
}

// MARK: - Helper Models



// MARK: - Settings Snapshot (for change detection)

struct SettingsSnapshot: Equatable {
    var ipv4Addresses: [String]
    var ipv4SubnetMasks: [String]
    var ipv4Routes: [(String, String)]  // (destination, mask)
    var ipv6Addresses: [String]
    var ipv6PrefixLengths: [Int]
    var ipv6Routes: [(String, Int)]
    var dnsServers: [String]
    var dnsSearchDomains: [String]
    var dnsMatchDomains: [String]
    var mtu: Int?
    
    var hasIPAddresses: Bool {
        (!ipv4Addresses.isEmpty && ipv4Addresses.first?.isEmpty == false)
            || (!ipv6Addresses.isEmpty && ipv6Addresses.first?.isEmpty == false)
    }
    
    init(from settings: NEPacketTunnelNetworkSettings) {
        ipv4Addresses = settings.ipv4Settings?.addresses ?? []
        ipv4SubnetMasks = settings.ipv4Settings?.subnetMasks ?? []
        ipv4Routes = settings.ipv4Settings?.includedRoutes?.map {
            ($0.destinationAddress, $0.destinationSubnetMask)
        } ?? []
        ipv6Addresses = settings.ipv6Settings?.addresses ?? []
        ipv6PrefixLengths = settings.ipv6Settings?.networkPrefixLengths.map(\.intValue) ?? []
        ipv6Routes = settings.ipv6Settings?.includedRoutes?.map {
            ($0.destinationAddress, $0.destinationNetworkPrefixLength.intValue)
        } ?? []
        dnsServers = settings.dnsSettings?.servers ?? []
        dnsSearchDomains = settings.dnsSettings?.searchDomains ?? []
        dnsMatchDomains = settings.dnsSettings?.matchDomains ?? []
        mtu = settings.mtu?.intValue
    }
    
    static func == (lhs: SettingsSnapshot, rhs: SettingsSnapshot) -> Bool {
        lhs.ipv4Addresses == rhs.ipv4Addresses &&
        lhs.ipv4SubnetMasks == rhs.ipv4SubnetMasks &&
        lhs.ipv4Routes.count == rhs.ipv4Routes.count &&
        zip(lhs.ipv4Routes, rhs.ipv4Routes).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 } &&
        lhs.ipv6Addresses == rhs.ipv6Addresses &&
        lhs.ipv6PrefixLengths == rhs.ipv6PrefixLengths &&
        lhs.ipv6Routes.count == rhs.ipv6Routes.count &&
        zip(lhs.ipv6Routes, rhs.ipv6Routes).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 } &&
        lhs.dnsServers == rhs.dnsServers &&
        lhs.dnsSearchDomains == rhs.dnsSearchDomains &&
        lhs.dnsMatchDomains == rhs.dnsMatchDomains &&
        lhs.mtu == rhs.mtu
    }
}

// MARK: - Network Utility Functions

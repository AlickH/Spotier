import NetworkExtension
import os


let debounceInterval: TimeInterval = 0.5

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var lastAppliedSettings: SettingsSnapshot?
    private var needReapplySettings = false
    private var debounceTask: Task<Void, Never>?
    private var configHints = CoreConfigHints()
    private var meshEngine: MeshEngine?
    private var packetTunnelIO: PacketTunnelIO?
    private var packetReadTask: Task<Void, Never>?
    private var packetWriteTask: Task<Void, Never>?

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
        
        logger.info("应用网络设置")
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard self != nil else {
                wrappedCompletion(error)
                return
            }
            if let error {
                logger.error("setTunnelNetworkSettings 失败: \(error)")
                wrappedCompletion(error)
                return
            }

            logger.info("网络设置已应用")
            wrappedCompletion(nil)
        }
    }
    
    /// Build NEPacketTunnelNetworkSettings dynamically from the Swift core running info snapshot.
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
        
        // 1. 读取配置
        guard let configToml = loadConfig() else {
            let error = NSError(domain: "SwiftierNE", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取 VPN 配置"])
            completionHandler(error)
            return
        }
        
        // 2. 解析配置中的 IPv4 和 MTU 信息
        let parsedConfig: CoreConfigParseResult
        do {
            parsedConfig = try CoreConfigParser.parse(configToml)
            configHints = parsedConfig.hints
        } catch {
            logger.error("解析配置失败: \(error.localizedDescription)")
            completionHandler(error)
            return
        }
        
        let engine = MeshEngine()
        let packetIO = PacketTunnelIO(flow: packetFlow)
        meshEngine = engine
        packetTunnelIO = packetIO

        Task {
            do {
                try await engine.start(configuration: parsedConfig.configuration)
                startPacketIO(engine: engine, packetIO: packetIO)
                applyNetworkSettings(completionHandler)
            } catch {
                logger.error("Swift MeshEngine 启动失败: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("正在停止 VPN Tunnel, reason: \(reason.rawValue)")
        stopPacketIO()
        let engine = meshEngine
        meshEngine = nil
        packetTunnelIO = nil

        Task {
            await engine?.stop()
            completionHandler()
        }
    }
    
    // MARK: - App IPC (handleAppMessage)
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let handler = completionHandler else { return }
        
        // Command: "running_info" -> return Swift core running info JSON.
        if let command = String(data: messageData, encoding: .utf8) {
            switch command {
            case "running_info":
                handler(meshEngine?.runningInfoData())
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
        guard let data = meshEngine?.runningInfoData() else { return nil }
        do {
            return try JSONDecoder().decode(RunningInfo.self, from: data)
        } catch {
            logger.error("解析 running info 失败: \(error)")
            return nil
        }
    }
    
    private func startPacketIO(engine: MeshEngine, packetIO: PacketTunnelIO) {
        packetIO.startReading()

        packetReadTask = Task {
            for await packet in packetIO.packets {
                await engine.receivePacket(packet)
            }
        }

        packetWriteTask = Task {
            for await packet in engine.outboundPackets {
                packetIO.write(packet)
            }
        }
    }

    private func stopPacketIO() {
        packetReadTask?.cancel()
        packetWriteTask?.cancel()
        packetReadTask = nil
        packetWriteTask = nil
        packetTunnelIO?.stop()
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

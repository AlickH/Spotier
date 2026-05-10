import Foundation
import NetworkExtension
import os

public let APP_BUNDLE_ID: String = "com.alick.spotier"
public let APP_GROUP_ID: String = "group.com.alick.spotier"
public let ICLOUD_CONTAINER_ID: String = "iCloud.com.alick.spotier"
public let LOG_FILENAME: String = "easytier.log"

public func appGroupDefaults() -> UserDefaults? {
    UserDefaults(suiteName: APP_GROUP_ID)
}

public func appGroupContainerURL(fileManager: FileManager = .default) -> URL? {
    fileManager.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID)
}

public func appGroupFileURL(_ filename: String, fileManager: FileManager = .default) -> URL? {
    appGroupContainerURL(fileManager: fileManager)?.appendingPathComponent(filename)
}

public enum LogLevel: String, Codable, CaseIterable {
    case off = "off"
    case trace = "trace"
    case debug = "debug"
    case info = "info"
    case warn = "warn"
    case error = "error"
}

public enum StoredLogLevel: String, Codable, CaseIterable {
    case off = "OFF"
    case error = "ERROR"
    case warn = "WARN"
    case info = "INFO"
    case debug = "DEBUG"
    case trace = "TRACE"

    public init(storedValue: String) {
        self = StoredLogLevel(rawValue: storedValue.uppercased()) ?? .info
    }

    public var effectiveLogLevel: LogLevel {
        switch self {
        case .off: return .off
        case .error: return .error
        case .warn: return .warn
        case .info: return .info
        case .debug: return .debug
        case .trace: return .trace
        }
    }

    public func allows(_ logLevel: LogLevel) -> Bool {
        rank(of: logLevel) <= rank
    }

    private var rank: Int {
        switch self {
        case .off: return 0
        case .error: return 1
        case .warn: return 2
        case .info: return 3
        case .debug: return 4
        case .trace: return 5
        }
    }

    private func rank(of logLevel: LogLevel) -> Int {
        switch logLevel {
        case .off: return 0
        case .error: return 1
        case .warn: return 2
        case .info: return 3
        case .debug: return 4
        case .trace: return 5
        }
    }
}

public func readStoredLogLevel(defaults: UserDefaults? = appGroupDefaults()) -> StoredLogLevel {
    StoredLogLevel(storedValue: defaults?.string(forKey: "logLevel") ?? StoredLogLevel.info.rawValue)
}

public func writeStoredLogLevel(_ level: StoredLogLevel, defaults: UserDefaults? = appGroupDefaults()) {
    defaults?.set(level.rawValue, forKey: "logLevel")
}

public struct EasyTierOptions: Codable {
    public var config: String = ""
    public var ipv4: String?
    public var ipv6: String?
    public var mtu: Int?
    public var routes: [String] = []
    public var logLevel: LogLevel = .info
    public var magicDNS: Bool = false
    public var dns: [String] = []

    public init() {}
}

public struct TunnelNetworkSettingsSnapshot: Codable, Equatable {
    public struct IPv4Subnet: Codable, Hashable {
        public var address: String
        public var subnetMask: String

        public init(address: String, subnetMask: String) {
            self.address = address
            self.subnetMask = subnetMask
        }
    }

    public struct IPv6Subnet: Codable, Hashable {
        public var address: String
        public var networkPrefixLength: Int

        public init(address: String, networkPrefixLength: Int) {
            self.address = address
            self.networkPrefixLength = networkPrefixLength
        }
    }

    public struct IPv4: Codable, Equatable {
        public var subnets: Set<IPv4Subnet>
        public var includedRoutes: Set<IPv4Subnet>?
        public var excludedRoutes: Set<IPv4Subnet>?

        public init(
            addresses: [String],
            subnetMasks: [String],
            includedRoutes: [IPv4Subnet]? = nil,
            excludedRoutes: [IPv4Subnet]? = nil
        ) {
            subnets = .init()
            for (index, address) in addresses.enumerated() {
                subnets.insert(
                    IPv4Subnet(address: address, subnetMask: subnetMasks[index])
                )
            }
            if let includedRoutes, !includedRoutes.isEmpty {
                self.includedRoutes = Set(includedRoutes)
            }
            if let excludedRoutes, !excludedRoutes.isEmpty {
                self.excludedRoutes = Set(excludedRoutes)
            }
        }
    }

    public struct IPv6: Codable, Equatable {
        public var subnets: Set<IPv6Subnet>
        public var includedRoutes: Set<IPv6Subnet>?
        public var excludedRoutes: Set<IPv6Subnet>?

        public init(
            addresses: [String],
            networkPrefixLengths: [Int],
            includedRoutes: [IPv6Subnet]? = nil,
            excludedRoutes: [IPv6Subnet]? = nil
        ) {
            subnets = .init()
            for (index, address) in addresses.enumerated() {
                subnets.insert(
                    IPv6Subnet(
                        address: address,
                        networkPrefixLength: networkPrefixLengths[index]
                    )
                )
            }
            if let includedRoutes {
                self.includedRoutes = Set(includedRoutes)
            }
            if let excludedRoutes {
                self.excludedRoutes = Set(excludedRoutes)
            }
        }
    }

    public struct DNS: Codable, Equatable {
        public var servers: Set<String>
        public var searchDomains: Set<String>?
        public var matchDomains: Set<String>?

        public init(
            servers: [String],
            searchDomains: [String]? = nil,
            matchDomains: [String]? = nil
        ) {
            self.servers = Set(servers)
            if let searchDomains {
                self.searchDomains = Set(searchDomains)
            }
            if let matchDomains {
                self.matchDomains = Set(matchDomains)
            }
        }
    }

    public var ipv4: IPv4?
    public var ipv6: IPv6?
    public var dns: DNS?
    public var mtu: UInt32?

    public init(ipv4: IPv4? = nil, ipv6: IPv6? = nil, dns: DNS? = nil, mtu: UInt32? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.dns = dns
        self.mtu = mtu
    }
}

public enum ProviderCommand: String, Codable, CaseIterable {
    case exportOSLog = "export_oslog"
    case runningInfo = "running_info"
    case lastNetworkSettings = "last_network_settings"
}

public func connectWithManager(_ manager: NETunnelProviderManager, logger: Logger? = nil) async throws {
    manager.isEnabled = true
    if let defaults = appGroupDefaults() {
        manager.protocolConfiguration?.includeAllNetworks = defaults.bool(forKey: "includeAllNetworks")
        manager.protocolConfiguration?.excludeLocalNetworks = defaults.bool(forKey: "excludeLocalNetworks")
        if #available(iOS 16.4, *) {
            manager.protocolConfiguration?.excludeCellularServices = defaults.bool(forKey: "excludeCellularServices")
            manager.protocolConfiguration?.excludeAPNs = defaults.bool(forKey: "excludeAPNs")
        }
        if #available(iOS 17.4, macOS 14.4, *) {
            manager.protocolConfiguration?.excludeDeviceCommunication = defaults.bool(forKey: "excludeDeviceCommunication")
        }
        manager.protocolConfiguration?.enforceRoutes = defaults.bool(forKey: "enforceRoutes")
        if let logger {
            logger.debug("connect with protocol configuration: \(manager.protocolConfiguration)")
        }
    }
    try await manager.saveToPreferences()
    try manager.connection.startVPNTunnel()
}

import Foundation

struct MeshEngineConfiguration: Equatable {
    var networkName: String
    var networkSecret: String
    var instanceName: String?
    var virtualIPv4: String?
    var virtualIPv6: String?
    var peers: [String]
    var listeners: [String]
    var mappedListeners: [String]
    var advertisedRoutes: [String]
    var exitNodes: [String]
    var enableExitNode: Bool
    var mtu: Int
    var disableP2P: Bool
    var p2pOnly: Bool
    var disableUDPHolePunching: Bool
    var magicDNS: Bool
    var magicDNSZone: String

    init(
        networkName: String,
        networkSecret: String,
        instanceName: String? = nil,
        virtualIPv4: String? = nil,
        virtualIPv6: String? = nil,
        peers: [String] = [],
        listeners: [String] = [],
        mappedListeners: [String] = [],
        advertisedRoutes: [String] = [],
        exitNodes: [String] = [],
        enableExitNode: Bool = false,
        mtu: Int = 1380,
        disableP2P: Bool = false,
        p2pOnly: Bool = false,
        disableUDPHolePunching: Bool = false,
        magicDNS: Bool = false,
        magicDNSZone: String = "et.net"
    ) {
        self.networkName = networkName
        self.networkSecret = networkSecret
        self.instanceName = instanceName
        self.virtualIPv4 = virtualIPv4
        self.virtualIPv6 = virtualIPv6
        self.peers = peers
        self.listeners = listeners
        self.mappedListeners = mappedListeners
        self.advertisedRoutes = advertisedRoutes
        self.exitNodes = exitNodes
        self.enableExitNode = enableExitNode
        self.mtu = mtu
        self.disableP2P = disableP2P
        self.p2pOnly = p2pOnly
        self.disableUDPHolePunching = disableUDPHolePunching
        self.magicDNS = magicDNS
        self.magicDNSZone = magicDNSZone
    }

    func validate() throws {
        guard !networkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshEngineConfigurationError.emptyNetworkName
        }

        guard (576...9000).contains(mtu) else {
            throw MeshEngineConfigurationError.invalidMTU(mtu)
        }
    }
}

enum MeshEngineConfigurationError: Error, Equatable {
    case emptyNetworkName
    case invalidMTU(Int)
}

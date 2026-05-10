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
    var mtu: Int
    var disableP2P: Bool
    var disableUDPHolePunching: Bool

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
        mtu: Int = 1380,
        disableP2P: Bool = false,
        disableUDPHolePunching: Bool = false
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
        self.mtu = mtu
        self.disableP2P = disableP2P
        self.disableUDPHolePunching = disableUDPHolePunching
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

import Foundation

struct MeshEngineConfiguration: Equatable {
    var networkName: String
    var networkSecret: String
    var virtualIPv4: String?
    var virtualIPv6: String?
    var peers: [String]
    var listeners: [String]
    var mtu: Int

    init(
        networkName: String,
        networkSecret: String,
        virtualIPv4: String? = nil,
        virtualIPv6: String? = nil,
        peers: [String] = [],
        listeners: [String] = [],
        mtu: Int = 1380
    ) {
        self.networkName = networkName
        self.networkSecret = networkSecret
        self.virtualIPv4 = virtualIPv4
        self.virtualIPv6 = virtualIPv6
        self.peers = peers
        self.listeners = listeners
        self.mtu = mtu
    }

    func validate() throws {
        guard !networkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshEngineConfigurationError.emptyNetworkName
        }

        guard !networkSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshEngineConfigurationError.emptyNetworkSecret
        }

        guard (576...9000).contains(mtu) else {
            throw MeshEngineConfigurationError.invalidMTU(mtu)
        }
    }
}

enum MeshEngineConfigurationError: Error, Equatable {
    case emptyNetworkName
    case emptyNetworkSecret
    case invalidMTU(Int)
}

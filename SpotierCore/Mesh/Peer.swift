import Foundation

struct Peer: Equatable {
    var id: PeerID
    var hostname: String
    var virtualIPv4: String?
    var virtualIPv6: String?
    var publicKey: Data
    var knownEndpoints: Set<TransportEndpoint>
    var relayAvailable: Bool
    var lastSeen: Date
    var routeCost: Int
    var isStale: Bool

    init(
        id: PeerID,
        hostname: String,
        virtualIPv4: String?,
        virtualIPv6: String?,
        publicKey: Data,
        knownEndpoints: Set<TransportEndpoint>,
        relayAvailable: Bool = false,
        lastSeen: Date,
        routeCost: Int = 1,
        isStale: Bool = false
    ) {
        self.id = id
        self.hostname = hostname
        self.virtualIPv4 = virtualIPv4
        self.virtualIPv6 = virtualIPv6
        self.publicKey = publicKey
        self.knownEndpoints = knownEndpoints
        self.relayAvailable = relayAvailable
        self.lastSeen = lastSeen
        self.routeCost = routeCost
        self.isStale = isStale
    }
}

import Foundation

enum VirtualRouteKind: Equatable {
    case host
    case subnetProxy
}

struct VirtualRoute: Equatable {
    var destination: String
    var ownerPeerID: PeerID
    var nextHopPeerID: PeerID
    var cost: Int
    var updatedAt: Date
    var kind: VirtualRouteKind

    init(
        destination: String,
        ownerPeerID: PeerID,
        nextHopPeerID: PeerID,
        cost: Int,
        updatedAt: Date,
        kind: VirtualRouteKind
    ) {
        self.destination = destination
        self.ownerPeerID = ownerPeerID
        self.nextHopPeerID = nextHopPeerID
        self.cost = cost
        self.updatedAt = updatedAt
        self.kind = kind
    }
}

struct RouteUpdate: Equatable {
    var peerID: PeerID
    var ipv4Address: String?
    var ipv6Address: String?
    var nextHopPeerID: PeerID
    var cost: Int
    var proxyCIDRs: [String]

    init(
        peerID: PeerID,
        ipv4Address: String?,
        ipv6Address: String?,
        nextHopPeerID: PeerID,
        cost: Int,
        proxyCIDRs: [String]
    ) {
        self.peerID = peerID
        self.ipv4Address = ipv4Address
        self.ipv6Address = ipv6Address
        self.nextHopPeerID = nextHopPeerID
        self.cost = cost
        self.proxyCIDRs = proxyCIDRs
    }
}

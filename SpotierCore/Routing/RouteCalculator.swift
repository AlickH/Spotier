import Foundation

enum RouteCalculator {
    static func apply(peer: Peer, to routeTable: inout RouteTable, now: Date = Date()) {
        routeTable.applyDirectPeerRoute(
            peerID: peer.id,
            ipv4Address: peer.virtualIPv4,
            ipv6Address: peer.virtualIPv6,
            nextHopPeerID: peer.id,
            cost: peer.routeCost,
            now: now
        )
    }
}

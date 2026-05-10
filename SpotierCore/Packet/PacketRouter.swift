import Foundation

enum PacketRouteDecision: Equatable {
    case local
    case peer(PeerID)
    case subnetProxy(PeerID)
    case drop
}

struct PacketRouter {
    var routeTable: RouteTable
    var localIPv4: String?
    var localIPv6: String?

    init(routeTable: RouteTable, localIPv4: String? = nil, localIPv6: String? = nil) {
        self.routeTable = routeTable
        self.localIPv4 = localIPv4
        self.localIPv6 = localIPv6
    }

    func route(_ packet: IPPacket) -> PacketRouteDecision {
        let destination = packet.destinationAddress

        if destination == localIPv4 || destination.lowercased() == localIPv6?.lowercased() {
            return .local
        }

        guard let route = routeTable.bestRoute(for: destination) else {
            return .drop
        }

        switch route.kind {
        case .host:
            return .peer(route.nextHopPeerID)
        case .subnetProxy:
            return .subnetProxy(route.nextHopPeerID)
        }
    }
}

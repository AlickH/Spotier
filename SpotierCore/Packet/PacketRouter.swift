import Foundation

enum PacketRouteDecision: Equatable {
    case local
    case peer(PeerID)
    case subnetProxy(PeerID)
    case exitNode(PeerID)
    case drop
}

struct PacketRouter {
    var routeTable: RouteTable
    var localIPv4: String?
    var localIPv6: String?
    var exitNodes: [String]
    var p2pOnly: Bool

    init(
        routeTable: RouteTable,
        localIPv4: String? = nil,
        localIPv6: String? = nil,
        exitNodes: [String] = [],
        p2pOnly: Bool = false
    ) {
        self.routeTable = routeTable
        self.localIPv4 = localIPv4
        self.localIPv6 = localIPv6
        self.exitNodes = exitNodes
        self.p2pOnly = p2pOnly
    }

    func route(_ packet: IPPacket) -> PacketRouteDecision {
        let destination = packet.destinationAddress

        if destination == addressPart(localIPv4) || destination.lowercased() == addressPart(localIPv6)?.lowercased() {
            return .local
        }

        guard let route = routeTable.bestRoute(for: destination) else {
            if isSameIPv4Network(destination, localCIDR: localIPv4) {
                return .drop
            }
            if p2pOnly {
                return .drop
            }
            return exitNodeRoute() ?? .drop
        }

        switch route.kind {
        case .host:
            return .peer(route.nextHopPeerID)
        case .subnetProxy:
            return .subnetProxy(route.nextHopPeerID)
        }
    }

    private func exitNodeRoute() -> PacketRouteDecision? {
        for address in exitNodes {
            if let route = routeTable.bestRoute(for: address), route.kind == .host {
                return .exitNode(route.nextHopPeerID)
            }
        }
        return nil
    }

    private func isSameIPv4Network(_ address: String, localCIDR: String?) -> Bool {
        guard let localCIDR else { return false }
        let parts = localCIDR.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              (0...32).contains(prefix),
              let localValue = parseIPv4(parts[0]),
              let addressValue = parseIPv4(address) else {
            return false
        }

        let mask = prefix == 0 ? UInt32(0) : UInt32.max << (32 - prefix)
        return (localValue & mask) == (addressValue & mask)
    }

    private func parseIPv4(_ address: String) -> UInt32? {
        let bytes = address.split(separator: ".").compactMap { UInt8($0) }
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func addressPart(_ cidrOrAddress: String?) -> String? {
        cidrOrAddress?.split(separator: "/", maxSplits: 1).first.map(String.init)
    }
}

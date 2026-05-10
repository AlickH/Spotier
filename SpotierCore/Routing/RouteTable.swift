import Foundation

struct RouteTable: Equatable {
    private(set) var routes: [VirtualRoute] = []

    mutating func apply(_ update: RouteUpdate, now: Date = Date()) {
        removeRoutes(ownedBy: update.peerID)

        if let ipv4Address = update.ipv4Address {
            routes.append(VirtualRoute(
                destination: hostDestination(from: ipv4Address, defaultPrefix: 32),
                ownerPeerID: update.peerID,
                nextHopPeerID: update.nextHopPeerID,
                cost: update.cost,
                updatedAt: now,
                kind: .host
            ))
        }

        if let ipv6Address = update.ipv6Address {
            routes.append(VirtualRoute(
                destination: hostDestination(from: ipv6Address, defaultPrefix: 128),
                ownerPeerID: update.peerID,
                nextHopPeerID: update.nextHopPeerID,
                cost: update.cost,
                updatedAt: now,
                kind: .host
            ))
        }

        for cidr in update.proxyCIDRs {
            routes.append(VirtualRoute(
                destination: cidr,
                ownerPeerID: update.peerID,
                nextHopPeerID: update.nextHopPeerID,
                cost: update.cost,
                updatedAt: now,
                kind: .subnetProxy
            ))
        }
    }

    mutating func removeRoutes(ownedBy peerID: PeerID) {
        routes.removeAll { $0.ownerPeerID == peerID }
    }

    func bestRoute(for address: String) -> VirtualRoute? {
        routes
            .filter { routeContains($0.destination, address: address) }
            .sorted { lhs, rhs in
                if lhs.cost != rhs.cost {
                    return lhs.cost < rhs.cost
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first
    }

    private func hostDestination(from address: String, defaultPrefix: Int) -> String {
        if address.contains("/") {
            return address
        }
        return "\(address)/\(defaultPrefix)"
    }

    private func routeContains(_ destination: String, address: String) -> Bool {
        let parts = destination.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let prefix = Int(parts[1]) else {
            return destination == address
        }

        if destination.contains(":") || address.contains(":") {
            return ipv6Contains(network: parts[0], prefix: prefix, address: address)
        }
        return ipv4Contains(network: parts[0], prefix: prefix, address: address)
    }

    private func ipv4Contains(network: String, prefix: Int, address: String) -> Bool {
        guard (0...32).contains(prefix),
              let networkValue = parseIPv4(network),
              let addressValue = parseIPv4(address) else {
            return false
        }

        let mask = prefix == 0 ? UInt32(0) : UInt32.max << (32 - prefix)
        return (networkValue & mask) == (addressValue & mask)
    }

    private func ipv6Contains(network: String, prefix: Int, address: String) -> Bool {
        guard prefix == 128 else {
            return false
        }
        return network.lowercased() == address.lowercased()
    }

    private func parseIPv4(_ address: String) -> UInt32? {
        let bytes = address.split(separator: ".").compactMap { UInt8($0) }
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

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

    mutating func applyDirectPeerRoute(
        peerID: PeerID,
        ipv4Address: String?,
        ipv6Address: String?,
        nextHopPeerID: PeerID,
        cost: Int,
        now: Date = Date()
    ) {
        routes.removeAll { $0.ownerPeerID == peerID && $0.kind == .host }

        if let ipv4Address {
            routes.append(VirtualRoute(
                destination: hostDestination(from: ipv4Address, defaultPrefix: 32),
                ownerPeerID: peerID,
                nextHopPeerID: nextHopPeerID,
                cost: cost,
                updatedAt: now,
                kind: .host
            ))
        }

        if let ipv6Address {
            routes.append(VirtualRoute(
                destination: hostDestination(from: ipv6Address, defaultPrefix: 128),
                ownerPeerID: peerID,
                nextHopPeerID: nextHopPeerID,
                cost: cost,
                updatedAt: now,
                kind: .host
            ))
        }
    }

    func bestRoute(for address: String) -> VirtualRoute? {
        routes
            .filter { routeContains($0.destination, address: address) }
            .sorted { lhs, rhs in
                let lhsPrefix = routePrefixLength(lhs.destination) ?? 0
                let rhsPrefix = routePrefixLength(rhs.destination) ?? 0
                if lhsPrefix != rhsPrefix {
                    return lhsPrefix > rhsPrefix
                }
                if lhs.cost != rhs.cost {
                    return lhs.cost < rhs.cost
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first
    }

    private func routePrefixLength(_ destination: String) -> Int? {
        let parts = destination.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return Int(parts[1])
    }

    private func hostDestination(from address: String, defaultPrefix: Int) -> String {
        let host = address.split(separator: "/", maxSplits: 1).first.map(String.init) ?? address
        return "\(host)/\(defaultPrefix)"
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
        guard (0...128).contains(prefix),
              let networkBytes = parseIPv6(network),
              let addressBytes = parseIPv6(address) else {
            return false
        }

        let fullBytes = prefix / 8
        let remainingBits = prefix % 8

        if fullBytes > 0, networkBytes[0..<fullBytes] != addressBytes[0..<fullBytes] {
            return false
        }

        guard remainingBits > 0 else { return true }

        let mask = UInt8.max << (8 - remainingBits)
        return (networkBytes[fullBytes] & mask) == (addressBytes[fullBytes] & mask)
    }

    private func parseIPv4(_ address: String) -> UInt32? {
        let bytes = address.split(separator: ".").compactMap { UInt8($0) }
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func parseIPv6(_ address: String) -> [UInt8]? {
        var storage = in6_addr()
        let result = address.withCString {
            inet_pton(AF_INET6, $0, &storage)
        }
        guard result == 1 else { return nil }
        return withUnsafeBytes(of: storage) { Array($0) }
    }
}

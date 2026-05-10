import Foundation

enum PacketRouteDecision: Equatable {
    case local
    case peer(PeerID)
    case peers([PeerID])
    case subnetProxy(PeerID)
    case exitNode(PeerID)
    case drop
}

struct PacketRouter {
    var routeTable: RouteTable
    var localPeerID: PeerID?
    var localIPv4: String?
    var localIPv6: String?
    var exitNodes: [String]
    var p2pOnly: Bool

    init(
        routeTable: RouteTable,
        localPeerID: PeerID? = nil,
        localIPv4: String? = nil,
        localIPv6: String? = nil,
        exitNodes: [String] = [],
        p2pOnly: Bool = false
    ) {
        self.routeTable = routeTable
        self.localPeerID = localPeerID
        self.localIPv4 = localIPv4
        self.localIPv6 = localIPv6
        self.exitNodes = exitNodes
        self.p2pOnly = p2pOnly
    }

    func route(_ packet: IPPacket) -> PacketRouteDecision {
        if shouldDropIPv6LinkLocalSource(packet) {
            return .drop
        }

        let destination = packet.destinationAddress

        if let peerIDs = multicastOrBroadcastPeers(for: packet) {
            return peerIDs.isEmpty ? .drop : .peers(peerIDs)
        }

        if destination == addressPart(localIPv4) || destination.lowercased() == addressPart(localIPv6)?.lowercased() {
            return .local
        }

        guard let route = routeTable.bestRoute(for: destination) else {
            if isSameIPv4Network(destination, localCIDR: localIPv4) {
                return .drop
            }
            if isSameIPv6Network(destination, localCIDR: localIPv6) {
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

    private func multicastOrBroadcastPeers(for packet: IPPacket) -> [PeerID]? {
        switch packet {
        case .ipv4(let ipv4):
            guard isIPv4Multicast(ipv4.destinationAddress)
                || isIPv4Broadcast(ipv4.destinationAddress)
                || isSameIPv4NetworkBroadcast(ipv4.destinationAddress) else {
                return nil
            }
            return knownPeerIDs().filter { $0 != localPeerID }
        case .ipv6(let ipv6):
            guard isIPv6Multicast(ipv6.destinationAddress)
                || isSameIPv6NetworkBroadcast(ipv6.destinationAddress) else {
                return nil
            }
            return knownPeerIDs()
        }
    }

    private func knownPeerIDs() -> [PeerID] {
        Array(Set(routeTable.routes.map(\.nextHopPeerID))).sorted { $0.rawValue < $1.rawValue }
    }

    private func shouldDropIPv6LinkLocalSource(_ packet: IPPacket) -> Bool {
        guard case .ipv6(let ipv6) = packet,
              isIPv6LinkLocal(ipv6.sourceAddress) else {
            return false
        }
        return ipv6.sourceAddress.lowercased() != addressPart(localIPv6)?.lowercased()
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

    private func isSameIPv6Network(_ address: String, localCIDR: String?) -> Bool {
        guard let localCIDR else { return false }
        let parts = localCIDR.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              (0...128).contains(prefix),
              let localBytes = parseIPv6(parts[0]),
              let addressBytes = parseIPv6(address) else {
            return false
        }

        let fullBytes = prefix / 8
        let remainingBits = prefix % 8
        if fullBytes > 0, localBytes[0..<fullBytes] != addressBytes[0..<fullBytes] {
            return false
        }
        guard remainingBits > 0 else { return true }

        let mask = UInt8.max << (8 - remainingBits)
        return (localBytes[fullBytes] & mask) == (addressBytes[fullBytes] & mask)
    }

    private func isSameIPv4NetworkBroadcast(_ address: String) -> Bool {
        guard let localIPv4 else { return false }
        let parts = localIPv4.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              (0...32).contains(prefix),
              let localValue = parseIPv4(parts[0]),
              let addressValue = parseIPv4(address) else {
            return false
        }

        let mask = prefix == 0 ? UInt32(0) : UInt32.max << (32 - prefix)
        return addressValue == (localValue | ~mask)
    }

    private func isSameIPv6NetworkBroadcast(_ address: String) -> Bool {
        guard let localIPv6 else { return false }
        let parts = localIPv6.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              (0...128).contains(prefix),
              let localBytes = parseIPv6(parts[0]),
              let addressBytes = parseIPv6(address) else {
            return false
        }

        let fullBytes = prefix / 8
        let remainingBits = prefix % 8
        if fullBytes > 0, localBytes[0..<fullBytes] != addressBytes[0..<fullBytes] {
            return false
        }
        if remainingBits > 0 {
            let networkMask = UInt8.max << (8 - remainingBits)
            guard (localBytes[fullBytes] & networkMask) == (addressBytes[fullBytes] & networkMask) else {
                return false
            }
            let hostMask = UInt8.max >> remainingBits
            guard (addressBytes[fullBytes] & hostMask) == hostMask else { return false }
        }

        let hostBitsStart = remainingBits == 0 ? fullBytes : fullBytes + 1
        guard hostBitsStart < addressBytes.count else { return true }
        return addressBytes[hostBitsStart...].allSatisfy { $0 == UInt8.max }
    }

    private func isIPv4Broadcast(_ address: String) -> Bool {
        address == "255.255.255.255"
    }

    private func isIPv4Multicast(_ address: String) -> Bool {
        guard let value = parseIPv4(address) else { return false }
        return (0xE0000000...0xEFFFFFFF).contains(value)
    }

    private func isIPv6LinkLocal(_ address: String) -> Bool {
        guard let bytes = parseIPv6(address) else { return false }
        return bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80
    }

    private func isIPv6Multicast(_ address: String) -> Bool {
        guard let bytes = parseIPv6(address) else { return false }
        return bytes[0] == 0xFF
    }

    private func parseIPv4(_ address: String) -> UInt32? {
        let bytes = address.split(separator: ".").compactMap { UInt8($0) }
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func parseIPv6(_ address: String) -> [UInt8]? {
        var storage = in6_addr()
        let result = address.withCString { inet_pton(AF_INET6, $0, &storage) }
        guard result == 1 else { return nil }
        return withUnsafeBytes(of: storage) { Array($0) }
    }

    private func addressPart(_ cidrOrAddress: String?) -> String? {
        cidrOrAddress?.split(separator: "/", maxSplits: 1).first.map(String.init)
    }
}

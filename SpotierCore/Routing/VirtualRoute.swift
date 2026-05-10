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

extension RouteUpdate {
    init(wireData: Data, sender: PeerID) throws {
        var cursor = RouteUpdateCursor(wireData)
        let ipv4Address = try cursor.readOptionalString()
        let ipv6Address = try cursor.readOptionalString()
        let cost = Int(try cursor.readUInt8())
        let proxyCount = Int(try cursor.readUInt8())
        var proxyCIDRs: [String] = []
        for _ in 0..<proxyCount {
            proxyCIDRs.append(try cursor.readString())
        }
        guard cursor.isAtEnd else {
            throw FrameCodecError.malformedPayload
        }

        self.init(
            peerID: sender,
            ipv4Address: ipv4Address,
            ipv6Address: ipv6Address,
            nextHopPeerID: sender,
            cost: cost,
            proxyCIDRs: proxyCIDRs
        )
    }
}

private struct RouteUpdateCursor {
    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else {
            throw FrameCodecError.truncatedFrame
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readString() throws -> String {
        let length = Int(try readUInt16())
        guard offset + length <= data.count else {
            throw FrameCodecError.truncatedFrame
        }
        let bytes = data.subdata(in: offset..<(offset + length))
        offset += length
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw FrameCodecError.malformedPayload
        }
        return value
    }

    mutating func readOptionalString() throws -> String? {
        switch try readUInt8() {
        case 0:
            return nil
        case 1:
            return try readString()
        default:
            throw FrameCodecError.malformedPayload
        }
    }

    private mutating func readUInt16() throws -> UInt16 {
        let high = UInt16(try readUInt8())
        let low = UInt16(try readUInt8())
        return (high << 8) | low
    }
}

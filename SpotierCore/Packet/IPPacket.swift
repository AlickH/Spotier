import Foundation

enum IPPacket: Equatable {
    case ipv4(IPv4Packet)
    case ipv6(IPv6Packet)

    var destinationAddress: String {
        switch self {
        case .ipv4(let packet):
            return packet.destinationAddress
        case .ipv6(let packet):
            return packet.destinationAddress
        }
    }
}

struct IPv4Packet: Equatable {
    var sourceAddress: String
    var destinationAddress: String
    var protocolNumber: UInt8
    var payloadLength: Int
}

struct IPv6Packet: Equatable {
    var sourceAddress: String
    var destinationAddress: String
    var nextHeader: UInt8
    var payloadLength: Int
}

enum IPPacketError: Error, Equatable {
    case nonIPPacket
    case truncatedPacket
    case malformedPacket
}

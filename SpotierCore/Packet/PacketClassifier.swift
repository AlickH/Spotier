import Foundation

enum PacketClassifier {
    static func parse(_ data: Data) throws -> IPPacket {
        guard let firstByte = data.first else {
            throw IPPacketError.truncatedPacket
        }

        switch firstByte >> 4 {
        case 4:
            return .ipv4(try parseIPv4(data))
        case 6:
            return .ipv6(try parseIPv6(data))
        default:
            throw IPPacketError.nonIPPacket
        }
    }

    private static func parseIPv4(_ data: Data) throws -> IPv4Packet {
        guard data.count >= 20 else {
            throw IPPacketError.truncatedPacket
        }

        let headerLength = Int(data[0] & 0x0F) * 4
        guard headerLength >= 20, data.count >= headerLength else {
            throw IPPacketError.malformedPacket
        }

        let totalLength = Int(data.readUInt16(at: 2))
        guard totalLength >= headerLength, data.count >= totalLength else {
            throw IPPacketError.truncatedPacket
        }

        return IPv4Packet(
            sourceAddress: data.ipv4String(at: 12),
            destinationAddress: data.ipv4String(at: 16),
            protocolNumber: data[9],
            payloadLength: totalLength - headerLength
        )
    }

    private static func parseIPv6(_ data: Data) throws -> IPv6Packet {
        guard data.count >= 40 else {
            throw IPPacketError.truncatedPacket
        }

        let payloadLength = Int(data.readUInt16(at: 4))
        guard data.count >= 40 + payloadLength else {
            throw IPPacketError.truncatedPacket
        }

        return IPv6Packet(
            sourceAddress: data.ipv6String(at: 8),
            destinationAddress: data.ipv6String(at: 24),
            nextHeader: data[6],
            payloadLength: payloadLength
        )
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func ipv4String(at offset: Int) -> String {
        "\(self[offset]).\(self[offset + 1]).\(self[offset + 2]).\(self[offset + 3])"
    }

    func ipv6String(at offset: Int) -> String {
        var groups: [String] = []
        for index in stride(from: offset, to: offset + 16, by: 2) {
            let value = (UInt16(self[index]) << 8) | UInt16(self[index + 1])
            groups.append(String(value, radix: 16))
        }
        return groups.joined(separator: ":")
    }
}

import Foundation

struct MagicDNSResponder {
    var resolverIPv4: String
    var zone: String
    var records: [String: String]

    static func records(localIdentity: NodeIdentity?, peerStore: PeerStore) -> [String: String] {
        var records: [String: String] = [:]
        if let localIdentity,
           let address = ipv4Address(from: localIdentity.virtualIPv4),
           isValidRecordHostname(localIdentity.hostname) {
            records[localIdentity.hostname.lowercased()] = address
        }
        for peer in peerStore.peers {
            if let address = ipv4Address(from: peer.virtualIPv4),
               isValidRecordHostname(peer.hostname) {
                records[peer.hostname.lowercased()] = address
            }
        }
        return records
    }

    func response(to packet: Data) -> Data? {
        guard packet.count >= 28,
              packet[0] >> 4 == 4,
              packet[9] == 17,
              packet.ipv4String(at: 16) == resolverIPv4 else {
            return nil
        }

        let headerLength = Int(packet[0] & 0x0F) * 4
        guard headerLength >= 20, packet.count >= headerLength + 8 else {
            return nil
        }
        let sourcePort = packet.readUInt16(at: headerLength)
        let destinationPort = packet.readUInt16(at: headerLength + 2)
        guard destinationPort == 53 else { return nil }

        let dnsOffset = headerLength + 8
        guard let query = DNSQuery(packet: packet, offset: dnsOffset),
              query.classCode == 1 else {
            return nil
        }

        let dnsPayload: Data
        if query.type == 1, let hostname = hostnameInZone(query.name), let address = records[hostname] {
            dnsPayload = dnsSuccessPayload(query: query, address: address)
        } else if query.type == 1, hostnameInZone(query.name) != nil {
            dnsPayload = dnsNXDomainPayload(query: query)
        } else if query.type == 6, isZoneName(query.name) {
            dnsPayload = dnsSOAPayload(query: query)
        } else {
            return nil
        }
        var udpPayload = Data()
        udpPayload.appendUInt16(53)
        udpPayload.appendUInt16(sourcePort)
        udpPayload.appendUInt16(UInt16(8 + dnsPayload.count))
        udpPayload.appendUInt16(0)
        udpPayload.append(dnsPayload)
        return ipv4Packet(
            source: resolverIPv4,
            destination: packet.ipv4String(at: 12),
            protocolNumber: 17,
            payload: udpPayload
        )
    }

    private func hostnameInZone(_ name: String) -> String? {
        let lowercased = name.lowercased()
        let suffix = ".\(zone.lowercased())"
        guard lowercased.hasSuffix(suffix) else { return nil }
        return String(lowercased.dropLast(suffix.count))
    }

    private func isZoneName(_ name: String) -> Bool {
        name.lowercased() == zone.lowercased()
    }

    private func dnsSuccessPayload(query: DNSQuery, address: String) -> Data {
        var data = Data()
        data.appendUInt16(query.id)
        data.appendUInt16(0x8180)
        data.appendUInt16(1)
        data.appendUInt16(1)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.append(query.question)
        data.appendUInt16(0xC00C)
        data.appendUInt16(1)
        data.appendUInt16(1)
        data.appendUInt32(1)
        data.appendUInt16(4)
        data.append(contentsOf: address.split(separator: ".").compactMap { UInt8($0) })
        return data
    }

    private func dnsNXDomainPayload(query: DNSQuery) -> Data {
        var data = Data()
        data.appendUInt16(query.id)
        data.appendUInt16(0x8183)
        data.appendUInt16(1)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.append(query.question)
        return data
    }

    private func dnsSOAPayload(query: DNSQuery) -> Data {
        var data = Data()
        data.appendUInt16(query.id)
        data.appendUInt16(0x8180)
        data.appendUInt16(1)
        data.appendUInt16(1)
        data.appendUInt16(0)
        data.appendUInt16(0)
        data.append(query.question)
        data.appendUInt16(0xC00C)
        data.appendUInt16(6)
        data.appendUInt16(1)
        data.appendUInt32(60)
        let rdata = soaRData()
        data.appendUInt16(UInt16(rdata.count))
        data.append(rdata)
        return data
    }

    private func soaRData() -> Data {
        var data = Data()
        data.appendDNSName("ns.\(zone)")
        data.appendDNSName("hostmaster.\(zone)")
        data.appendUInt32(2023101001)
        data.appendUInt32(7200)
        data.appendUInt32(3600)
        data.appendUInt32(1209600)
        data.appendUInt32(86400)
        return data
    }

    private func ipv4Packet(source: String, destination: String, protocolNumber: UInt8, payload: Data) -> Data {
        let sourceBytes = ipv4Bytes(source)
        let destinationBytes = ipv4Bytes(destination)
        let totalLength = UInt16(20 + payload.count)
        var data = Data([
            0x45, 0x00,
            UInt8(totalLength >> 8), UInt8(totalLength & 0xFF),
            0x00, 0x00, 0x00, 0x00,
            64, protocolNumber,
            0x00, 0x00
        ])
        data.append(contentsOf: sourceBytes)
        data.append(contentsOf: destinationBytes)
        let checksum = ipv4HeaderChecksum(data)
        data[10] = UInt8(checksum >> 8)
        data[11] = UInt8(checksum & 0xFF)
        data.append(payload)
        return data
    }

    private func ipv4HeaderChecksum(_ header: Data) -> UInt16 {
        var sum: UInt32 = 0
        for offset in stride(from: 0, to: 20, by: 2) {
            sum += UInt32(header.readUInt16(at: offset))
        }
        while sum > 0xFFFF {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return UInt16(~sum & 0xFFFF)
    }

    private func ipv4Bytes(_ address: String) -> [UInt8] {
        address.split(separator: ".").compactMap { UInt8($0) }
    }

    private static func ipv4Address(from cidr: String?) -> String? {
        cidr?.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    private static func isValidRecordHostname(_ hostname: String) -> Bool {
        !hostname.isEmpty
            && !hostname.hasPrefix(".")
            && !hostname.hasSuffix(".")
            && !hostname.contains("..")
    }
}

private struct DNSQuery {
    var id: UInt16
    var name: String
    var type: UInt16
    var classCode: UInt16
    var question: Data

    init?(packet: Data, offset: Int) {
        guard packet.count >= offset + 12,
              packet.readUInt16(at: offset + 4) == 1 else {
            return nil
        }

        id = packet.readUInt16(at: offset)
        var labels: [String] = []
        var cursor = offset + 12
        while cursor < packet.count {
            let length = Int(packet[cursor])
            cursor += 1
            if length == 0 { break }
            guard length <= 63, cursor + length <= packet.count else {
                return nil
            }
            labels.append(String(decoding: packet[cursor..<cursor + length], as: UTF8.self))
            cursor += length
        }
        guard cursor + 4 <= packet.count else { return nil }

        name = labels.joined(separator: ".")
        type = packet.readUInt16(at: cursor)
        classCode = packet.readUInt16(at: cursor + 2)
        question = packet.subdata(in: offset + 12..<cursor + 4)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendDNSName(_ name: String) {
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            append(UInt8(bytes.count))
            append(contentsOf: bytes)
        }
        append(0)
    }

    func readUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func ipv4String(at offset: Int) -> String {
        "\(self[offset]).\(self[offset + 1]).\(self[offset + 2]).\(self[offset + 3])"
    }
}

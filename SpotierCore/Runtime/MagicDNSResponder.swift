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
        guard packet.count >= 20,
              packet[0] >> 4 == 4,
              packet.ipv4String(at: 16) == resolverIPv4 else {
            return nil
        }

        let headerLength = Int(packet[0] & 0x0F) * 4
        guard headerLength >= 20, packet.count >= headerLength else {
            return nil
        }

        if packet[9] == 17 {
            return dnsResponse(to: packet, headerLength: headerLength)
        }
        if packet[9] == 1 {
            return icmpEchoResponse(to: packet, headerLength: headerLength)
        }
        return nil
    }

    private func dnsResponse(to packet: Data, headerLength: Int) -> Data? {
        guard packet.count >= headerLength + 8 else { return nil }

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
        let responseSource = resolverIPv4
        let responseDestination = packet.ipv4String(at: 12)
        let udpChecksum = udpIPv4Checksum(
            udpPayload: udpPayload,
            source: responseSource,
            destination: responseDestination
        )
        udpPayload[6] = UInt8(udpChecksum >> 8)
        udpPayload[7] = UInt8(udpChecksum & 0xFF)
        return ipv4Packet(
            request: packet,
            headerLength: headerLength,
            source: responseSource,
            destination: responseDestination,
            protocolNumber: 17,
            payload: udpPayload
        )
    }

    private func icmpEchoResponse(to packet: Data, headerLength: Int) -> Data? {
        guard packet.count >= headerLength + 8,
              packet[headerLength] == 8,
              packet[headerLength + 1] == 0 else {
            return nil
        }

        var icmpPayload = packet.subdata(in: headerLength..<packet.count)
        icmpPayload[0] = 0
        icmpPayload[2] = 0
        icmpPayload[3] = 0
        let checksum = internetChecksum(icmpPayload)
        icmpPayload[2] = UInt8(checksum >> 8)
        icmpPayload[3] = UInt8(checksum & 0xFF)
        return ipv4Packet(
            request: packet,
            headerLength: headerLength,
            source: resolverIPv4,
            destination: packet.ipv4String(at: 12),
            protocolNumber: 1,
            payload: icmpPayload
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

    private func ipv4Packet(
        request: Data,
        headerLength: Int,
        source: String,
        destination: String,
        protocolNumber: UInt8,
        payload: Data
    ) -> Data {
        let sourceBytes = ipv4Bytes(source)
        let destinationBytes = ipv4Bytes(destination)
        let totalLength = UInt16(headerLength + payload.count)
        var data = request.subdata(in: 0..<headerLength)
        data[2] = UInt8(totalLength >> 8)
        data[3] = UInt8(totalLength & 0xFF)
        data[9] = protocolNumber
        data[10] = 0
        data[11] = 0
        data.replaceSubrange(12..<16, with: sourceBytes)
        data.replaceSubrange(16..<20, with: destinationBytes)
        let checksum = ipv4HeaderChecksum(data)
        data[10] = UInt8(checksum >> 8)
        data[11] = UInt8(checksum & 0xFF)
        data.append(payload)
        return data
    }

    private func ipv4HeaderChecksum(_ header: Data) -> UInt16 {
        internetChecksum(header)
    }

    private func internetChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var offset = 0
        while offset + 1 < data.count {
            sum += UInt32(data.readUInt16(at: offset))
            offset += 2
        }
        if offset < data.count {
            sum += UInt32(data[offset]) << 8
        }
        while sum > 0xFFFF {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return UInt16(~sum & 0xFFFF)
    }

    private func udpIPv4Checksum(udpPayload: Data, source: String, destination: String) -> UInt16 {
        var data = Data()
        data.append(contentsOf: ipv4Bytes(source))
        data.append(contentsOf: ipv4Bytes(destination))
        data.append(0)
        data.append(17)
        data.appendUInt16(UInt16(udpPayload.count))
        data.append(udpPayload)
        return internetChecksum(data)
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

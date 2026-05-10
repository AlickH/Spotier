import Foundation
import XCTest
@testable import Spotier

final class MagicDNSResponderTests: XCTestCase {
    func testRespondsWithPeerIPv4ForHostnameInZone() throws {
        var store = PeerStore()
        store.upsert(Peer(
            id: PeerID(2),
            hostname: "peer",
            virtualIPv4: "10.0.0.2/24",
            virtualIPv6: nil,
            publicKey: Data(),
            knownEndpoints: [],
            lastSeen: Date()
        ))
        let responder = MagicDNSResponder(
            resolverIPv4: "100.100.100.101",
            zone: "et.net",
            records: MagicDNSResponder.records(localIdentity: nil, peerStore: store)
        )

        let response = try XCTUnwrap(responder.response(to: dnsQueryPacket(name: "peer.et.net", sourcePort: 53001)))

        XCTAssertEqual(response[12..<16].map(Int.init), [100, 100, 100, 101])
        XCTAssertEqual(response[16..<20].map(Int.init), [10, 0, 0, 9])
        XCTAssertEqual(ipv4HeaderChecksum(response), 0)
        XCTAssertEqual(response[20], 0)
        XCTAssertEqual(response[21], 53)
        XCTAssertEqual(response[22], 207)
        XCTAssertEqual(response[23], 9)
        let answerOffset = 28 + 12 + dnsQuestionLength(name: "peer.et.net")
        XCTAssertEqual(response.readUInt32(at: answerOffset + 6), 1)
        XCTAssertEqual(response.suffix(4).map(Int.init), [10, 0, 0, 2])
    }

    func testIgnoresNamesOutsideConfiguredZone() {
        let responder = MagicDNSResponder(
            resolverIPv4: "100.100.100.101",
            zone: "et.net",
            records: ["peer.et.net": "10.0.0.2"]
        )

        XCTAssertNil(responder.response(to: dnsQueryPacket(name: "peer.example.com", sourcePort: 53001)))
    }

    func testReturnsNXDomainForUnknownHostnameInConfiguredZone() throws {
        let responder = MagicDNSResponder(
            resolverIPv4: "100.100.100.101",
            zone: "et.net",
            records: ["peer": "10.0.0.2"]
        )

        let response = try XCTUnwrap(responder.response(to: dnsQueryPacket(name: "missing.et.net", sourcePort: 53001)))

        XCTAssertEqual(response[20], 0)
        XCTAssertEqual(response[21], 53)
        XCTAssertEqual(response[22], 207)
        XCTAssertEqual(response[23], 9)
        XCTAssertEqual(response.readUInt16(at: 30), 0x8183)
        XCTAssertEqual(response.readUInt16(at: 32), 1)
        XCTAssertEqual(response.readUInt16(at: 34), 0)
    }

    func testRespondsWithSOAForConfiguredZone() throws {
        let responder = MagicDNSResponder(
            resolverIPv4: "100.100.100.101",
            zone: "et.net",
            records: ["peer": "10.0.0.2"]
        )

        let response = try XCTUnwrap(responder.response(to: dnsQueryPacket(name: "et.net", sourcePort: 53001, queryType: 6)))

        XCTAssertEqual(response.readUInt16(at: 30), 0x8180)
        XCTAssertEqual(response.readUInt16(at: 32), 1)
        XCTAssertEqual(response.readUInt16(at: 34), 1)
        XCTAssertEqual(response.readUInt16(at: 48), 6)
        XCTAssertEqual(response.readUInt16(at: 50), 1)
    }

    private func dnsQueryPacket(name: String, sourcePort: UInt16, queryType: UInt16 = 1) -> Data {
        let dnsPayload = dnsQueryPayload(name: name, queryType: queryType)
        var udp = Data()
        udp.appendUInt16(sourcePort)
        udp.appendUInt16(53)
        udp.appendUInt16(UInt16(8 + dnsPayload.count))
        udp.appendUInt16(0)
        udp.append(dnsPayload)
        return ipv4Packet(
            source: [10, 0, 0, 9],
            destination: [100, 100, 100, 101],
            protocolNumber: 17,
            payload: Array(udp)
        )
    }

    private func dnsQueryPayload(name: String, queryType: UInt16) -> Data {
        var data = Data([0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(0)
        data.appendUInt16(queryType)
        data.appendUInt16(1)
        return data
    }

    private func dnsQuestionLength(name: String) -> Int {
        name.split(separator: ".").reduce(1 + 4) { length, label in
            length + 1 + label.utf8.count
        }
    }

    private func ipv4Packet(
        source: [UInt8],
        destination: [UInt8],
        protocolNumber: UInt8,
        payload: [UInt8]
    ) -> Data {
        let totalLength = UInt16(20 + payload.count)
        var data = Data([
            0x45, 0x00,
            UInt8(totalLength >> 8), UInt8(totalLength & 0xFF),
            0x00, 0x00, 0x00, 0x00,
            64, protocolNumber,
            0x00, 0x00
        ])
        data.append(contentsOf: source)
        data.append(contentsOf: destination)
        data.append(contentsOf: payload)
        return data
    }

    private func ipv4HeaderChecksum(_ packet: Data) -> UInt16 {
        var sum: UInt32 = 0
        for offset in stride(from: 0, to: 20, by: 2) {
            sum += UInt32(packet.readUInt16(at: offset))
        }
        while sum > 0xFFFF {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return UInt16(~sum & 0xFFFF)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    func readUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func readUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }
}

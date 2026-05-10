import Foundation
import XCTest
@testable import Spotier

final class PacketClassifierTests: XCTestCase {
    func testIPv4ClassificationAndRouting() throws {
        let packetData = ipv4Packet(
            source: [10, 0, 0, 1],
            destination: [10, 0, 0, 2],
            protocolNumber: 17,
            payload: [1, 2, 3, 4]
        )

        let packet = try PacketClassifier.parse(packetData)
        XCTAssertEqual(packet, .ipv4(IPv4Packet(
            sourceAddress: "10.0.0.1",
            destinationAddress: "10.0.0.2",
            protocolNumber: 17,
            payloadLength: 4
        )))

        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: "10.0.0.2",
            ipv6Address: nil,
            nextHopPeerID: PeerID(2),
            cost: 1,
            proxyCIDRs: []
        ))

        XCTAssertEqual(PacketRouter(routeTable: table).route(packet), .peer(PeerID(2)))
    }

    func testIPv6ClassificationAndLocalRouting() throws {
        let packetData = ipv6Packet(
            source: [0xfd00, 0, 0, 0, 0, 0, 0, 1],
            destination: [0xfd00, 0, 0, 0, 0, 0, 0, 2],
            nextHeader: 58,
            payload: [9, 9]
        )

        let packet = try PacketClassifier.parse(packetData)
        XCTAssertEqual(packet, .ipv6(IPv6Packet(
            sourceAddress: "fd00:0:0:0:0:0:0:1",
            destinationAddress: "fd00:0:0:0:0:0:0:2",
            nextHeader: 58,
            payloadLength: 2
        )))

        let router = PacketRouter(routeTable: RouteTable(), localIPv6: "fd00:0:0:0:0:0:0:2")
        XCTAssertEqual(router.route(packet), .local)
    }

    func testLocalRoutingMatchesConfiguredCIDRAddress() throws {
        let ipv4 = try PacketClassifier.parse(ipv4Packet(
            source: [10, 0, 0, 2],
            destination: [10, 0, 0, 1],
            protocolNumber: 17,
            payload: []
        ))
        let ipv6 = try PacketClassifier.parse(ipv6Packet(
            source: [0xfd00, 0, 0, 0, 0, 0, 0, 2],
            destination: [0xfd00, 0, 0, 0, 0, 0, 0, 1],
            nextHeader: 58,
            payload: []
        ))

        let router = PacketRouter(
            routeTable: RouteTable(),
            localIPv4: "10.0.0.1/24",
            localIPv6: "fd00:0:0:0:0:0:0:1/64"
        )

        XCTAssertEqual(router.route(ipv4), .local)
        XCTAssertEqual(router.route(ipv6), .local)
    }

    func testSubnetProxyRouting() throws {
        let packet = try PacketClassifier.parse(ipv4Packet(
            source: [10, 0, 0, 1],
            destination: [192, 168, 1, 10],
            protocolNumber: 6,
            payload: []
        ))
        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(3),
            ipv4Address: nil,
            ipv6Address: nil,
            nextHopPeerID: PeerID(3),
            cost: 2,
            proxyCIDRs: ["192.168.1.0/24"]
        ))

        XCTAssertEqual(PacketRouter(routeTable: table).route(packet), .subnetProxy(PeerID(3)))
    }

    func testUnknownRouteProducesDrop() throws {
        let packet = try PacketClassifier.parse(ipv4Packet(
            source: [10, 0, 0, 1],
            destination: [203, 0, 113, 10],
            protocolNumber: 17,
            payload: []
        ))

        XCTAssertEqual(PacketRouter(routeTable: RouteTable()).route(packet), .drop)
    }

    func testExternalIPv4UsesFirstAvailableExitNodeInConfiguredOrder() throws {
        let packet = try PacketClassifier.parse(ipv4Packet(
            source: [10, 126, 126, 4],
            destination: [203, 0, 113, 10],
            protocolNumber: 6,
            payload: []
        ))
        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(1),
            ipv4Address: "10.126.126.9",
            ipv6Address: nil,
            nextHopPeerID: PeerID(1),
            cost: 1,
            proxyCIDRs: []
        ))
        table.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: "10.126.126.10",
            ipv6Address: nil,
            nextHopPeerID: PeerID(2),
            cost: 1,
            proxyCIDRs: []
        ))

        let router = PacketRouter(
            routeTable: table,
            localIPv4: "10.126.126.4",
            localIPv6: nil,
            exitNodes: ["10.126.126.10", "10.126.126.9"]
        )

        XCTAssertEqual(router.route(packet), .exitNode(PeerID(2)))
    }

    func testP2POnlyDropsExternalIPv4InsteadOfUsingExitNode() throws {
        let packet = try PacketClassifier.parse(ipv4Packet(
            source: [10, 126, 126, 4],
            destination: [203, 0, 113, 10],
            protocolNumber: 6,
            payload: []
        ))
        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: "10.126.126.10",
            ipv6Address: nil,
            nextHopPeerID: PeerID(2),
            cost: 1,
            proxyCIDRs: []
        ))

        let router = PacketRouter(
            routeTable: table,
            localIPv4: "10.126.126.4/24",
            localIPv6: nil,
            exitNodes: ["10.126.126.10"],
            p2pOnly: true
        )

        XCTAssertEqual(router.route(packet), .drop)
    }

    func testSameVirtualIPv4NetworkUnknownPeerDoesNotUseExitNode() throws {
        let packet = try PacketClassifier.parse(ipv4Packet(
            source: [10, 126, 126, 4],
            destination: [10, 126, 126, 99],
            protocolNumber: 6,
            payload: []
        ))
        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: "10.126.126.10",
            ipv6Address: nil,
            nextHopPeerID: PeerID(2),
            cost: 1,
            proxyCIDRs: []
        ))

        let router = PacketRouter(
            routeTable: table,
            localIPv4: "10.126.126.4/24",
            localIPv6: nil,
            exitNodes: ["10.126.126.10"]
        )

        XCTAssertEqual(router.route(packet), .drop)
    }

    func testSameVirtualIPv6NetworkUnknownPeerDoesNotUseExitNode() throws {
        let packet = try PacketClassifier.parse(ipv6Packet(
            source: [0xfd00, 0, 0, 0, 0, 0, 0, 4],
            destination: [0xfd00, 0, 0, 0, 0, 0, 0, 99],
            nextHeader: 6,
            payload: []
        ))
        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: nil,
            ipv6Address: "fd00:0:0:0:0:0:0:10",
            nextHopPeerID: PeerID(2),
            cost: 1,
            proxyCIDRs: []
        ))

        let router = PacketRouter(
            routeTable: table,
            localIPv4: nil,
            localIPv6: "fd00:0:0:0:0:0:0:4/64",
            exitNodes: ["fd00:0:0:0:0:0:0:10"]
        )

        XCTAssertEqual(router.route(packet), .drop)
    }

    func testIPv6LinkLocalSourceIsDroppedUnlessItIsLocalAddress() throws {
        let remoteLinkLocalPacket = try PacketClassifier.parse(ipv6Packet(
            source: [0xfe80, 0, 0, 0, 0, 0, 0, 8],
            destination: [0xfd00, 0, 0, 0, 0, 0, 0, 2],
            nextHeader: 17,
            payload: []
        ))
        let localLinkLocalPacket = try PacketClassifier.parse(ipv6Packet(
            source: [0xfe80, 0, 0, 0, 0, 0, 0, 1],
            destination: [0xfd00, 0, 0, 0, 0, 0, 0, 2],
            nextHeader: 17,
            payload: []
        ))
        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: nil,
            ipv6Address: "fd00:0:0:0:0:0:0:2",
            nextHopPeerID: PeerID(2),
            cost: 1,
            proxyCIDRs: []
        ))

        let router = PacketRouter(
            routeTable: table,
            localIPv4: nil,
            localIPv6: "fe80:0:0:0:0:0:0:1/64"
        )

        XCTAssertEqual(router.route(remoteLinkLocalPacket), .drop)
        XCTAssertEqual(router.route(localLinkLocalPacket), .peer(PeerID(2)))
    }

    func testRejectsNonIPPacket() {
        XCTAssertThrowsError(try PacketClassifier.parse(Data([0x10, 0x00]))) { error in
            XCTAssertEqual(error as? IPPacketError, .nonIPPacket)
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

    private func ipv6Packet(
        source: [UInt16],
        destination: [UInt16],
        nextHeader: UInt8,
        payload: [UInt8]
    ) -> Data {
        let payloadLength = UInt16(payload.count)
        var data = Data([
            0x60, 0x00, 0x00, 0x00,
            UInt8(payloadLength >> 8), UInt8(payloadLength & 0xFF),
            nextHeader, 64
        ])
        appendIPv6(source, to: &data)
        appendIPv6(destination, to: &data)
        data.append(contentsOf: payload)
        return data
    }

    private func appendIPv6(_ groups: [UInt16], to data: inout Data) {
        for group in groups {
            data.append(UInt8(group >> 8))
            data.append(UInt8(group & 0xFF))
        }
    }
}

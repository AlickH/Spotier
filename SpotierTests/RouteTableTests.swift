import Foundation
import XCTest
@testable import Spotier

final class RouteTableTests: XCTestCase {
    func testDirectPeerHostRoute() {
        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(1),
            ipv4Address: "10.1.1.2",
            ipv6Address: "fd00::2",
            nextHopPeerID: PeerID(1),
            cost: 1,
            proxyCIDRs: []
        ))

        XCTAssertEqual(table.bestRoute(for: "10.1.1.2")?.ownerPeerID, PeerID(1))
        XCTAssertEqual(table.bestRoute(for: "fd00::2")?.ownerPeerID, PeerID(1))
        XCTAssertNil(table.bestRoute(for: "10.1.1.3"))
    }

    func testSubnetRouteSelectionUsesLowestCostThenNewestUpdate() {
        var table = RouteTable()
        let base = Date(timeIntervalSince1970: 100)

        table.apply(RouteUpdate(
            peerID: PeerID(1),
            ipv4Address: nil,
            ipv6Address: nil,
            nextHopPeerID: PeerID(1),
            cost: 10,
            proxyCIDRs: ["192.168.0.0/16"]
        ), now: base)
        table.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: nil,
            ipv6Address: nil,
            nextHopPeerID: PeerID(2),
            cost: 2,
            proxyCIDRs: ["192.168.1.0/24"]
        ), now: base.addingTimeInterval(1))

        XCTAssertEqual(table.bestRoute(for: "192.168.1.10")?.ownerPeerID, PeerID(2))

        table.apply(RouteUpdate(
            peerID: PeerID(3),
            ipv4Address: nil,
            ipv6Address: nil,
            nextHopPeerID: PeerID(3),
            cost: 2,
            proxyCIDRs: ["192.168.1.0/24"]
        ), now: base.addingTimeInterval(2))

        XCTAssertEqual(table.bestRoute(for: "192.168.1.10")?.ownerPeerID, PeerID(3))
    }

    func testRouteRemovalWhenPeerIsRemoved() {
        var table = RouteTable()
        table.apply(RouteUpdate(
            peerID: PeerID(1),
            ipv4Address: "10.1.1.2",
            ipv6Address: nil,
            nextHopPeerID: PeerID(1),
            cost: 1,
            proxyCIDRs: ["192.168.1.0/24"]
        ))

        table.removeRoutes(ownedBy: PeerID(1))

        XCTAssertNil(table.bestRoute(for: "10.1.1.2"))
        XCTAssertNil(table.bestRoute(for: "192.168.1.10"))
    }

    func testRouteCalculatorAddsDirectPeerRoutes() {
        var table = RouteTable()
        let peer = Peer(
            id: PeerID(4),
            hostname: "peer",
            virtualIPv4: "10.4.0.2",
            virtualIPv6: nil,
            publicKey: Data(),
            knownEndpoints: [],
            lastSeen: Date()
        )

        RouteCalculator.apply(peer: peer, to: &table)

        XCTAssertEqual(table.bestRoute(for: "10.4.0.2")?.nextHopPeerID, PeerID(4))
    }

    func testRouteCalculatorPreservesPeerSubnetProxyRoutes() {
        var table = RouteTable()
        let peer = Peer(
            id: PeerID(5),
            hostname: "peer",
            virtualIPv4: "10.5.0.2",
            virtualIPv6: nil,
            publicKey: Data(),
            knownEndpoints: [],
            lastSeen: Date()
        )
        table.apply(RouteUpdate(
            peerID: peer.id,
            ipv4Address: nil,
            ipv6Address: nil,
            nextHopPeerID: peer.id,
            cost: 1,
            proxyCIDRs: ["192.168.55.0/24"]
        ))

        RouteCalculator.apply(peer: peer, to: &table)

        XCTAssertEqual(table.bestRoute(for: "10.5.0.2")?.ownerPeerID, peer.id)
        XCTAssertEqual(table.bestRoute(for: "192.168.55.8")?.ownerPeerID, peer.id)
        XCTAssertEqual(table.bestRoute(for: "192.168.55.8")?.kind, .subnetProxy)
    }
}

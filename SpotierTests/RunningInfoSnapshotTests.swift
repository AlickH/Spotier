import Foundation
import XCTest
@testable import Spotier

final class RunningInfoSnapshotTests: XCTestCase {
    func testPreservesConsumedRunningInfoFields() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let local = try NodeIdentity.derive(
            network: network,
            deviceSeed: Data(repeating: 1, count: 32),
            hostname: "local",
            virtualIPv4: "10.0.0.1/24",
            virtualIPv6: nil
        )
        var store = PeerStore()
        store.upsert(Peer(
            id: PeerID(2),
            hostname: "peer",
            virtualIPv4: "10.0.0.2/24",
            virtualIPv6: nil,
            publicKey: Data(),
            knownEndpoints: [],
            version: "swift-core",
            lastSeen: Date()
        ))
        var routes = RouteTable()
        routes.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: "10.0.0.2",
            ipv6Address: nil,
            nextHopPeerID: PeerID(2),
            cost: 1,
            proxyCIDRs: ["192.168.1.0/24"]
        ))

        let snapshot = RunningInfoSnapshot.make(
            localIdentity: local,
            configuration: MeshEngineConfiguration(networkName: "easytier", networkSecret: "secret"),
            peerStore: store,
            routeTable: routes,
            events: [.statusChanged(.running)],
            running: true,
            errorMessage: nil
        )
        let json = try JSONSerialization.jsonObject(with: snapshot.jsonData()) as? [String: Any]

        XCTAssertEqual(json?["dev_name"] as? String, "local")
        XCTAssertNotNil(json?["my_node_info"])
        XCTAssertNotNil(json?["events"])
        XCTAssertNotNil(json?["routes"])
        XCTAssertNotNil(json?["peers"])
        XCTAssertNotNil(json?["peer_route_pairs"])
        XCTAssertEqual(json?["running"] as? Bool, true)
    }

    func testMeshEngineServesRunningInfoData() async throws {
        let engine = MeshEngine()
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.0.0.1/24"
        )

        try await engine.start(configuration: config)
        defer {
            Task { await engine.stop() }
        }

        let data = try XCTUnwrap(engine.runningInfoData())
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["running"] as? Bool, true)
        XCTAssertNotNil(json?["my_node_info"])
    }

    func testProviderRunningInfoCommandReturnsSwiftCoreSnapshot() async throws {
        let engine = MeshEngine()
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.0.0.1/24"
        )

        try await engine.start(configuration: config)
        defer {
            Task { await engine.stop() }
        }

        let data = try XCTUnwrap(engine.sendProviderCommand("running_info"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["dev_name"] as? String, engine.localIdentity?.hostname)
        XCTAssertNotNil(json?["my_node_info"])
        XCTAssertEqual(json?["running"] as? Bool, true)
    }

    func testRunningInfoNodeInfoExposesConfiguredListeners() async throws {
        let engine = MeshEngine()
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.0.0.1/24",
            listeners: ["udp://0.0.0.0:11010"],
            mappedListeners: ["udp://198.51.100.9:21010"]
        )

        try await engine.start(configuration: config)
        defer {
            Task { await engine.stop() }
        }

        let data = try XCTUnwrap(engine.runningInfoData())
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let nodeInfo = json?["my_node_info"] as? [String: Any]
        let listeners = nodeInfo?["listeners"] as? [[String: Any]]
        let urls = listeners?.compactMap { $0["url"] as? String }

        XCTAssertEqual(urls, ["udp://0.0.0.0:11010", "udp://198.51.100.9:21010"])
    }

    func testRunningInfoNodeInfoExposesPeerIDAndIPv6() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let local = try NodeIdentity.derive(
            network: network,
            deviceSeed: Data(repeating: 1, count: 32),
            hostname: "local",
            virtualIPv4: "10.0.0.1/24",
            virtualIPv6: "fd00:0:0:0:0:0:0:1/64"
        )
        let snapshot = RunningInfoSnapshot.make(
            localIdentity: local,
            configuration: MeshEngineConfiguration(networkName: "easytier", networkSecret: "secret"),
            peerStore: PeerStore(),
            routeTable: RouteTable(),
            events: [],
            running: true,
            errorMessage: nil
        )
        let json = try JSONSerialization.jsonObject(with: snapshot.jsonData()) as? [String: Any]
        let nodeInfo = json?["my_node_info"] as? [String: Any]
        let virtualIPv6 = nodeInfo?["virtual_ipv6"] as? [String: Any]

        XCTAssertEqual(nodeInfo?["peer_id"] as? Int, Int(UInt32(truncatingIfNeeded: local.peerID.rawValue)))
        XCTAssertNotNil(virtualIPv6)
        XCTAssertEqual(virtualIPv6?["network_length"] as? Int, 64)
    }

    func testRunningInfoGroupsPeerHostRouteWithProxyCIDRs() throws {
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
        var routes = RouteTable()
        routes.apply(RouteUpdate(
            peerID: PeerID(2),
            ipv4Address: "10.0.0.2",
            ipv6Address: nil,
            nextHopPeerID: PeerID(2),
            cost: 2,
            proxyCIDRs: ["192.168.77.0/24", "192.168.88.0/24"]
        ))

        let snapshot = RunningInfoSnapshot.make(
            localIdentity: nil,
            configuration: MeshEngineConfiguration(networkName: "easytier", networkSecret: "secret"),
            peerStore: store,
            routeTable: routes,
            events: [],
            running: true,
            errorMessage: nil
        )
        let json = try JSONSerialization.jsonObject(with: snapshot.jsonData()) as? [String: Any]
        let routeRows = json?["routes"] as? [[String: Any]]
        let route = try XCTUnwrap(routeRows?.first)
        let ipv4Address = route["ipv4_addr"] as? [String: Any]
        let address = ipv4Address?["address"] as? [String: Any]

        XCTAssertEqual(routeRows?.count, 1)
        XCTAssertEqual(address?["addr"] as? Int, 167772162)
        XCTAssertEqual(route["proxy_cidrs"] as? [String], ["192.168.77.0/24", "192.168.88.0/24"])
        XCTAssertEqual(route["version"] as? String, "swift-core")
    }

    func testRunningInfoRoutesAreSortedByIPv4Address() throws {
        var store = PeerStore()
        store.upsert(Peer(
            id: PeerID(3),
            hostname: "later",
            virtualIPv4: "10.0.0.3/24",
            virtualIPv6: nil,
            publicKey: Data(),
            knownEndpoints: [],
            lastSeen: Date()
        ))
        store.upsert(Peer(
            id: PeerID(2),
            hostname: "earlier",
            virtualIPv4: "10.0.0.2/24",
            virtualIPv6: nil,
            publicKey: Data(),
            knownEndpoints: [],
            lastSeen: Date()
        ))
        var routes = RouteTable()
        routes.apply(RouteUpdate(peerID: PeerID(3), ipv4Address: "10.0.0.3", ipv6Address: nil, nextHopPeerID: PeerID(3), cost: 1, proxyCIDRs: []))
        routes.apply(RouteUpdate(peerID: PeerID(2), ipv4Address: "10.0.0.2", ipv6Address: nil, nextHopPeerID: PeerID(2), cost: 1, proxyCIDRs: []))

        let snapshot = RunningInfoSnapshot.make(
            localIdentity: nil,
            configuration: MeshEngineConfiguration(networkName: "easytier", networkSecret: "secret"),
            peerStore: store,
            routeTable: routes,
            events: [],
            running: true,
            errorMessage: nil
        )
        let json = try JSONSerialization.jsonObject(with: snapshot.jsonData()) as? [String: Any]
        let routeRows = try XCTUnwrap(json?["routes"] as? [[String: Any]])
        let peerRoutePairs = try XCTUnwrap(json?["peer_route_pairs"] as? [[String: Any]])

        XCTAssertEqual(routeRows.compactMap { $0["peer_id"] as? Int }, [2, 3])
        XCTAssertEqual(peerRoutePairs.compactMap { ($0["route"] as? [String: Any])?["peer_id"] as? Int }, [2, 3])
    }

    func testRunningInfoPeerConnectionExposesDefaultUDPTunnel() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let local = try NodeIdentity.derive(
            network: network,
            deviceSeed: Data(repeating: 1, count: 32),
            hostname: "local",
            virtualIPv4: "10.0.0.1/24",
            virtualIPv6: nil
        )
        var store = PeerStore()
        store.upsert(Peer(
            id: PeerID(2),
            hostname: "peer",
            virtualIPv4: "10.0.0.2/24",
            virtualIPv6: nil,
            publicKey: Data(),
            knownEndpoints: [TransportEndpoint(host: "198.51.100.20", port: 22010)],
            lastSeen: Date()
        ))

        let snapshot = RunningInfoSnapshot.make(
            localIdentity: local,
            configuration: MeshEngineConfiguration(
                networkName: "easytier",
                networkSecret: "secret",
                listeners: ["udp://0.0.0.0:11010"]
            ),
            peerStore: store,
            routeTable: RouteTable(),
            events: [],
            running: true,
            errorMessage: nil
        )
        let json = try JSONSerialization.jsonObject(with: snapshot.jsonData()) as? [String: Any]
        let peers = json?["peers"] as? [[String: Any]]
        let peer = try XCTUnwrap(peers?.first)
        let connections = peer["conns"] as? [[String: Any]]
        let connection = try XCTUnwrap(connections?.first)
        let tunnel = connection["tunnel"] as? [String: Any]
        let localAddress = tunnel?["local_addr"] as? [String: Any]
        let remoteAddress = tunnel?["remote_addr"] as? [String: Any]
        let connectionID = try XCTUnwrap(connection["conn_id"] as? String)
        let defaultConnectionID = try XCTUnwrap(peer["default_conn_id"] as? [String: Any])
        let directlyConnected = try XCTUnwrap(peer["directly_connected_conns"] as? [[String: Any]])

        XCTAssertEqual(connectionID, uuidString(defaultConnectionID))
        XCTAssertEqual(directlyConnected.map(uuidString), [connectionID])
        XCTAssertEqual(tunnel?["tunnel_type"] as? String, "udp")
        XCTAssertEqual(localAddress?["url"] as? String, "udp://0.0.0.0:11010")
        XCTAssertEqual(remoteAddress?["url"] as? String, "udp://198.51.100.20:22010")
    }

    private func uuidString(_ parts: [String: Any]) -> String {
        String(
            format: "%08x-%08x-%08x-%08x",
            uuidPart(parts, "part1"),
            uuidPart(parts, "part2"),
            uuidPart(parts, "part3"),
            uuidPart(parts, "part4")
        )
    }

    private func uuidPart(_ parts: [String: Any], _ key: String) -> UInt32 {
        let number = parts[key] as? NSNumber
        return number?.uint32Value ?? 0
    }
}

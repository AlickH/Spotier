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
}

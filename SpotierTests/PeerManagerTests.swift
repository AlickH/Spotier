import Foundation
import XCTest
@testable import Spotier

final class PeerManagerTests: XCTestCase {
    func testPeerAdditionFromHello() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let local = try identity(seedByte: 1, network: network)
        let manager = PeerManager(localIdentity: local, network: network)
        let remote = try identity(seedByte: 2, network: network)
        let endpoint = TransportEndpoint(host: "127.0.0.1", port: 11010)
        let hello = helloFrame(from: remote)

        let responses = try manager.receive(TransportInboundFrame(frame: hello, remoteEndpoint: endpoint))

        let peer = manager.peerStore.peer(id: remote.peerID)
        XCTAssertEqual(peer?.hostname, "host-2")
        XCTAssertEqual(peer?.virtualIPv4, "10.0.0.2/24")
        XCTAssertEqual(peer?.knownEndpoints, [endpoint])
        XCTAssertEqual(peer?.routeCost, 1)
        XCTAssertEqual(responses.first?.payload, .control(.sessionOffer(local.publicKey)))
    }

    func testSessionEstablishment() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let clientIdentity = try identity(seedByte: 1, network: network)
        let serverIdentity = try identity(seedByte: 2, network: network)
        let client = PeerManager(localIdentity: clientIdentity, network: network)
        let server = PeerManager(localIdentity: serverIdentity, network: network)
        let endpoint = TransportEndpoint(host: "127.0.0.1", port: 11010)

        let offers = try server.receive(TransportInboundFrame(frame: client.makeHelloFrame(), remoteEndpoint: endpoint))
        let answers = try client.receive(TransportInboundFrame(frame: offers[0], remoteEndpoint: endpoint))
        _ = try server.receive(TransportInboundFrame(frame: answers[0], remoteEndpoint: endpoint))

        XCTAssertEqual(client.session(for: serverIdentity.peerID)?.health, .established)
        XCTAssertEqual(server.session(for: clientIdentity.peerID)?.health, .established)
        XCTAssertNotNil(client.session(for: serverIdentity.peerID)?.crypto)
        XCTAssertNotNil(server.session(for: clientIdentity.peerID)?.crypto)
    }

    func testPingPongRefreshesPeer() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let manager = try peerManager(seedByte: 1, network: network)
        let remote = try identity(seedByte: 2, network: network)
        let endpoint = TransportEndpoint(host: "127.0.0.1", port: 11010)
        let base = Date(timeIntervalSince1970: 100)

        _ = try manager.receive(TransportInboundFrame(frame: helloFrame(from: remote), remoteEndpoint: endpoint), now: base)
        let pong = try manager.receive(
            TransportInboundFrame(frame: pingFrame(from: remote), remoteEndpoint: endpoint),
            now: base.addingTimeInterval(3)
        )

        XCTAssertEqual(pong.first?.payload, .control(.peerPong))
        XCTAssertEqual(manager.peerStore.peer(id: remote.peerID)?.lastSeen, base.addingTimeInterval(3))
    }

    func testStalePeerRemoval() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let manager = try peerManager(seedByte: 1, network: network, staleTimeout: 10)
        let remote = try identity(seedByte: 2, network: network)
        let endpoint = TransportEndpoint(host: "127.0.0.1", port: 11010)
        let base = Date(timeIntervalSince1970: 100)

        _ = try manager.receive(TransportInboundFrame(frame: helloFrame(from: remote), remoteEndpoint: endpoint), now: base)

        let removed = manager.cleanupStalePeers(now: base.addingTimeInterval(10))

        XCTAssertEqual(removed, [remote.peerID])
        XCTAssertNil(manager.peerStore.peer(id: remote.peerID))
        XCTAssertNil(manager.session(for: remote.peerID))
    }

    private func peerManager(
        seedByte: UInt8,
        network: NetworkSecret,
        staleTimeout: TimeInterval = 30
    ) throws -> PeerManager {
        PeerManager(
            localIdentity: try identity(seedByte: seedByte, network: network),
            network: network,
            staleTimeout: staleTimeout
        )
    }

    private func identity(seedByte: UInt8, network: NetworkSecret) throws -> NodeIdentity {
        try NodeIdentity.derive(
            network: network,
            deviceSeed: Data(repeating: seedByte, count: 32),
            hostname: "host-\(seedByte)",
            virtualIPv4: "10.0.0.\(seedByte)/24",
            virtualIPv6: nil
        )
    }

    private func helloFrame(from identity: NodeIdentity) -> CoreFrame {
        CoreFrame(
            type: .control,
            sender: identity.peerID,
            receiver: PeerID(0),
            sequence: 1,
            payload: .control(.hello(ControlMessage.Hello(
                hostname: identity.hostname,
                virtualIPv4: identity.virtualIPv4,
                virtualIPv6: identity.virtualIPv6,
                publicKey: identity.publicKey
            )))
        )
    }

    private func pingFrame(from identity: NodeIdentity) -> CoreFrame {
        CoreFrame(
            type: .control,
            sender: identity.peerID,
            receiver: PeerID(1),
            sequence: 2,
            payload: .control(.peerPing)
        )
    }

}

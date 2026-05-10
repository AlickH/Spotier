import Foundation
import XCTest
@testable import Spotier

final class HolePunchCoordinatorTests: XCTestCase {
    func testConfiguredSTUNClientBuildsBindingRequest() throws {
        let transactionID = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        let server = TransportEndpoint(host: "stun.example.com", port: 3478)
        let client = STUNClient(server: server)

        let request = try client.bindingRequest(transactionID: transactionID)

        XCTAssertEqual(client.server, server)
        XCTAssertEqual(request.count, 20)
        XCTAssertEqual(request[0], 0)
        XCTAssertEqual(request[1], 1)
        XCTAssertEqual(request[8..<20], transactionID[0..<12])
    }

    func testSTUNResponseParsingUsingFixtureBytes() throws {
        let transactionID = Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        let response = stunBindingResponse(
            transactionID: transactionID,
            publicAddress: "203.0.113.9",
            publicPort: 54321
        )

        let client = STUNClient(server: TransportEndpoint(host: "stun.example.com", port: 3478))
        let endpoint = try client.discoverPublicEndpoint(from: response, transactionID: transactionID)

        XCTAssertEqual(endpoint, TransportEndpoint(host: "203.0.113.9", port: 54321))
    }

    func testEndpointCandidateExchange() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let local = try identity(seedByte: 1, network: network)
        let remote = try identity(seedByte: 2, network: network)
        let manager = PeerManager(localIdentity: local, network: network)
        let endpoint = TransportEndpoint(host: "203.0.113.9", port: 11010)

        _ = try manager.receive(TransportInboundFrame(
            frame: helloFrame(from: remote),
            remoteEndpoint: TransportEndpoint(host: "127.0.0.1", port: 11010)
        ))
        let outgoingCandidate = manager.publishEndpointCandidate(endpoint, to: remote.peerID)
        XCTAssertEqual(outgoingCandidate?.payload, .control(.endpointCandidate("udp://203.0.113.9:11010")))

        let candidate = endpointCandidateFrame(from: remote.peerID, to: local.peerID, endpoint: endpoint)
        _ = try manager.receive(TransportInboundFrame(frame: candidate, remoteEndpoint: endpoint))

        XCTAssertTrue(manager.peerStore.peer(id: remote.peerID)?.knownEndpoints.contains(endpoint) == true)
    }

    func testDisabledUDPHolePunchingDoesNotPublishOrAcceptCandidates() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let local = try identity(seedByte: 1, network: network)
        let remote = try identity(seedByte: 2, network: network)
        let manager = PeerManager(localIdentity: local, network: network, udpHolePunchingEnabled: false)
        let endpoint = TransportEndpoint(host: "203.0.113.9", port: 11010)

        _ = try manager.receive(TransportInboundFrame(
            frame: helloFrame(from: remote),
            remoteEndpoint: TransportEndpoint(host: "127.0.0.1", port: 11010)
        ))

        XCTAssertNil(manager.publishEndpointCandidate(endpoint, to: remote.peerID))

        let candidate = endpointCandidateFrame(from: remote.peerID, to: local.peerID, endpoint: endpoint)
        _ = try manager.receive(TransportInboundFrame(frame: candidate, remoteEndpoint: endpoint))

        XCTAssertFalse(manager.peerStore.peer(id: remote.peerID)?.knownEndpoints.contains(endpoint) == true)
    }

    func testDirectTransportPromotionAfterAuthenticatedProbe() throws {
        let coordinator = HolePunchCoordinator()
        let peerID = PeerID(2)
        let endpoint = TransportEndpoint(host: "203.0.113.9", port: 11010)

        coordinator.setRelayActive(for: peerID)
        _ = coordinator.receiveRemoteCandidate(endpoint, from: peerID)

        XCTAssertEqual(coordinator.transportPreference(for: peerID), .relay)
        XCTAssertTrue(coordinator.relayPeers.contains(peerID))

        coordinator.authenticateProbeResponse(from: peerID, endpoint: endpoint)

        XCTAssertEqual(coordinator.transportPreference(for: peerID), .direct)
        XCTAssertTrue(coordinator.relayPeers.contains(peerID))
    }

    private func identity(seedByte: UInt8, network: NetworkSecret) throws -> NodeIdentity {
        try NodeIdentity.derive(
            network: network,
            deviceSeed: Data(repeating: seedByte, count: 32),
            hostname: "host-\(seedByte)",
            virtualIPv4: nil,
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
                publicKey: identity.publicKey,
                version: "swift-core"
            )))
        )
    }

    private func endpointCandidateFrame(from sender: PeerID, to receiver: PeerID, endpoint: TransportEndpoint) -> CoreFrame {
        CoreFrame(
            type: .control,
            sender: sender,
            receiver: receiver,
            sequence: 2,
            payload: .control(.endpointCandidate("udp://\(endpoint.description)"))
        )
    }

    private func stunBindingResponse(transactionID: Data, publicAddress: String, publicPort: UInt16) -> Data {
        let cookie = STUNBindingRequest.magicCookie
        let address = ipv4Value(publicAddress)
        let xorPort = publicPort ^ UInt16(cookie >> 16)
        let xorAddress = address ^ cookie

        var data = Data()
        data.appendUInt16(0x0101)
        data.appendUInt16(8)
        data.appendUInt32(cookie)
        data.append(transactionID)
        data.appendUInt16(0x0020)
        data.appendUInt16(8)
        data.append(0)
        data.append(0x01)
        data.appendUInt16(xorPort)
        data.appendUInt32(xorAddress)
        return data
    }

    private func ipv4Value(_ address: String) -> UInt32 {
        address
            .split(separator: ".")
            .compactMap { UInt32($0) }
            .reduce(UInt32(0)) { ($0 << 8) | $1 }
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}

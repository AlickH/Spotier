import XCTest
@testable import Spotier

final class MeshEngineTransportTests: XCTestCase {
    func testStartsUDPTransportFromConfiguredListener() async throws {
        let engine = MeshEngine()
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            listeners: ["udp://127.0.0.1:19093"]
        )

        try await engine.start(configuration: config)
        defer {
            Task { await engine.stop() }
        }

        XCTAssertEqual(engine.status, .running)
        XCTAssertTrue(engine.events.contains(.statusChanged(.running)))
    }

    func testTransportStartFailureEmitsFatalError() async throws {
        let engine = MeshEngine(transport: FailingStartTransport())
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            listeners: ["udp://127.0.0.1:19094"]
        )

        do {
            try await engine.start(configuration: config)
            XCTFail("Expected UDP bind failure")
        } catch {
            XCTAssertTrue(engine.events.contains { event in
                if case .fatalError = event {
                    return true
                }
                return false
            })
        }
    }

    func testUDPBootstrapSkipsNonUDPPeers() async throws {
        let transport = RecordingTransport()
        let engine = MeshEngine(transport: transport)
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            peers: [
                "tcp://relay.example.com:11010",
                "udp://198.51.100.20:11010"
            ],
            listeners: ["udp://127.0.0.1:19094"]
        )

        try await engine.start(configuration: config)
        defer {
            Task { await engine.stop() }
        }

        XCTAssertEqual(transport.sentEndpoints, [
            TransportEndpoint(host: "198.51.100.20", port: 11010)
        ])
    }

    func testStartFailsWhenConfiguredPeersContainNoUDPPeer() async {
        let transport = RecordingTransport()
        let engine = MeshEngine(transport: transport)
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            peers: ["tcp://relay.example.com:11010"],
            listeners: ["udp://127.0.0.1:19094"]
        )

        do {
            try await engine.start(configuration: config)
            XCTFail("Expected unsupported peer failure")
        } catch {
            XCTAssertEqual(error as? TransportError, .unsupportedPeerScheme)
            XCTAssertTrue(engine.events.contains(.fatalError("unsupportedPeerScheme")))
            XCTAssertFalse(transport.didStart)
            XCTAssertTrue(transport.sentEndpoints.isEmpty)
        }
    }

    func testStartFailsWhenListenersAreConfiguredButNoneAreUDP() async {
        let engine = MeshEngine()
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            listeners: ["tcp://127.0.0.1:19095"]
        )

        do {
            try await engine.start(configuration: config)
            XCTFail("Expected unsupported listener failure")
        } catch {
            XCTAssertEqual(error as? TransportError, .unsupportedListenerScheme)
            XCTAssertTrue(engine.events.contains(.fatalError("unsupportedListenerScheme")))
        }
    }
}

private final class FailingStartTransport: Transport {
    let inboundFrames = AsyncStream<TransportInboundFrame> { continuation in
        continuation.finish()
    }

    func start() async throws {
        throw TransportError.listenerUnavailable
    }

    func stop() async {}

    func send(_ frame: CoreFrame, to endpoint: TransportEndpoint) async throws {
        throw TransportError.connectionUnavailable
    }
}

private final class RecordingTransport: Transport {
    let inboundFrames = AsyncStream<TransportInboundFrame> { continuation in
        continuation.finish()
    }

    private(set) var didStart = false
    private(set) var sentEndpoints: [TransportEndpoint] = []

    func start() async throws {
        didStart = true
    }

    func stop() async {}

    func send(_ frame: CoreFrame, to endpoint: TransportEndpoint) async throws {
        sentEndpoints.append(endpoint)
    }
}

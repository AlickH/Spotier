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
        let occupiedTransport = UDPTransport(bindPort: 19094)
        try await occupiedTransport.start()
        defer {
            Task { await occupiedTransport.stop() }
        }

        let engine = MeshEngine()
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
}

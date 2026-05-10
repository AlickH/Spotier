import Foundation
import Network
import XCTest
@testable import Spotier

final class UDPTransportTests: XCTestCase {
    func testEndpointParsing() throws {
        let endpoint = try TransportEndpoint(urlString: "udp://127.0.0.1:11010")

        XCTAssertEqual(endpoint.host, "127.0.0.1")
        XCTAssertEqual(endpoint.port, 11010)
        XCTAssertEqual(endpoint.description, "127.0.0.1:11010")
    }

    func testRejectsInvalidEndpointURL() {
        XCTAssertThrowsError(try TransportEndpoint(urlString: "not-a-url")) { error in
            XCTAssertEqual(error as? TransportEndpointError, .invalidURL("not-a-url"))
        }
    }

    func testLocalUDPSendReceiveOnLoopback() async throws {
        let receiver = UDPTransport(bindPort: 19091)
        try await receiver.start()
        defer {
            Task { await receiver.stop() }
        }

        let sender = UDPTransport(bindPort: 0)
        let frame = CoreFrame(
            type: .control,
            sender: PeerID(1),
            receiver: PeerID(2),
            sequence: 3,
            payload: .control(.peerPing)
        )

        try await sender.send(frame, to: TransportEndpoint(host: "127.0.0.1", port: 19091))

        var iterator = receiver.inboundFrames.makeAsyncIterator()
        let received = await iterator.next()

        XCTAssertEqual(received?.frame, frame)
    }

    func testInvalidFrameDoesNotCrashTransport() async throws {
        let receiver = UDPTransport(bindPort: 19092)
        try await receiver.start()
        defer {
            Task { await receiver.stop() }
        }

        let endpoint = TransportEndpoint(host: "127.0.0.1", port: 19092)
        let rawSender = UDPTransport(bindPort: 0)
        let invalid = CoreFrame(
            type: .data,
            sender: PeerID(1),
            receiver: PeerID(2),
            sequence: 1,
            payload: .data(DataPacket(encryptedIPPacket: Data([1, 2, 3])))
        )
        var encoded = try FrameCodec.encode(invalid)
        encoded[0] = 99

        try await rawSender.sendRaw(encoded, to: endpoint)
        try await Task.sleep(for: .milliseconds(100))

        var iterator = receiver.inboundFrames.makeAsyncIterator()
        let next = await withTimeout(milliseconds: 100) {
            await iterator.next()
        }
        XCTAssertNil(next)
    }
}

private extension UDPTransport {
    func sendRaw(_ data: Data, to endpoint: TransportEndpoint) async throws {
        let connection = NWConnection(to: endpoint.nwEndpoint, using: .udp)
        connection.start(queue: DispatchQueue(label: "spotier.udp.test.raw"))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                connection.cancel()
                if error == nil {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: TransportError.sendFailed)
                }
            })
        }
    }
}

private func withTimeout<T>(
    milliseconds: UInt64,
    operation: @escaping () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operation()
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

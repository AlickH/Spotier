import Foundation
import Network
import XCTest
@testable import Spotier

final class RelayTransportTests: XCTestCase {
    func testLengthPrefixedControlFrameRoundTripUsingLocalListener() async throws {
        let pair = try relaySessionPair()
        let server = try RelayTestServer(port: 19095, crypto: pair.server)
        try await server.start()
        defer {
            Task { await server.stop() }
        }

        let transport = try RelayTransport(urlString: "tcp://127.0.0.1:19095", sessionCrypto: pair.client)
        try await transport.start()
        defer {
            Task { await transport.stop() }
        }

        let frame = CoreFrame(
            type: .control,
            sender: PeerID(1),
            receiver: PeerID(2),
            sequence: 11,
            payload: .control(.peerPing)
        )

        try await transport.send(frame, to: TransportEndpoint(host: "127.0.0.1", port: 19095))

        var iterator = transport.inboundFrames.makeAsyncIterator()
        let received = await withRelayTimeout(milliseconds: 500) {
            await iterator.next()
        }

        XCTAssertEqual(received?.frame, frame)
    }

    func testRelaysEncryptedDataFrames() async throws {
        let pair = try relaySessionPair()
        let server = try RelayTestServer(port: 19096, crypto: pair.server)
        try await server.start()
        defer {
            Task { await server.stop() }
        }

        let transport = try RelayTransport(urlString: "tcp://127.0.0.1:19096", sessionCrypto: pair.client)
        try await transport.start()
        defer {
            Task { await transport.stop() }
        }

        let frame = CoreFrame(
            type: .data,
            sender: PeerID(1),
            receiver: PeerID(2),
            sequence: 12,
            payload: .data(DataPacket(encryptedIPPacket: Data([1, 2, 3, 4])))
        )

        try await transport.send(frame, to: TransportEndpoint(host: "127.0.0.1", port: 19096))

        var iterator = transport.inboundFrames.makeAsyncIterator()
        let received = await withRelayTimeout(milliseconds: 500) {
            await iterator.next()
        }

        XCTAssertEqual(received?.frame, frame)
    }

    func testRelayUsesTLSForTLSScheme() throws {
        let pair = try relaySessionPair()
        let transport = try RelayTransport(urlString: "tls://relay.example.com:443", sessionCrypto: pair.client)

        XCTAssertTrue(transport.usesTLS)
    }

    func testRelayReconnectIsOnlyExplicitTransportRestart() async throws {
        let pair = try relaySessionPair()
        let server = try RelayTestServer(port: 19097, crypto: pair.server, closeConnectionsImmediately: true)
        try await server.start()
        defer {
            Task { await server.stop() }
        }

        let firstTransport = try RelayTransport(urlString: "tcp://127.0.0.1:19097", sessionCrypto: pair.client)
        try await firstTransport.start()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(server.connectionCount, 1)

        await firstTransport.stop()

        let secondPair = try relaySessionPair()
        let secondTransport = try RelayTransport(urlString: "tcp://127.0.0.1:19097", sessionCrypto: secondPair.client)
        try await secondTransport.start()
        try await Task.sleep(for: .milliseconds(150))
        await secondTransport.stop()

        XCTAssertEqual(server.connectionCount, 2)
    }
}

private final class RelayTestServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "spotier.relay.test.server")
    private let crypto: SessionCrypto
    private let closeConnectionsImmediately: Bool
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private(set) var connectionCount = 0

    init(port: UInt16, crypto: SessionCrypto, closeConnectionsImmediately: Bool = false) throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        self.crypto = crypto
        self.closeConnectionsImmediately = closeConnectionsImmediately
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            continuations.append(continuation)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    self.resumeStart()
                case .failed(let error):
                    self.resumeStart(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.connectionCount += 1
                if self?.closeConnectionsImmediately == true {
                    connection.cancel()
                    return
                }

                let decoder = RelayFrameStreamDecoder()
                self?.receive(on: connection, decoder: decoder)
                connection.start(queue: self?.queue ?? .main)
            }
            listener.start(queue: queue)
        }
    }

    func stop() async {
        listener.cancel()
    }

    private func receive(on connection: NWConnection, decoder: RelayFrameStreamDecoder) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                do {
                    let records = try decoder.append(data)
                    for record in records {
                        let frame = try RelayFrameCodec.decode(record, crypto: self.crypto)
                        let encoded = try RelayFrameCodec.encode(frame, crypto: self.crypto)
                        connection.send(content: encoded, completion: .contentProcessed { _ in })
                    }
                } catch {
                    connection.cancel()
                    return
                }
            }

            guard error == nil, !isComplete else { return }
            self.receive(on: connection, decoder: decoder)
        }
    }

    private func resumeStart(throwing error: Error? = nil) {
        let pending = continuations
        continuations.removeAll()

        for continuation in pending {
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: ())
            }
        }
    }
}

private func relaySessionPair() throws -> (client: SessionCrypto, server: SessionCrypto) {
    let network = NetworkSecret(networkName: "easytier", secret: "secret")
    let clientIdentity = try NodeIdentity.derive(
        network: network,
        deviceSeed: Data(repeating: 1, count: 32),
        hostname: "client",
        virtualIPv4: nil,
        virtualIPv6: nil
    )
    let serverIdentity = try NodeIdentity.derive(
        network: network,
        deviceSeed: Data(repeating: 2, count: 32),
        hostname: "server",
        virtualIPv4: nil,
        virtualIPv6: nil
    )

    return (
        try SessionCrypto.establish(
            localIdentity: clientIdentity,
            handshake: HandshakeState(
                network: network,
                localPeerID: clientIdentity.peerID,
                remotePeerID: serverIdentity.peerID,
                remotePublicKey: serverIdentity.publicKey,
                role: .initiator
            )
        ),
        try SessionCrypto.establish(
            localIdentity: serverIdentity,
            handshake: HandshakeState(
                network: network,
                localPeerID: serverIdentity.peerID,
                remotePeerID: clientIdentity.peerID,
                remotePublicKey: clientIdentity.publicKey,
                role: .responder
            )
        )
    )
}

private func withRelayTimeout<T>(
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

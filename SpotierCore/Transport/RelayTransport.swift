import Foundation
import Network

final class RelayTransport: Transport {
    let inboundFrames: AsyncStream<TransportInboundFrame>

    private let relayEndpoint: TransportEndpoint
    private let parameters: NWParameters
    private let sessionCrypto: SessionCrypto
    private let queue = DispatchQueue(label: "spotier.relay.transport")
    private let decoder = RelayFrameStreamDecoder()
    private var connection: NWConnection?
    private var continuation: AsyncStream<TransportInboundFrame>.Continuation?
    private var startContinuation: CheckedContinuation<Void, Error>?

    let usesTLS: Bool

    init(urlString: String, sessionCrypto: SessionCrypto) throws {
        guard let url = URL(string: urlString),
              let scheme = url.scheme else {
            throw RelayTransportError.invalidURL(urlString)
        }

        switch scheme {
        case "tcp":
            parameters = .tcp
            usesTLS = false
        case "tls":
            parameters = .tls
            usesTLS = true
        default:
            throw RelayTransportError.unsupportedScheme(scheme)
        }

        relayEndpoint = try TransportEndpoint(urlString: urlString)
        self.sessionCrypto = sessionCrypto

        let stream = AsyncStream<TransportInboundFrame>.makeStream()
        inboundFrames = stream.stream
        continuation = stream.continuation
    }

    func start() async throws {
        let connection = NWConnection(to: relayEndpoint.nwEndpoint, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.startContinuation = continuation

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    self.resumeStart()
                    self.receive(on: connection)
                case .failed(let error):
                    self.resumeStart(throwing: error)
                    self.connection = nil
                    self.continuation?.finish()
                case .cancelled:
                    self.connection = nil
                    self.continuation?.finish()
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    func stop() async {
        connection?.cancel()
        connection = nil
        continuation?.finish()
    }

    func send(_ frame: CoreFrame, to endpoint: TransportEndpoint) async throws {
        guard let connection else {
            throw TransportError.connectionUnavailable
        }

        let data = try RelayFrameCodec.encode(frame, crypto: sessionCrypto)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if error == nil {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: TransportError.sendFailed)
                }
            })
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                do {
                    let records = try self.decoder.append(data)
                    for record in records {
                        let frame = try RelayFrameCodec.decode(record, crypto: self.sessionCrypto)
                        self.continuation?.yield(TransportInboundFrame(
                            frame: frame,
                            remoteEndpoint: self.relayEndpoint
                        ))
                    }
                } catch {
                    self.connection = nil
                    self.continuation?.finish()
                    connection.cancel()
                    return
                }
            }

            guard error == nil, !isComplete else {
                self.connection = nil
                self.continuation?.finish()
                return
            }

            self.receive(on: connection)
        }
    }

    private func resumeStart(throwing error: Error? = nil) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }
}

enum RelayTransportError: Error, Equatable {
    case invalidURL(String)
    case unsupportedScheme(String)
}

enum RelayFrameCodec {
    static func encode(_ frame: CoreFrame, crypto: SessionCrypto) throws -> Data {
        let plaintext = try FrameCodec.encode(frame)
        let ciphertext = try crypto.encrypt(sequence: frame.sequence, plaintext: plaintext)

        var record = Data()
        record.reserveCapacity(8 + ciphertext.count)
        record.appendUInt64(frame.sequence)
        record.append(ciphertext)

        var data = Data()
        data.reserveCapacity(4 + record.count)
        data.appendUInt32(UInt32(record.count))
        data.append(record)
        return data
    }

    static func decode(_ record: Data, crypto: SessionCrypto) throws -> CoreFrame {
        guard record.count >= 8 else {
            throw TransportError.malformedRelayFrame
        }

        let sequence = record.readUInt64(at: 0)
        let ciphertext = record.dropFirst(8)
        let plaintext = try crypto.decrypt(sequence: sequence, ciphertext: Data(ciphertext))
        return try FrameCodec.decode(plaintext)
    }
}

final class RelayFrameStreamDecoder {
    private var buffer = Data()

    func append(_ data: Data) throws -> [Data] {
        buffer.append(data)

        var records: [Data] = []
        while buffer.count >= 4 {
            let length = Int(buffer.readUInt32(at: 0))
            guard buffer.count >= 4 + length else { break }

            records.append(Data(buffer[4..<4 + length]))
            buffer.removeFirst(4 + length)
        }

        return records
    }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt64(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xFF))
        append(UInt8((value >> 48) & 0xFF))
        append(UInt8((value >> 40) & 0xFF))
        append(UInt8((value >> 32) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    func readUInt32(at offset: Int) -> UInt32 {
        let bytes = self[offset..<offset + 4]
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func readUInt64(at offset: Int) -> UInt64 {
        let bytes = self[offset..<offset + 8]
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

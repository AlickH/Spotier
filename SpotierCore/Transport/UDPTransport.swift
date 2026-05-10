import Foundation
import Network

final class UDPTransport: Transport {
    let inboundFrames: AsyncStream<TransportInboundFrame>

    private let bindPort: UInt16
    private let queue = DispatchQueue(label: "spotier.udp.transport")
    private var listener: NWListener?
    private var continuation: AsyncStream<TransportInboundFrame>.Continuation?

    init(bindPort: UInt16) {
        self.bindPort = bindPort
        let stream = AsyncStream<TransportInboundFrame>.makeStream()
        inboundFrames = stream.stream
        continuation = stream.continuation
    }

    func start() async throws {
        let listener = try NWListener(
            using: .udp,
            on: NWEndpoint.Port(rawValue: bindPort)!
        )
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(on: connection)
            connection.start(queue: self?.queue ?? .main)
        }
        listener.start(queue: queue)
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        continuation?.finish()
    }

    func send(_ frame: CoreFrame, to endpoint: TransportEndpoint) async throws {
        let data = try FrameCodec.encode(frame)
        let connection = NWConnection(to: endpoint.nwEndpoint, using: .udp)
        connection.start(queue: queue)

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

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, _ in
            guard let self else { return }
            defer {
                self.receive(on: connection)
            }

            guard let data else { return }
            guard let frame = try? FrameCodec.decode(data) else { return }
            guard let remoteEndpoint = self.remoteEndpoint(from: connection.endpoint) else { return }

            self.continuation?.yield(TransportInboundFrame(
                frame: frame,
                remoteEndpoint: remoteEndpoint
            ))
        }
    }

    private func remoteEndpoint(from endpoint: NWEndpoint) -> TransportEndpoint? {
        switch endpoint {
        case .hostPort(let host, let port):
            return TransportEndpoint(host: String(describing: host), port: port.rawValue)
        default:
            return nil
        }
    }
}

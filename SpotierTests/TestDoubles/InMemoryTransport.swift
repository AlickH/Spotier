import Foundation
@testable import Spotier

final class InMemoryTransport: Transport {
    let endpoint: TransportEndpoint
    let inboundFrames: AsyncStream<TransportInboundFrame>

    private(set) var sentFrames: [CoreFrame] = []
    private var continuation: AsyncStream<TransportInboundFrame>.Continuation?
    private var peers: [TransportEndpoint: InMemoryTransport] = [:]

    init(endpoint: TransportEndpoint) {
        self.endpoint = endpoint
        let stream = AsyncStream<TransportInboundFrame>.makeStream()
        inboundFrames = stream.stream
        continuation = stream.continuation
    }

    func connect(to peer: InMemoryTransport) {
        peers[peer.endpoint] = peer
        peer.peers[endpoint] = self
    }

    func start() async throws {}

    func stop() async {
        continuation?.finish()
    }

    func send(_ frame: CoreFrame, to endpoint: TransportEndpoint) async throws {
        guard let peer = peers[endpoint] else {
            throw TransportError.sendFailed
        }
        sentFrames.append(frame)
        peer.continuation?.yield(TransportInboundFrame(frame: frame, remoteEndpoint: self.endpoint))
    }
}

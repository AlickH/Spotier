import Foundation

struct TransportInboundFrame: Equatable {
    var frame: CoreFrame
    var remoteEndpoint: TransportEndpoint
}

protocol Transport {
    var inboundFrames: AsyncStream<TransportInboundFrame> { get }

    func start() async throws
    func stop() async
    func send(_ frame: CoreFrame, to endpoint: TransportEndpoint) async throws
}

enum TransportError: Error, Equatable {
    case listenerUnavailable
    case unsupportedListenerScheme
    case unsupportedPeerScheme
    case connectionUnavailable
    case sendFailed
    case malformedRelayFrame
}

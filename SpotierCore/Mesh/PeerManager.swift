import Foundation

final class PeerManager {
    private let localIdentity: NodeIdentity
    private let network: NetworkSecret
    private let staleTimeout: TimeInterval
    private var nextSequence: UInt64 = 1

    private(set) var peerStore = PeerStore()
    private(set) var sessions: [PeerID: PeerSession] = [:]

    init(
        localIdentity: NodeIdentity,
        network: NetworkSecret,
        staleTimeout: TimeInterval = 30
    ) {
        self.localIdentity = localIdentity
        self.network = network
        self.staleTimeout = staleTimeout
    }

    func makeHelloFrame() -> CoreFrame {
        makeControlFrame(
            receiver: PeerID(0),
            payload: .hello(ControlMessage.Hello(
                hostname: localIdentity.hostname,
                virtualIPv4: localIdentity.virtualIPv4,
                virtualIPv6: localIdentity.virtualIPv6,
                publicKey: localIdentity.publicKey
            ))
        )
    }

    func receive(_ inbound: TransportInboundFrame, now: Date = Date()) throws -> [CoreFrame] {
        guard case .control(let message) = inbound.frame.payload else {
            return []
        }

        switch message {
        case .hello(let hello):
            return try receiveHello(
                hello,
                from: inbound.frame.sender,
                endpoint: inbound.remoteEndpoint,
                now: now
            )
        case .sessionOffer(let publicKey):
            return try receiveSessionOffer(
                publicKey,
                from: inbound.frame.sender,
                now: now
            )
        case .sessionAnswer(let publicKey):
            try receiveSessionAnswer(publicKey, from: inbound.frame.sender, now: now)
            return []
        case .peerPing:
            refreshPeer(inbound.frame.sender, now: now)
            return [makeControlFrame(receiver: inbound.frame.sender, payload: .peerPong)]
        case .peerPong:
            refreshPeer(inbound.frame.sender, now: now)
            return []
        case .relayRequest, .relayResponse, .routeUpdate, .endpointCandidate:
            refreshPeer(inbound.frame.sender, now: now)
            return []
        }
    }

    func cleanupStalePeers(now: Date = Date()) -> [PeerID] {
        let staleIDs = peerStore.markStale(now: now, timeout: staleTimeout)
        for id in staleIDs {
            sessions[id]?.markStale()
        }

        let removedIDs = peerStore.removeStalePeers()
        for id in removedIDs {
            sessions[id] = nil
        }
        return removedIDs
    }

    func session(for peerID: PeerID) -> PeerSession? {
        sessions[peerID]
    }

    private func receiveHello(
        _ hello: ControlMessage.Hello,
        from peerID: PeerID,
        endpoint: TransportEndpoint,
        now: Date
    ) throws -> [CoreFrame] {
        let peer = Peer(
            id: peerID,
            hostname: hello.hostname,
            virtualIPv4: hello.virtualIPv4,
            virtualIPv6: hello.virtualIPv6,
            publicKey: hello.publicKey,
            knownEndpoints: [endpoint],
            lastSeen: now
        )
        peerStore.upsert(peer)

        sessions[peerID] = PeerSession(
            peerID: peerID,
            handshakeState: HandshakeState(
                network: network,
                localPeerID: localIdentity.peerID,
                remotePeerID: peerID,
                remotePublicKey: hello.publicKey,
                role: .responder
            )
        )

        return [makeControlFrame(receiver: peerID, payload: .sessionOffer(localIdentity.publicKey))]
    }

    private func receiveSessionOffer(
        _ publicKey: Data,
        from peerID: PeerID,
        now: Date
    ) throws -> [CoreFrame] {
        peerStore.updatePeer(id: peerID) { peer in
            peer.publicKey = publicKey
            peer.lastSeen = now
            peer.isStale = false
        }

        var session = PeerSession(
            peerID: peerID,
            handshakeState: HandshakeState(
                network: network,
                localPeerID: localIdentity.peerID,
                remotePeerID: peerID,
                remotePublicKey: publicKey,
                role: .initiator
            )
        )
        try session.establish(localIdentity: localIdentity)
        sessions[peerID] = session

        return [makeControlFrame(receiver: peerID, payload: .sessionAnswer(localIdentity.publicKey))]
    }

    private func receiveSessionAnswer(_ publicKey: Data, from peerID: PeerID, now: Date) throws {
        peerStore.updatePeer(id: peerID) { peer in
            peer.publicKey = publicKey
            peer.lastSeen = now
            peer.isStale = false
        }

        guard var session = sessions[peerID] else { return }
        session.handshakeState.remotePublicKey = publicKey
        try session.establish(localIdentity: localIdentity)
        sessions[peerID] = session
    }

    private func refreshPeer(_ peerID: PeerID, now: Date) {
        peerStore.updatePeer(id: peerID) { peer in
            peer.lastSeen = now
            peer.isStale = false
        }
    }

    private func makeControlFrame(receiver: PeerID, payload: ControlMessage) -> CoreFrame {
        let frame = CoreFrame(
            type: .control,
            sender: localIdentity.peerID,
            receiver: receiver,
            sequence: nextSequence,
            payload: .control(payload)
        )
        nextSequence += 1
        return frame
    }
}

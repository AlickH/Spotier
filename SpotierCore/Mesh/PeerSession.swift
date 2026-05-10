import Foundation

enum TransportPreference: Equatable {
    case direct
    case relay
}

enum PeerSessionHealth: Equatable {
    case handshaking
    case established
    case stale
}

struct PeerSession {
    var peerID: PeerID
    var handshakeState: HandshakeState
    var crypto: SessionCrypto?
    var transportPreference: TransportPreference
    var health: PeerSessionHealth

    init(
        peerID: PeerID,
        handshakeState: HandshakeState,
        crypto: SessionCrypto? = nil,
        transportPreference: TransportPreference = .direct,
        health: PeerSessionHealth = .handshaking
    ) {
        self.peerID = peerID
        self.handshakeState = handshakeState
        self.crypto = crypto
        self.transportPreference = transportPreference
        self.health = health
    }

    mutating func establish(localIdentity: NodeIdentity) throws {
        crypto = try SessionCrypto.establish(
            localIdentity: localIdentity,
            handshake: handshakeState
        )
        health = .established
    }

    mutating func markStale() {
        health = .stale
    }
}

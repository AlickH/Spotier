import Foundation

enum HandshakeRole: Equatable {
    case initiator
    case responder
}

struct HandshakeState: Equatable {
    var network: NetworkSecret
    var localPeerID: PeerID
    var remotePeerID: PeerID
    var remotePublicKey: Data
    var role: HandshakeRole

    init(
        network: NetworkSecret,
        localPeerID: PeerID,
        remotePeerID: PeerID,
        remotePublicKey: Data,
        role: HandshakeRole
    ) {
        self.network = network
        self.localPeerID = localPeerID
        self.remotePeerID = remotePeerID
        self.remotePublicKey = remotePublicKey
        self.role = role
    }
}

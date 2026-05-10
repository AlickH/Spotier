import Foundation

struct EndpointProbe: Equatable {
    var peerID: PeerID
    var endpoint: TransportEndpoint
}

final class HolePunchCoordinator {
    private(set) var localCandidate: TransportEndpoint?
    private(set) var remoteCandidates: [PeerID: Set<TransportEndpoint>] = [:]
    private(set) var pendingProbes: [PeerID: Set<TransportEndpoint>] = [:]
    private(set) var directPeers = Set<PeerID>()
    private(set) var relayPeers = Set<PeerID>()

    func setRelayActive(for peerID: PeerID) {
        relayPeers.insert(peerID)
    }

    func publishLocalCandidate(_ endpoint: TransportEndpoint, localPeerID: PeerID, remotePeerID: PeerID) -> CoreFrame {
        localCandidate = endpoint
        return CoreFrame(
            type: .control,
            sender: localPeerID,
            receiver: remotePeerID,
            sequence: 0,
            payload: .control(.endpointCandidate("udp://\(endpoint.description)"))
        )
    }

    func receiveRemoteCandidate(_ endpoint: TransportEndpoint, from peerID: PeerID) -> [EndpointProbe] {
        remoteCandidates[peerID, default: []].insert(endpoint)
        pendingProbes[peerID, default: []].insert(endpoint)
        return [EndpointProbe(peerID: peerID, endpoint: endpoint)]
    }

    func authenticateProbeResponse(from peerID: PeerID, endpoint: TransportEndpoint) -> Bool {
        guard pendingProbes[peerID]?.contains(endpoint) == true else { return false }
        directPeers.insert(peerID)
        return true
    }

    func transportPreference(for peerID: PeerID) -> TransportPreference {
        directPeers.contains(peerID) ? .direct : .relay
    }
}

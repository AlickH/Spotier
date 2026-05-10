import Foundation

struct PeerStore: Equatable {
    private var peersByID: [PeerID: Peer] = [:]

    var peers: [Peer] {
        peersByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    mutating func upsert(_ peer: Peer) {
        peersByID[peer.id] = peer
    }

    func peer(id: PeerID) -> Peer? {
        peersByID[id]
    }

    mutating func updatePeer(id: PeerID, _ update: (inout Peer) -> Void) {
        guard var peer = peersByID[id] else { return }
        update(&peer)
        peersByID[id] = peer
    }

    mutating func markStale(now: Date, timeout: TimeInterval) -> [PeerID] {
        var staleIDs: [PeerID] = []

        for id in peersByID.keys {
            guard var peer = peersByID[id] else { continue }
            if now.timeIntervalSince(peer.lastSeen) >= timeout {
                peer.isStale = true
                peersByID[id] = peer
                staleIDs.append(id)
            }
        }

        return staleIDs
    }

    mutating func removeStalePeers() -> [PeerID] {
        let staleIDs = peersByID.values.filter(\.isStale).map(\.id)
        for id in staleIDs {
            peersByID[id] = nil
        }
        return staleIDs
    }
}

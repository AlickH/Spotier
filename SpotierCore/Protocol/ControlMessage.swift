import Foundation

enum ControlMessage: Equatable {
    case hello(Hello)
    case sessionOffer(Data)
    case sessionAnswer(Data)
    case routeUpdate(Data)
    case peerPing
    case peerPong
    case relayRequest(PeerID)
    case relayResponse(Bool)
    case endpointCandidate(String)

    struct Hello: Equatable {
        var hostname: String
        var virtualIPv4: String?
        var virtualIPv6: String?
        var publicKey: Data
        var version: String

        init(
            hostname: String,
            virtualIPv4: String?,
            virtualIPv6: String?,
            publicKey: Data,
            version: String
        ) {
            self.hostname = hostname
            self.virtualIPv4 = virtualIPv4
            self.virtualIPv6 = virtualIPv6
            self.publicKey = publicKey
            self.version = version
        }
    }
}

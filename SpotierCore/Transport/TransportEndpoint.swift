import Foundation
import Network

struct TransportEndpoint: Hashable, Equatable, CustomStringConvertible {
    var scheme: String
    var host: String
    var port: UInt16

    init(scheme: String = "udp", host: String, port: UInt16) {
        self.scheme = scheme
        self.host = host
        self.port = port
    }

    init(urlString: String) throws {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              let host = url.host,
              let port = url.port,
              port >= 0,
              port <= Int(UInt16.max) else {
            throw TransportEndpointError.invalidURL(urlString)
        }
        self.scheme = scheme
        self.host = host
        self.port = UInt16(port)
    }

    var nwEndpoint: NWEndpoint {
        .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
    }

    var description: String {
        "\(host):\(port)"
    }
}

enum TransportEndpointError: Error, Equatable {
    case invalidURL(String)
}

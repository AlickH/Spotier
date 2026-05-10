import Darwin
import Foundation

struct RunningInfoSnapshot: Codable, Equatable {
    var devName: String
    var myNodeInfo: NodeInfo?
    var events: [String]
    var routes: [Route]
    var peers: [PeerInfo]
    var peerRoutePairs: [PeerRoutePair]
    var running: Bool
    var errorMsg: String?

    enum CodingKeys: String, CodingKey {
        case devName = "dev_name"
        case myNodeInfo = "my_node_info"
        case events, routes, peers, running
        case peerRoutePairs = "peer_route_pairs"
        case errorMsg = "error_msg"
    }

    static func make(
        localIdentity: NodeIdentity?,
        configuration: MeshEngineConfiguration?,
        peerStore: PeerStore,
        routeTable: RouteTable,
        events: [MeshEngineEvent],
        running: Bool,
        errorMessage: String?
    ) -> RunningInfoSnapshot {
        let routeRows = routeTable.routes.map { route in
            Route(
                peerID: Int(route.ownerPeerID.rawValue),
                ipv4Address: IPv4CIDR(route.destination),
                ipv6Address: IPv6CIDR(route.destination),
                nextHopPeerID: Int(route.nextHopPeerID.rawValue),
                cost: route.cost,
                pathLatency: 0,
                proxyCIDRs: route.kind == .subnetProxy ? [route.destination] : [],
                hostname: peerStore.peer(id: route.ownerPeerID)?.hostname ?? "",
                instID: "",
                version: ""
            )
        }

        let peerRows = peerStore.peers.map { peer in
            PeerInfo(
                peerID: Int(peer.id.rawValue),
                connections: [
                    PeerConnectionInfo(
                        connectionID: "\(peer.id.rawValue)-direct",
                        localPeerID: Int(localIdentity?.peerID.rawValue ?? 0),
                        isClient: true,
                        peerID: Int(peer.id.rawValue),
                        features: [],
                        tunnel: nil,
                        stats: PeerConnectionStats(),
                        lossRate: 0,
                        networkName: configuration?.networkName,
                        isClosed: peer.isStale
                    )
                ],
                defaultConnectionID: nil,
                directlyConnectedConnectionIDs: []
            )
        }

        return RunningInfoSnapshot(
            devName: localIdentity?.hostname ?? "",
            myNodeInfo: localIdentity.map { NodeInfo(identity: $0) },
            events: events.map(\.runningInfoText),
            routes: routeRows,
            peers: peerRows,
            peerRoutePairs: routeRows.map { route in
                PeerRoutePair(
                    route: route,
                    peer: peerRows.first { $0.peerID == route.peerID }
                )
            },
            running: running,
            errorMsg: errorMessage
        )
    }

    func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

extension RunningInfoSnapshot {
    struct NodeInfo: Codable, Equatable {
        var virtualIPv4: IPv4CIDR?
        var hostname: String
        var version: String
        var ips: IPList?
        var stunInfo: STUNInfo?
        var listeners: [URLString]?
        var vpnPortalConfig: String?

        init(identity: NodeIdentity) {
            virtualIPv4 = identity.virtualIPv4.flatMap(IPv4CIDR.init)
            hostname = identity.hostname
            version = "swift-core"
            ips = IPList(listeners: [])
            stunInfo = STUNInfo()
            listeners = []
            vpnPortalConfig = nil
        }

        enum CodingKeys: String, CodingKey {
            case virtualIPv4 = "virtual_ipv4"
            case hostname, version, ips, listeners
            case stunInfo = "stun_info"
            case vpnPortalConfig = "vpn_portal_cfg"
        }
    }

    struct IPList: Codable, Equatable {
        var publicIPv4: IPv4Address?
        var interfaceIPv4s: [IPv4Address]?
        var publicIPv6: IPv6Address?
        var interfaceIPv6s: [IPv6Address]?
        var listeners: [URLString]?

        init(listeners: [URLString]) {
            self.listeners = listeners
        }

        enum CodingKeys: String, CodingKey {
            case publicIPv4 = "public_ipv4"
            case interfaceIPv4s = "interface_ipv4s"
            case publicIPv6 = "public_ipv6"
            case interfaceIPv6s = "interface_ipv6s"
            case listeners
        }
    }

    struct Route: Codable, Equatable {
        var peerID: Int
        var ipv4Address: IPv4CIDR?
        var ipv6Address: IPv6CIDR?
        var nextHopPeerID: Int
        var cost: Int
        var pathLatency: Int
        var proxyCIDRs: [String]
        var hostname: String
        var stunInfo: STUNInfo?
        var instID: String
        var version: String
        var nextHopPeerIDLatencyFirst: UInt?
        var costLatencyFirst: Int?
        var pathLatencyLatencyFirst: Int?
        var featureFlag: PeerFeatureFlag?

        enum CodingKeys: String, CodingKey {
            case peerID = "peer_id"
            case ipv4Address = "ipv4_addr"
            case ipv6Address = "ipv6_addr"
            case nextHopPeerID = "next_hop_peer_id"
            case cost
            case pathLatency = "path_latency"
            case proxyCIDRs = "proxy_cidrs"
            case hostname
            case stunInfo = "stun_info"
            case instID = "inst_id"
            case version
            case nextHopPeerIDLatencyFirst = "next_hop_peer_id_latency_first"
            case costLatencyFirst = "cost_latency_first"
            case pathLatencyLatencyFirst = "path_latency_latency_first"
            case featureFlag = "feature_flag"
        }
    }

    struct PeerInfo: Codable, Equatable {
        var peerID: Int
        var connections: [PeerConnectionInfo]
        var defaultConnectionID: UUIDParts?
        var directlyConnectedConnectionIDs: [UUIDParts]

        enum CodingKeys: String, CodingKey {
            case peerID = "peer_id"
            case connections = "conns"
            case defaultConnectionID = "default_conn_id"
            case directlyConnectedConnectionIDs = "directly_connected_conns"
        }
    }

    struct PeerConnectionInfo: Codable, Equatable {
        var connectionID: String
        var localPeerID: Int
        var isClient: Bool
        var peerID: Int
        var features: [String]
        var tunnel: TunnelInfo?
        var stats: PeerConnectionStats?
        var lossRate: Double
        var networkName: String?
        var isClosed: Bool?

        enum CodingKeys: String, CodingKey {
            case connectionID = "conn_id"
            case localPeerID = "my_peer_id"
            case isClient = "is_client"
            case peerID = "peer_id"
            case features, tunnel, stats
            case lossRate = "loss_rate"
            case networkName = "network_name"
            case isClosed = "is_closed"
        }
    }

    struct PeerConnectionStats: Codable, Equatable {
        var rxBytes = 0
        var txBytes = 0
        var rxPackets = 0
        var txPackets = 0
        var latencyUs = 0

        enum CodingKeys: String, CodingKey {
            case rxBytes = "rx_bytes"
            case txBytes = "tx_bytes"
            case rxPackets = "rx_packets"
            case txPackets = "tx_packets"
            case latencyUs = "latency_us"
        }
    }

    struct PeerRoutePair: Codable, Equatable {
        var route: Route
        var peer: PeerInfo?
    }

    struct TunnelInfo: Codable, Equatable {
        var tunnelType: String
        var localAddress: URLString
        var remoteAddress: URLString

        enum CodingKeys: String, CodingKey {
            case tunnelType = "tunnel_type"
            case localAddress = "local_addr"
            case remoteAddress = "remote_addr"
        }
    }

    struct STUNInfo: Codable, Equatable {
        var udpNATType = 0
        var tcpNATType = 0
        var lastUpdateTime: TimeInterval = 0
        var publicIPs: [String] = []
        var minPort: Int?
        var maxPort: Int?

        enum CodingKeys: String, CodingKey {
            case udpNATType = "udp_nat_type"
            case tcpNATType = "tcp_nat_type"
            case lastUpdateTime = "last_update_time"
            case publicIPs = "public_ip"
            case minPort = "min_port"
            case maxPort = "max_port"
        }
    }

    struct PeerFeatureFlag: Codable, Equatable {
        var isPublicServer = false
        var avoidRelayData = false
        var kcpInput = false
        var noRelayKcp = false
        var supportConnectionListSync = false

        enum CodingKeys: String, CodingKey {
            case isPublicServer = "is_public_server"
            case avoidRelayData = "avoid_relay_data"
            case kcpInput = "kcp_input"
            case noRelayKcp = "no_relay_kcp"
            case supportConnectionListSync = "support_conn_list_sync"
        }
    }

    struct URLString: Codable, Equatable {
        var url: String
    }

    struct UUIDParts: Codable, Equatable {
        var part1: UInt32
        var part2: UInt32
        var part3: UInt32
        var part4: UInt32
    }

    struct IPv4CIDR: Codable, Equatable {
        var address: IPv4Address
        var networkLength: Int

        init?(_ cidr: String) {
            let parts = cidr.split(separator: "/", maxSplits: 1).map(String.init)
            let addressString = parts[0]
            let length = parts.count == 2 ? Int(parts[1]) : 32

            guard let address = IPv4Address(addressString),
                  let length,
                  (0...32).contains(length) else {
                return nil
            }

            self.address = address
            networkLength = length
        }

        enum CodingKeys: String, CodingKey {
            case address
            case networkLength = "network_length"
        }
    }

    struct IPv4Address: Codable, Equatable {
        var addr: UInt32

        init?(_ string: String) {
            let bytes = string.split(separator: ".").compactMap { UInt32($0) }
            guard bytes.count == 4 else { return nil }
            addr = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
        }
    }

    struct IPv6CIDR: Codable, Equatable {
        var address: IPv6Address
        var networkLength: Int

        init?(_ cidr: String) {
            let parts = cidr.split(separator: "/", maxSplits: 1).map(String.init)
            let addressString = parts[0]
            let length = parts.count == 2 ? Int(parts[1]) : 128

            guard let address = IPv6Address(addressString),
                  let length,
                  (0...128).contains(length) else {
                return nil
            }

            self.address = address
            networkLength = length
        }

        enum CodingKeys: String, CodingKey {
            case address
            case networkLength = "network_length"
        }
    }

    struct IPv6Address: Codable, Equatable {
        var part1: UInt32
        var part2: UInt32
        var part3: UInt32
        var part4: UInt32

        init?(_ string: String) {
            var addr = in6_addr()
            guard inet_pton(AF_INET6, string, &addr) == 1 else {
                return nil
            }

            let data = withUnsafeBytes(of: addr) { Data($0) }
            part1 = data.readUInt32(at: 0)
            part2 = data.readUInt32(at: 4)
            part3 = data.readUInt32(at: 8)
            part4 = data.readUInt32(at: 12)
        }
    }
}

private extension MeshEngineEvent {
    var runningInfoText: String {
        switch self {
        case .statusChanged(let status):
            return "status_changed: \(status)"
        case .peerChanged:
            return "peer_changed"
        case .routeChanged:
            return "route_changed"
        case .logLine(let line):
            return line
        case .fatalError(let message):
            return "fatal_error: \(message)"
        }
    }
}

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }
}

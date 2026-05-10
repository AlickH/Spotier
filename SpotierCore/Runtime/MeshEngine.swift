import Foundation

final class MeshEngine {
    let outboundPackets: AsyncStream<PacketTunnelPacket>

    private(set) var status: MeshEngineStatus = .stopped
    private(set) var configuration: MeshEngineConfiguration?
    private(set) var events: [MeshEngineEvent] = []
    private(set) var localIdentity: NodeIdentity?
    private(set) var peerStore = PeerStore()
    private(set) var routeTable = RouteTable()
    private var transport: (any Transport)?
    private var outboundPacketContinuation: AsyncStream<PacketTunnelPacket>.Continuation?

    init() {
        let stream = AsyncStream<PacketTunnelPacket>.makeStream()
        outboundPackets = stream.stream
        outboundPacketContinuation = stream.continuation
    }

    func start(configuration: MeshEngineConfiguration) async throws {
        try configuration.validate()
        setStatus(.starting)
        self.configuration = configuration
        localIdentity = try NodeIdentity.derive(
            network: NetworkSecret(
                networkName: configuration.networkName,
                secret: configuration.networkSecret
            ),
            deviceSeed: Data("spotier.swift.core.device".utf8),
            hostname: Host.current().localizedName ?? "spotier",
            virtualIPv4: configuration.virtualIPv4,
            virtualIPv6: configuration.virtualIPv6
        )

        do {
            if let udpPort = try configuredUDPPort(from: configuration.listeners) {
                let transport = UDPTransport(bindPort: udpPort)
                try await transport.start()
                self.transport = transport
            }
            setStatus(.running)
        } catch {
            let message = String(describing: error)
            setStatus(.failed(message))
            events.append(.fatalError(message))
            throw error
        }
    }

    func stop() async {
        guard status != .stopped else { return }
        setStatus(.stopping)
        await transport?.stop()
        transport = nil
        configuration = nil
        localIdentity = nil
        setStatus(.stopped)
    }

    func sendProviderCommand(_ command: String) -> Data? {
        guard command == "running_info" else {
            return nil
        }

        let json = #"{"dev_name":"","events":[],"routes":[],"peers":[],"peer_route_pairs":[],"running":\#(status == .running)}"#
        return json.data(using: .utf8)
    }

    func runningInfoData() -> Data? {
        let snapshot = RunningInfoSnapshot.make(
            localIdentity: localIdentity,
            configuration: configuration,
            peerStore: peerStore,
            routeTable: routeTable,
            events: events,
            running: status == .running,
            errorMessage: errorMessage
        )
        return try? snapshot.jsonData()
    }

    func receivePacket(_ packet: PacketTunnelPacket) async {
        do {
            _ = try PacketClassifier.parse(packet.data)
        } catch {
            events.append(.logLine("Dropped non-IP packet"))
        }
    }

    func emitPacket(_ packet: PacketTunnelPacket) {
        outboundPacketContinuation?.yield(packet)
    }

    private func configuredUDPPort(from listeners: [String]) throws -> UInt16? {
        for listener in listeners {
            guard URL(string: listener)?.scheme == "udp" else { continue }
            return try TransportEndpoint(urlString: listener).port
        }
        return nil
    }

    private func setStatus(_ newStatus: MeshEngineStatus) {
        status = newStatus
        events.append(.statusChanged(newStatus))
    }

    private var errorMessage: String? {
        if case .failed(let message) = status {
            return message
        }
        return nil
    }
}

import Foundation

final class MeshEngine {
    let outboundPackets: AsyncStream<PacketTunnelPacket>

    private(set) var status: MeshEngineStatus = .stopped
    private(set) var configuration: MeshEngineConfiguration?
    private(set) var events: [MeshEngineEvent] = []
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
        setStatus(.stopped)
    }

    func sendProviderCommand(_ command: String) -> Data? {
        guard command == "running_info" else {
            return nil
        }

        let json = #"{"dev_name":"","events":[],"routes":[],"peers":[],"peer_route_pairs":[],"running":\#(status == .running)}"#
        return json.data(using: .utf8)
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
}

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
    private let injectedTransport: (any Transport)?
    private let deviceSeed: Data
    private var outboundPacketContinuation: AsyncStream<PacketTunnelPacket>.Continuation?
    private var peerManager: PeerManager?
    private var transportReadTask: Task<Void, Never>?
    private var nextSequence: UInt64 = 1

    init(transport: (any Transport)? = nil, deviceSeed: Data = Data("spotier.swift.core.device".utf8)) {
        injectedTransport = transport
        self.deviceSeed = deviceSeed
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
            deviceSeed: deviceSeed,
            hostname: Host.current().localizedName ?? "spotier",
            virtualIPv4: configuration.virtualIPv4,
            virtualIPv6: configuration.virtualIPv6
        )
        guard let localIdentity else { return }
        peerManager = PeerManager(
            localIdentity: localIdentity,
            network: NetworkSecret(
                networkName: configuration.networkName,
                secret: configuration.networkSecret
            )
        )

        do {
            if let injectedTransport {
                try await injectedTransport.start()
                transport = injectedTransport
            } else if let udpPort = try configuredUDPPort(from: configuration.listeners) {
                let transport = UDPTransport(bindPort: udpPort)
                try await transport.start()
                self.transport = transport
            }
            startTransportReader()
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
        transportReadTask?.cancel()
        transportReadTask = nil
        await transport?.stop()
        transport = nil
        configuration = nil
        localIdentity = nil
        peerManager = nil
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
            let parsedPacket = try PacketClassifier.parse(packet.data)
            let decision = PacketRouter(
                routeTable: routeTable,
                localIPv4: localIdentity?.virtualIPv4,
                localIPv6: localIdentity?.virtualIPv6
            ).route(parsedPacket)
            try await forward(packet, decision: decision)
        } catch {
            events.append(.logLine("Dropped non-IP packet"))
        }
    }

    func emitPacket(_ packet: PacketTunnelPacket) {
        outboundPacketContinuation?.yield(packet)
    }

    func hasEstablishedSession(with peerID: PeerID) -> Bool {
        peerManager?.session(for: peerID)?.health == .established
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

    private func startTransportReader() {
        guard let transport else { return }
        transportReadTask = Task {
            for await inbound in transport.inboundFrames {
                await receive(inbound)
            }
        }
    }

    private func receive(_ inbound: TransportInboundFrame) async {
        do {
            switch inbound.frame.payload {
            case .control:
                let responses = try peerManager?.receive(inbound) ?? []
                syncPeerState()
                if case .control(.hello) = inbound.frame.payload,
                   let peer = peerStore.peer(id: inbound.frame.sender) {
                    RouteCalculator.apply(peer: peer, to: &routeTable)
                    events.append(.routeChanged)
                }
                for response in responses {
                    try await transport?.send(response, to: inbound.remoteEndpoint)
                }
            case .data(let packet):
                guard let session = peerManager?.session(for: inbound.frame.sender),
                      let crypto = session.crypto else {
                    return
                }
                let plaintext = try crypto.decrypt(
                    sequence: inbound.frame.sequence,
                    ciphertext: packet.encryptedIPPacket
                )
                emitPacket(PacketTunnelPacket(data: plaintext, protocolFamily: protocolFamily(for: plaintext)))
            }
        } catch {
            events.append(.logLine("Dropped inbound frame"))
        }
    }

    private func syncPeerState() {
        guard let manager = peerManager else { return }
        peerStore = manager.peerStore
    }

    private func forward(_ packet: PacketTunnelPacket, decision: PacketRouteDecision) async throws {
        let peerID: PeerID
        switch decision {
        case .local:
            emitPacket(packet)
            return
        case .peer(let id), .subnetProxy(let id):
            peerID = id
        case .drop:
            events.append(.logLine("Dropped unrouted packet"))
            return
        }

        guard let localIdentity,
              let session = peerManager?.session(for: peerID),
              let crypto = session.crypto,
              let endpoint = peerStore.peer(id: peerID)?.knownEndpoints.first else {
            events.append(.logLine("Dropped packet without established peer session"))
            return
        }

        let sequence = nextSequence
        nextSequence += 1
        let encrypted = try crypto.encrypt(sequence: sequence, plaintext: packet.data)
        let frame = CoreFrame(
            type: .data,
            sender: localIdentity.peerID,
            receiver: peerID,
            sequence: sequence,
            payload: .data(DataPacket(encryptedIPPacket: encrypted))
        )
        try await transport?.send(frame, to: endpoint)
    }

    private func protocolFamily(for packet: Data) -> Int32 {
        guard let firstByte = packet.first else { return AF_UNSPEC }
        switch firstByte >> 4 {
        case 4:
            return AF_INET
        case 6:
            return AF_INET6
        default:
            return AF_UNSPEC
        }
    }

    private var errorMessage: String? {
        if case .failed(let message) = status {
            return message
        }
        return nil
    }
}

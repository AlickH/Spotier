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
    private var advertisedRoutePeers = Set<PeerID>()
    private var endpointCandidatePeers = Set<PeerID>()
    private var peerTrafficStats: [PeerID: RunningInfoSnapshot.PeerConnectionStats] = [:]
    private var pendingLatencyPings: [PeerID: Date] = [:]

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
            hostname: configuration.instanceName ?? Host.current().localizedName ?? "spotier",
            virtualIPv4: configuration.virtualIPv4,
            virtualIPv6: configuration.virtualIPv6
        )
        guard let localIdentity else { return }
        peerManager = PeerManager(
            localIdentity: localIdentity,
            network: NetworkSecret(
                networkName: configuration.networkName,
                secret: configuration.networkSecret
            ),
            udpHolePunchingEnabled: !configuration.disableP2P && !configuration.disableUDPHolePunching
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
            try await sendBootstrapHello(to: configuration.peers)
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
        peerStore = PeerStore()
        routeTable = RouteTable()
        peerTrafficStats.removeAll()
        pendingLatencyPings.removeAll()
        nextSequence = 1
        advertisedRoutePeers.removeAll()
        endpointCandidatePeers.removeAll()
        setStatus(.stopped)
    }

    func sendProviderCommand(_ command: String) -> Data? {
        guard command == "running_info" else {
            return nil
        }

        return runningInfoData()
    }

    func runningInfoData() -> Data? {
        let snapshot = RunningInfoSnapshot.make(
            localIdentity: localIdentity,
            configuration: configuration,
            peerStore: peerStore,
            routeTable: routeTable,
            events: events,
            running: status == .running,
            errorMessage: errorMessage,
            peerTrafficStats: peerTrafficStats
        )
        return try? snapshot.jsonData()
    }

    func receivePacket(_ packet: PacketTunnelPacket) async {
        do {
            if let response = magicDNSResponse(to: packet.data) {
                emitPacket(PacketTunnelPacket(data: response, protocolFamily: AF_INET))
                return
            }
            let parsedPacket = try PacketClassifier.parse(packet.data)
            let decision = PacketRouter(
                routeTable: routeTable,
                localIPv4: localIdentity?.virtualIPv4,
                localIPv6: localIdentity?.virtualIPv6,
                exitNodes: configuration?.exitNodes ?? [],
                p2pOnly: configuration?.p2pOnly == true
            ).route(parsedPacket)
            try await forward(packet, decision: decision)
        } catch {
            events.append(.logLine("Dropped non-IP packet"))
        }
    }

    private func magicDNSResponse(to packet: Data) -> Data? {
        guard configuration?.magicDNS == true else { return nil }
        let responder = MagicDNSResponder(
            resolverIPv4: "100.100.100.101",
            zone: configuration?.magicDNSZone ?? "et.net",
            records: MagicDNSResponder.records(localIdentity: localIdentity, peerStore: peerStore)
        )
        return responder.response(to: packet)
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

    private func sendBootstrapHello(to peers: [String]) async throws {
        guard let transport, let peerManager else { return }
        for peer in peers {
            let endpoint = try TransportEndpoint(urlString: peer)
            try await transport.send(peerManager.makeHelloFrame(), to: endpoint)
        }
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
            guard acceptsFrameReceiver(inbound.frame) else {
                events.append(.logLine("Dropped frame addressed to another peer"))
                return
            }
            switch inbound.frame.payload {
            case .control:
                let responses = try peerManager?.receive(inbound) ?? []
                syncPeerState()
                if case .control(.peerPong) = inbound.frame.payload {
                    recordLatencyPong(from: inbound.frame.sender)
                }
                if case .control(.routeUpdate(let payload)) = inbound.frame.payload {
                    guard peerManager?.session(for: inbound.frame.sender)?.health == .established else {
                        events.append(.logLine("Dropped unauthenticated route update"))
                        return
                    }
                    let update = try RouteUpdate(wireData: payload, sender: inbound.frame.sender)
                    routeTable.apply(update)
                    events.append(.routeChanged)
                }
                if case .control(.hello) = inbound.frame.payload,
                   let peer = peerStore.peer(id: inbound.frame.sender) {
                    RouteCalculator.apply(peer: peer, to: &routeTable)
                    events.append(.routeChanged)
                }
                for response in responses {
                    try await transport?.send(response, to: inbound.remoteEndpoint)
                }
                try await sendEndpointCandidateIfNeeded(to: inbound.frame.sender, endpoint: inbound.remoteEndpoint)
                try await sendAdvertisedRoutesIfNeeded(to: inbound.frame.sender, endpoint: inbound.remoteEndpoint)
                try await sendLatencyPingIfNeeded(to: inbound.frame.sender, endpoint: inbound.remoteEndpoint)
            case .data(let packet):
                guard let session = peerManager?.session(for: inbound.frame.sender),
                      let crypto = session.crypto else {
                    return
                }
                let plaintext = try crypto.decrypt(
                    sequence: inbound.frame.sequence,
                    ciphertext: packet.encryptedIPPacket
                )
                guard shouldAcceptDataFrame(inbound.frame) else {
                    events.append(.logLine("Dropped disabled exit-node packet"))
                    return
                }
                recordReceivedPacket(from: inbound.frame.sender, byteCount: plaintext.count)
                emitPacket(PacketTunnelPacket(data: plaintext, protocolFamily: protocolFamily(for: plaintext)))
            }
        } catch {
            events.append(.logLine("Dropped inbound frame"))
        }
    }

    private func acceptsFrameReceiver(_ frame: CoreFrame) -> Bool {
        if frame.receiver == localIdentity?.peerID {
            return true
        }
        if frame.receiver == PeerID(0), case .control(.hello) = frame.payload {
            return true
        }
        return false
    }

    private func sendAdvertisedRoutes(to peerID: PeerID, endpoint: TransportEndpoint) async throws {
        guard let localIdentity, let configuration, !configuration.advertisedRoutes.isEmpty else { return }
        let update = RouteUpdate(
            peerID: localIdentity.peerID,
            ipv4Address: localIdentity.virtualIPv4,
            ipv6Address: localIdentity.virtualIPv6,
            nextHopPeerID: localIdentity.peerID,
            cost: 1,
            proxyCIDRs: configuration.advertisedRoutes
        )
        let frame = CoreFrame(
            type: .control,
            sender: localIdentity.peerID,
            receiver: peerID,
            sequence: nextSequence,
            payload: .control(.routeUpdate(try update.wireData()))
        )
        nextSequence += 1
        try await transport?.send(frame, to: endpoint)
    }

    private func sendAdvertisedRoutesIfNeeded(to peerID: PeerID, endpoint: TransportEndpoint) async throws {
        guard advertisedRoutePeers.contains(peerID) == false,
              peerManager?.session(for: peerID)?.health == .established else {
            return
        }
        try await sendAdvertisedRoutes(to: peerID, endpoint: endpoint)
        advertisedRoutePeers.insert(peerID)
    }

    private func sendEndpointCandidateIfNeeded(to peerID: PeerID, endpoint: TransportEndpoint) async throws {
        guard endpointCandidatePeers.contains(peerID) == false,
              peerManager?.session(for: peerID)?.health == .established,
              let candidate = try configuredUDPEndpoint() else {
            return
        }
        guard var frame = peerManager?.publishEndpointCandidate(candidate, to: peerID) else { return }
        frame.sequence = nextSequence
        nextSequence += 1
        try await transport?.send(frame, to: endpoint)
        endpointCandidatePeers.insert(peerID)
    }

    private func configuredUDPEndpoint() throws -> TransportEndpoint? {
        let candidates = (configuration?.mappedListeners ?? []) + (configuration?.listeners ?? [])
        guard let listener = candidates.first(where: { URL(string: $0)?.scheme == "udp" }) else {
            return nil
        }
        return try TransportEndpoint(urlString: listener)
    }

    private func syncPeerState() {
        guard let manager = peerManager else { return }
        peerStore = manager.peerStore
    }

    private func shouldAcceptDataFrame(_ frame: CoreFrame) -> Bool {
        if (frame.flags & CoreFrame.exitNodeFlag) == 0 {
            return true
        }
        return configuration?.enableExitNode == true
    }

    private func forward(_ packet: PacketTunnelPacket, decision: PacketRouteDecision) async throws {
        let peerID: PeerID
        let frameFlags: UInt16
        switch decision {
        case .local:
            emitPacket(packet)
            return
        case .peer(let id), .subnetProxy(let id):
            peerID = id
            frameFlags = 0
        case .exitNode(let id):
            peerID = id
            frameFlags = CoreFrame.exitNodeFlag
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
            flags: frameFlags,
            sender: localIdentity.peerID,
            receiver: peerID,
            sequence: sequence,
            payload: .data(DataPacket(encryptedIPPacket: encrypted))
        )
        try await transport?.send(frame, to: endpoint)
        recordSentPacket(to: peerID, byteCount: packet.data.count)
    }

    private func sendLatencyPingIfNeeded(to peerID: PeerID, endpoint: TransportEndpoint) async throws {
        guard peerManager?.session(for: peerID)?.health == .established,
              pendingLatencyPings[peerID] == nil,
              (peerTrafficStats[peerID]?.latencyUs ?? 0) == 0,
              let localIdentity else {
            return
        }

        let frame = CoreFrame(
            type: .control,
            sender: localIdentity.peerID,
            receiver: peerID,
            sequence: nextSequence,
            payload: .control(.peerPing)
        )
        pendingLatencyPings[peerID] = Date()
        nextSequence += 1
        try await transport?.send(frame, to: endpoint)
    }

    private func recordLatencyPong(from peerID: PeerID) {
        guard let startedAt = pendingLatencyPings.removeValue(forKey: peerID) else { return }
        let latencyUs = max(1, Int(Date().timeIntervalSince(startedAt) * 1_000_000))
        var stats = peerTrafficStats[peerID] ?? RunningInfoSnapshot.PeerConnectionStats()
        stats.latencyUs = latencyUs
        peerTrafficStats[peerID] = stats
    }

    private func recordSentPacket(to peerID: PeerID, byteCount: Int) {
        var stats = peerTrafficStats[peerID] ?? RunningInfoSnapshot.PeerConnectionStats()
        stats.txBytes += byteCount
        stats.txPackets += 1
        peerTrafficStats[peerID] = stats
    }

    private func recordReceivedPacket(from peerID: PeerID, byteCount: Int) {
        var stats = peerTrafficStats[peerID] ?? RunningInfoSnapshot.PeerConnectionStats()
        stats.rxBytes += byteCount
        stats.rxPackets += 1
        peerTrafficStats[peerID] = stats
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

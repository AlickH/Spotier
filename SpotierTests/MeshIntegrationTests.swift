import Foundation
import XCTest
@testable import Spotier

final class MeshIntegrationTests: XCTestCase {
    func testLocalMeshTransfersIPv4AndIPv6Packets() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "node-a", port: 10001))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "node-b", port: 10002))
        transportA.connect(to: transportB)

        let engineA = MeshEngine(
            transport: transportA,
            deviceSeed: Data(repeating: 1, count: 32)
        )
        let engineB = MeshEngine(
            transport: transportB,
            deviceSeed: Data(repeating: 2, count: 32)
        )
        defer {
            Task {
                await engineA.stop()
                await engineB.stop()
            }
        }

        try await engineA.start(configuration: configuration(ipv4: "10.0.0.1/24", ipv6: "fd00:0:0:0:0:0:0:1"))
        try await engineB.start(configuration: configuration(ipv4: "10.0.0.2/24", ipv6: "fd00:0:0:0:0:0:0:2"))

        try await exchangeHello(from: engineA, transport: transportA, to: engineB, endpoint: transportB.endpoint)
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
        try await waitUntil(engineB.sessionEstablished(with: engineA), timeout: .milliseconds(500))

        let ipv4 = ipv4Packet(source: [10, 0, 0, 1], destination: [10, 0, 0, 2])
        var outputB = engineB.outboundPackets.makeAsyncIterator()

        await engineA.receivePacket(PacketTunnelPacket(data: ipv4, protocolFamily: AF_INET))

        let receivedIPv4 = await withTimeout(milliseconds: 500) {
            await outputB.next()
        }
        XCTAssertEqual(receivedIPv4, PacketTunnelPacket(data: ipv4, protocolFamily: AF_INET))

        let ipv6 = ipv6Packet(
            source: [0xfd00, 0, 0, 0, 0, 0, 0, 2],
            destination: [0xfd00, 0, 0, 0, 0, 0, 0, 1]
        )
        var outputA = engineA.outboundPackets.makeAsyncIterator()

        await engineB.receivePacket(PacketTunnelPacket(data: ipv6, protocolFamily: AF_INET6))

        let receivedIPv6 = await withTimeout(milliseconds: 500) {
            await outputA.next()
        }
        XCTAssertEqual(receivedIPv6, PacketTunnelPacket(data: ipv6, protocolFamily: AF_INET6))
    }

    func testConfiguredPeerReceivesBootstrapHelloOnStart() async throws {
        let serverTransport = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19110))
        let clientTransport = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19111))
        clientTransport.connect(to: serverTransport)
        let client = MeshEngine(transport: clientTransport)
        var iterator = serverTransport.inboundFrames.makeAsyncIterator()

        try await client.start(configuration: MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.10.0.1/24",
            peers: ["udp://127.0.0.1:19110"],
            listeners: ["udp://127.0.0.1:19111"]
        ))
        defer {
            Task { await client.stop() }
        }

        let inbound = await withTimeout(milliseconds: 100) {
            await iterator.next()
        }

        XCTAssertEqual(inbound?.remoteEndpoint, clientTransport.endpoint)
        guard case .control(.hello) = inbound?.frame.payload else {
            XCTFail("Expected bootstrap hello frame")
            return
        }
    }

    func testEngineUsesConfiguredInstanceNameAsLocalHostname() async throws {
        let engine = MeshEngine()
        try await engine.start(configuration: MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            instanceName: "office-node"
        ))
        defer {
            Task { await engine.stop() }
        }

        XCTAssertEqual(engine.localIdentity?.hostname, "office-node")
    }

    func testOneWayConfiguredPeerEstablishesRouteAndTransfersPacket() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19120))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19121))
        transportA.connect(to: transportB)
        let engineA = MeshEngine(transport: transportA, deviceSeed: Data(repeating: 1, count: 32))
        let engineB = MeshEngine(transport: transportB, deviceSeed: Data(repeating: 2, count: 32))
        defer {
            Task {
                await engineA.stop()
                await engineB.stop()
            }
        }

        try await engineB.start(configuration: configuration(ipv4: "10.0.0.2/24", ipv6: "fd00:0:0:0:0:0:0:2"))
        try await engineA.start(configuration: MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.0.0.1/24",
            virtualIPv6: "fd00:0:0:0:0:0:0:1",
            peers: ["udp://127.0.0.1:19121"],
            listeners: ["udp://127.0.0.1:19120"],
            mtu: 1380
        ))
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
        try await waitUntil(engineB.sessionEstablished(with: engineA), timeout: .milliseconds(500))

        let ipv4 = ipv4Packet(source: [10, 0, 0, 1], destination: [10, 0, 0, 2])
        var outputB = engineB.outboundPackets.makeAsyncIterator()

        await engineA.receivePacket(PacketTunnelPacket(data: ipv4, protocolFamily: AF_INET))

        let receivedIPv4 = await withTimeout(milliseconds: 500) {
            await outputB.next()
        }
        XCTAssertEqual(receivedIPv4, PacketTunnelPacket(data: ipv4, protocolFamily: AF_INET))
    }

    func testRouteUpdateInstallsSubnetProxyRoute() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19130))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19131))
        transportA.connect(to: transportB)
        let engineA = MeshEngine(transport: transportA, deviceSeed: Data(repeating: 1, count: 32))
        let engineB = MeshEngine(transport: transportB, deviceSeed: Data(repeating: 2, count: 32))
        defer {
            Task {
                await engineA.stop()
                await engineB.stop()
            }
        }

        try await engineA.start(configuration: configuration(ipv4: "10.0.0.1/24", ipv6: "fd00:0:0:0:0:0:0:1"))
        try await engineB.start(configuration: configuration(ipv4: "10.0.0.2/24", ipv6: "fd00:0:0:0:0:0:0:2"))
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)
        let updatePayload = routeUpdatePayload(
            ipv4Address: "10.0.0.2",
            ipv6Address: nil,
            cost: 2,
            proxyCIDRs: ["192.168.77.0/24"]
        )
        try await transportB.send(CoreFrame(
            type: .control,
            sender: try XCTUnwrap(engineB.localIdentity?.peerID),
            receiver: try XCTUnwrap(engineA.localIdentity?.peerID),
            sequence: 50,
            payload: .control(.routeUpdate(updatePayload))
        ), to: transportA.endpoint)

        try await waitUntil(engineA.routeTable.bestRoute(for: "192.168.77.9") != nil, timeout: .milliseconds(500))

        XCTAssertEqual(engineA.routeTable.bestRoute(for: "192.168.77.9")?.ownerPeerID, engineB.localIdentity?.peerID)
        XCTAssertEqual(engineA.routeTable.bestRoute(for: "192.168.77.9")?.cost, 2)
    }

    func testStopClearsMeshStateFromRunningInfo() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19140))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19141))
        transportA.connect(to: transportB)
        let engineA = MeshEngine(transport: transportA, deviceSeed: Data(repeating: 1, count: 32))
        let engineB = MeshEngine(transport: transportB, deviceSeed: Data(repeating: 2, count: 32))
        defer {
            Task { await engineB.stop() }
        }

        try await engineA.start(configuration: configuration(ipv4: "10.0.0.1/24", ipv6: "fd00:0:0:0:0:0:0:1"))
        try await engineB.start(configuration: configuration(ipv4: "10.0.0.2/24", ipv6: "fd00:0:0:0:0:0:0:2"))
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)
        try await waitUntil(engineA.routeTable.bestRoute(for: "10.0.0.2") != nil, timeout: .milliseconds(500))

        await engineA.stop()

        let data = try XCTUnwrap(engineA.runningInfoData())
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["running"] as? Bool, false)
        XCTAssertNil(json?["my_node_info"] as? [String: Any])
        XCTAssertEqual((json?["peers"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((json?["routes"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((json?["peer_route_pairs"] as? [[String: Any]])?.count, 0)
    }

    func testAdvertisedRoutesAreSentAfterSessionEstablishes() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19150))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19151))
        transportA.connect(to: transportB)
        let engineA = MeshEngine(transport: transportA, deviceSeed: Data(repeating: 1, count: 32))
        let engineB = MeshEngine(transport: transportB, deviceSeed: Data(repeating: 2, count: 32))
        defer {
            Task {
                await engineA.stop()
                await engineB.stop()
            }
        }

        try await engineA.start(configuration: MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.0.0.1/24",
            virtualIPv6: "fd00:0:0:0:0:0:0:1",
            advertisedRoutes: ["192.168.55.0/24"],
            mtu: 1380
        ))
        try await engineB.start(configuration: configuration(ipv4: "10.0.0.2/24", ipv6: "fd00:0:0:0:0:0:0:2"))
        try await exchangeHello(from: engineA, transport: transportA, to: engineB, endpoint: transportB.endpoint)
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
        try await waitUntil(engineB.sessionEstablished(with: engineA), timeout: .milliseconds(500))
        try await waitUntil(engineB.routeTable.bestRoute(for: "192.168.55.8") != nil, timeout: .milliseconds(500))

        XCTAssertEqual(engineB.routeTable.bestRoute(for: "192.168.55.8")?.ownerPeerID, engineA.localIdentity?.peerID)
        XCTAssertEqual(engineB.routeTable.bestRoute(for: "192.168.55.8")?.kind, .subnetProxy)
    }

    private func routeUpdatePayload(
        ipv4Address: String?,
        ipv6Address: String?,
        cost: Int,
        proxyCIDRs: [String]
    ) -> Data {
        var data = Data()
        appendOptionalString(ipv4Address, to: &data)
        appendOptionalString(ipv6Address, to: &data)
        data.append(UInt8(cost))
        data.append(UInt8(proxyCIDRs.count))
        for cidr in proxyCIDRs {
            appendString(cidr, to: &data)
        }
        return data
    }

    private func appendOptionalString(_ value: String?, to data: inout Data) {
        guard let value else {
            data.append(0)
            return
        }
        data.append(1)
        appendString(value, to: &data)
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        data.append(UInt8((bytes.count >> 8) & 0xFF))
        data.append(UInt8(bytes.count & 0xFF))
        data.append(bytes)
    }

    private func configuration(ipv4: String, ipv6: String) -> MeshEngineConfiguration {
        MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: ipv4,
            virtualIPv6: ipv6,
            mtu: 1380
        )
    }

    private func exchangeHello(
        from engine: MeshEngine,
        transport: InMemoryTransport,
        to remote: MeshEngine,
        endpoint: TransportEndpoint
    ) async throws {
        guard let identity = engine.localIdentity else {
            XCTFail("Missing local identity")
            return
        }
        let frame = CoreFrame(
            type: .control,
            sender: identity.peerID,
            receiver: PeerID(0),
            sequence: 1,
            payload: .control(.hello(ControlMessage.Hello(
                hostname: identity.hostname,
                virtualIPv4: identity.virtualIPv4,
                virtualIPv6: identity.virtualIPv6,
                publicKey: identity.publicKey
            )))
        )
        try await transport.send(frame, to: endpoint)
        try await waitUntil(remote.peerStore.peer(id: identity.peerID) != nil, timeout: .milliseconds(500))
    }

    private func ipv4Packet(source: [UInt8], destination: [UInt8]) -> Data {
        var data = Data([
            0x45, 0x00,
            0x00, 0x14,
            0x00, 0x00, 0x00, 0x00,
            64, 17,
            0x00, 0x00
        ])
        data.append(contentsOf: source)
        data.append(contentsOf: destination)
        return data
    }

    private func ipv6Packet(source: [UInt16], destination: [UInt16]) -> Data {
        var data = Data([0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 58, 64])
        appendIPv6(source, to: &data)
        appendIPv6(destination, to: &data)
        return data
    }

    private func appendIPv6(_ groups: [UInt16], to data: inout Data) {
        for group in groups {
            data.append(UInt8(group >> 8))
            data.append(UInt8(group & 0xFF))
        }
    }
}

private extension MeshEngine {
    func sessionEstablished(with remote: MeshEngine) -> Bool {
        guard let peerID = remote.localIdentity?.peerID else { return false }
        return hasEstablishedSession(with: peerID)
    }
}

private func waitUntil(
    _ condition: @autoclosure @escaping () -> Bool,
    timeout: Duration
) async throws {
    let start = ContinuousClock.now
    while !condition() {
        if ContinuousClock.now - start > timeout {
            XCTFail("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private func withTimeout<T>(
    milliseconds: UInt64,
    operation: @escaping () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operation()
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

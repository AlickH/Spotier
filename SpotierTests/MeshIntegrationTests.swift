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

    func testRunningInfoAccumulatesPeerTrafficStats() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "node-a", port: 10003))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "node-b", port: 10004))
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
        try await exchangeHello(from: engineA, transport: transportA, to: engineB, endpoint: transportB.endpoint)
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
        try await waitUntil(engineB.sessionEstablished(with: engineA), timeout: .milliseconds(500))

        let packet = ipv4Packet(source: [10, 0, 0, 1], destination: [10, 0, 0, 2])
        var outputB = engineB.outboundPackets.makeAsyncIterator()

        await engineA.receivePacket(PacketTunnelPacket(data: packet, protocolFamily: AF_INET))
        _ = await withTimeout(milliseconds: 500) {
            await outputB.next()
        }

        let statsA = try XCTUnwrap(peerStats(from: engineA))
        let statsB = try XCTUnwrap(peerStats(from: engineB))
        XCTAssertEqual(statsA["tx_bytes"] as? Int, packet.count)
        XCTAssertEqual(statsA["tx_packets"] as? Int, 1)
        XCTAssertEqual(statsA["rx_bytes"] as? Int, 0)
        XCTAssertEqual(statsB["rx_bytes"] as? Int, packet.count)
        XCTAssertEqual(statsB["rx_packets"] as? Int, 1)
        XCTAssertEqual(statsB["tx_bytes"] as? Int, 0)
    }

    func testRunningInfoUpdatesLatencyFromPeerPingPong() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "node-a", port: 10005))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "node-b", port: 10006))
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
        try await exchangeHello(from: engineA, transport: transportA, to: engineB, endpoint: transportB.endpoint)
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)

        try await waitUntil((try? self.peerLatency(from: engineA)) ?? 0 > 0, timeout: .milliseconds(500))
        try await waitUntil((try? self.peerLatency(from: engineB)) ?? 0 > 0, timeout: .milliseconds(500))
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

    func testMagicDNSQueryEmitsLocalDNSResponse() async throws {
        let engine = MeshEngine(deviceSeed: Data(repeating: 1, count: 32))
        try await engine.start(configuration: MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            instanceName: "local",
            virtualIPv4: "10.0.0.1/24",
            magicDNS: true,
            magicDNSZone: "et.net"
        ))
        defer {
            Task { await engine.stop() }
        }
        var output = engine.outboundPackets.makeAsyncIterator()

        await engine.receivePacket(PacketTunnelPacket(
            data: dnsQueryPacket(name: "local.et.net", sourcePort: 53001),
            protocolFamily: AF_INET
        ))

        let response = await withTimeout(milliseconds: 500) {
            await output.next()
        }
        let data = try XCTUnwrap(response?.data)
        XCTAssertEqual(response?.protocolFamily, AF_INET)
        XCTAssertEqual(data[12..<16].map(Int.init), [100, 100, 100, 101])
        XCTAssertEqual(data[16..<20].map(Int.init), [10, 0, 0, 9])
        XCTAssertEqual(data.suffix(4).map(Int.init), [10, 0, 0, 1])
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
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
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

    func testRouteUpdateFromUnauthenticatedPeerIsIgnored() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19132))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19133))
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
        let updatePayload = routeUpdatePayload(
            ipv4Address: "10.0.0.2",
            ipv6Address: nil,
            cost: 1,
            proxyCIDRs: ["192.168.88.0/24"]
        )
        try await transportB.send(CoreFrame(
            type: .control,
            sender: try XCTUnwrap(engineB.localIdentity?.peerID),
            receiver: try XCTUnwrap(engineA.localIdentity?.peerID),
            sequence: 51,
            payload: .control(.routeUpdate(updatePayload))
        ), to: transportA.endpoint)

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(engineA.routeTable.bestRoute(for: "192.168.88.9"))
    }

    func testRouteUpdateAddressedToAnotherPeerIsIgnored() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19134))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19135))
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
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
        let updatePayload = routeUpdatePayload(
            ipv4Address: "10.0.0.2",
            ipv6Address: nil,
            cost: 1,
            proxyCIDRs: ["192.168.99.0/24"]
        )
        try await transportB.send(CoreFrame(
            type: .control,
            sender: try XCTUnwrap(engineB.localIdentity?.peerID),
            receiver: PeerID(999),
            sequence: 52,
            payload: .control(.routeUpdate(updatePayload))
        ), to: transportA.endpoint)

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(engineA.routeTable.bestRoute(for: "192.168.99.9"))
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

    func testEndpointCandidateIsSentAfterSessionEstablishes() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19140))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19141))
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
            listeners: ["udp://127.0.0.1:20140"],
            mtu: 1380
        ))
        try await engineB.start(configuration: MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.0.0.2/24",
            listeners: ["udp://127.0.0.1:20141"],
            mtu: 1380
        ))
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)

        let peerID = try XCTUnwrap(engineA.localIdentity?.peerID)
        try await waitUntil(
            engineB.peerStore.peer(id: peerID)?.knownEndpoints.contains(TransportEndpoint(host: "127.0.0.1", port: 20140)) == true,
            timeout: .milliseconds(500)
        )
    }

    func testMappedUDPListenerIsPublishedAsEndpointCandidate() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19144))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19145))
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
            listeners: ["udp://127.0.0.1:20144"],
            mappedListeners: ["udp://198.51.100.9:21010"],
            mtu: 1380
        ))
        try await engineB.start(configuration: MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.0.0.2/24",
            listeners: ["udp://127.0.0.1:20145"],
            mtu: 1380
        ))
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)

        let peerID = try XCTUnwrap(engineA.localIdentity?.peerID)
        try await waitUntil(
            engineB.peerStore.peer(id: peerID)?.knownEndpoints.contains(TransportEndpoint(host: "198.51.100.9", port: 21010)) == true,
            timeout: .milliseconds(500)
        )
        XCTAssertFalse(
            engineB.peerStore.peer(id: peerID)?.knownEndpoints.contains(TransportEndpoint(host: "127.0.0.1", port: 20144)) == true
        )
    }

    func testDisabledUDPHolePunchingDoesNotSendEndpointCandidateAfterSessionEstablishes() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19142))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19143))
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
            listeners: ["udp://127.0.0.1:20142"],
            mtu: 1380,
            disableUDPHolePunching: true
        ))
        try await engineB.start(configuration: MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.0.0.2/24",
            listeners: ["udp://127.0.0.1:20143"],
            mtu: 1380
        ))
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)

        let peerID = try XCTUnwrap(engineA.localIdentity?.peerID)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(
            engineB.peerStore.peer(id: peerID)?.knownEndpoints.contains(TransportEndpoint(host: "127.0.0.1", port: 20142)) == true
        )
    }

    func testExitNodeForwardedDataFrameSetsExitNodeFlag() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19146))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19147))
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
            exitNodes: ["10.0.0.2"],
            mtu: 1380
        ))
        try await engineB.start(configuration: configuration(ipv4: "10.0.0.2/24", ipv6: "fd00:0:0:0:0:0:0:2"))
        try await exchangeHello(from: engineA, transport: transportA, to: engineB, endpoint: transportB.endpoint)
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
        try await waitUntil(engineB.sessionEstablished(with: engineA), timeout: .milliseconds(500))

        let packet = ipv4Packet(source: [10, 0, 0, 1], destination: [203, 0, 113, 10])
        await engineA.receivePacket(PacketTunnelPacket(data: packet, protocolFamily: AF_INET))

        try await waitUntil(
            transportA.sentFrames.contains { frame in
                frame.type == .data && (frame.flags & CoreFrame.exitNodeFlag) != 0
            },
            timeout: .milliseconds(500)
        )
    }

    func testExitNodeFlaggedFrameIsDroppedWhenExitNodeIsDisabled() async throws {
        let packet = ipv4Packet(source: [10, 0, 0, 1], destination: [203, 0, 113, 10])
        let received = try await receiveExitNodeFlaggedPacket(
            packet,
            receiverConfiguration: configuration(ipv4: "10.0.0.2/24", ipv6: "fd00:0:0:0:0:0:0:2")
        )

        XCTAssertNil(received)
    }

    func testExitNodeFlaggedFrameIsAcceptedWhenExitNodeIsEnabled() async throws {
        let packet = ipv4Packet(source: [10, 0, 0, 1], destination: [203, 0, 113, 10])
        let received = try await receiveExitNodeFlaggedPacket(
            packet,
            receiverConfiguration: MeshEngineConfiguration(
                networkName: "easytier",
                networkSecret: "secret",
                virtualIPv4: "10.0.0.2/24",
                virtualIPv6: "fd00:0:0:0:0:0:0:2",
                enableExitNode: true,
                mtu: 1380
            )
        )

        XCTAssertEqual(received, PacketTunnelPacket(data: packet, protocolFamily: AF_INET))
    }

    func testBroadcastDataFrameIsIgnored() async throws {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19152))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19153))
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
        try await exchangeHello(from: engineA, transport: transportA, to: engineB, endpoint: transportB.endpoint)
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
        try await waitUntil(engineB.sessionEstablished(with: engineA), timeout: .milliseconds(500))

        let identityA = try XCTUnwrap(engineA.localIdentity)
        let identityB = try XCTUnwrap(engineB.localIdentity)
        let crypto = try SessionCrypto.establish(
            localIdentity: identityA,
            handshake: HandshakeState(
                network: NetworkSecret(networkName: "easytier", secret: "secret"),
                localPeerID: identityA.peerID,
                remotePeerID: identityB.peerID,
                remotePublicKey: identityB.publicKey,
                role: .initiator
            )
        )
        let sequence: UInt64 = 9_001
        let packet = ipv4Packet(source: [10, 0, 0, 1], destination: [10, 0, 0, 2])
        let encrypted = try crypto.encrypt(sequence: sequence, plaintext: packet)
        var outputB = engineB.outboundPackets.makeAsyncIterator()

        try await transportA.send(CoreFrame(
            type: .data,
            sender: identityA.peerID,
            receiver: PeerID(0),
            sequence: sequence,
            payload: .data(DataPacket(encryptedIPPacket: encrypted))
        ), to: transportB.endpoint)

        let received = await withTimeout(milliseconds: 200) {
            await outputB.next()
        }
        XCTAssertNil(received)
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
                publicKey: identity.publicKey,
                version: "swift-core"
            )))
        )
        try await transport.send(frame, to: endpoint)
        try await waitUntil(remote.peerStore.peer(id: identity.peerID) != nil, timeout: .milliseconds(500))
    }

    private func receiveExitNodeFlaggedPacket(
        _ packet: Data,
        receiverConfiguration: MeshEngineConfiguration
    ) async throws -> PacketTunnelPacket? {
        let transportA = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19148))
        let transportB = InMemoryTransport(endpoint: TransportEndpoint(host: "127.0.0.1", port: 19149))
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
            exitNodes: ["10.0.0.2"],
            mtu: 1380
        ))
        try await engineB.start(configuration: receiverConfiguration)
        try await exchangeHello(from: engineA, transport: transportA, to: engineB, endpoint: transportB.endpoint)
        try await exchangeHello(from: engineB, transport: transportB, to: engineA, endpoint: transportA.endpoint)
        try await waitUntil(engineA.sessionEstablished(with: engineB), timeout: .milliseconds(500))
        try await waitUntil(engineB.sessionEstablished(with: engineA), timeout: .milliseconds(500))

        var outputB = engineB.outboundPackets.makeAsyncIterator()
        await engineA.receivePacket(PacketTunnelPacket(data: packet, protocolFamily: AF_INET))

        return await withTimeout(milliseconds: 200) {
            await outputB.next()
        }
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

    private func dnsQueryPacket(name: String, sourcePort: UInt16) -> Data {
        var dnsPayload = Data([0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            dnsPayload.append(UInt8(bytes.count))
            dnsPayload.append(contentsOf: bytes)
        }
        dnsPayload.append(0)
        dnsPayload.appendUInt16(1)
        dnsPayload.appendUInt16(1)

        var udp = Data()
        udp.appendUInt16(sourcePort)
        udp.appendUInt16(53)
        udp.appendUInt16(UInt16(8 + dnsPayload.count))
        udp.appendUInt16(0)
        udp.append(dnsPayload)

        let totalLength = UInt16(20 + udp.count)
        var data = Data([
            0x45, 0x00,
            UInt8(totalLength >> 8), UInt8(totalLength & 0xFF),
            0x00, 0x00, 0x00, 0x00,
            64, 17,
            0x00, 0x00
        ])
        data.append(contentsOf: [10, 0, 0, 9])
        data.append(contentsOf: [100, 100, 100, 101])
        data.append(udp)
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

    private func peerStats(from engine: MeshEngine) throws -> [String: Any]? {
        let data = try XCTUnwrap(engine.runningInfoData())
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let peers = json?["peers"] as? [[String: Any]]
        let connection = (peers?.first?["conns"] as? [[String: Any]])?.first
        return connection?["stats"] as? [String: Any]
    }

    private func peerLatency(from engine: MeshEngine) throws -> Int {
        let stats = try XCTUnwrap(peerStats(from: engine))
        return stats["latency_us"] as? Int ?? 0
    }
}

private extension MeshEngine {
    func sessionEstablished(with remote: MeshEngine) -> Bool {
        guard let peerID = remote.localIdentity?.peerID else { return false }
        return hasEstablishedSession(with: peerID)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
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

import XCTest
@testable import Spotier

final class SpotierConfigCodecTests: XCTestCase {
    func testParseBuildsModelFromStructuredToml() throws {
        let content = """
        instance_name = "office-node"
        instance_id = "fixed-id"
        dhcp = false
        ipv4 = "10.20.30.40/16"
        listeners = ["tcp://0.0.0.0:12010", "udp://0.0.0.0:12010"]
        mapped_listeners = ["tcp://198.51.100.1:12010"]
        socks5_proxy = "socks5://0.0.0.0:2080"
        exit_nodes = ["exit-a", "exit-b"]
        routes = ["10.0.0.0/24", "10.0.1.0/24"]

        [network_identity]
        network_name = "teamnet"
        network_secret = "topsecret"

        [[peer]]
        uri = "tcp://peer-1:11010"

        [[peer]]
        uri = "udp://peer-2:11010"

        [flags]
        mtu = 1440
        latency_first = true
        disable_ipv6 = true
        disable_encryption = true
        use_smoltcp = true
        no_tun = true
        disable_p2p = true
        p2p_only = true
        disable_udp_hole_punching = true
        enable_exit_node = true
        bind_device = true
        enable_kcp_proxy = true
        disable_kcp_input = true
        enable_quic_proxy = true
        disable_quic_input = true
        relay_all_peer_rpc = true
        multi_thread = false
        proxy_forward_by_system = true
        disable_sym_hole_punching = true
        enable_magic_dns = true
        enable_private_mode = true
        relay_network_whitelist = "corp office"

        [vpn_portal_config]
        client_cidr = "10.14.14.0/24"
        wireguard_listen = "0.0.0.0:22022"

        [[proxy_network]]
        cidr = "192.168.0.0/24"

        [[port_forward]]
        proto = "udp"
        bind_addr = "0.0.0.0:8080"
        dst_addr = "10.0.0.8:80"
        """

        let model = SpotierConfigCodec.parse(content)

        XCTAssertEqual(model.instanceName, "office-node")
        XCTAssertEqual(model.instanceId, "fixed-id")
        XCTAssertFalse(model.dhcp)
        XCTAssertEqual(model.ipv4, "10.20.30.40")
        XCTAssertEqual(model.cidr, "16")
        XCTAssertEqual(model.networkName, "teamnet")
        XCTAssertEqual(model.networkSecret, "topsecret")
        XCTAssertEqual(model.listeners.values, ["tcp://0.0.0.0:12010", "udp://0.0.0.0:12010"])
        XCTAssertEqual(model.mappedListeners.values, ["tcp://198.51.100.1:12010"])
        XCTAssertTrue(model.enableSocks5)
        XCTAssertEqual(model.socks5Port, 2080)
        XCTAssertEqual(model.exitNodes.values, ["exit-a", "exit-b"])
        XCTAssertTrue(model.enableManualRoutes)
        XCTAssertEqual(model.manualRoutes.values, ["10.0.0.0/24", "10.0.1.0/24"])
        XCTAssertEqual(model.peerMode, .manual)
        XCTAssertEqual(model.manualPeers.values, ["tcp://peer-1:11010", "udp://peer-2:11010"])
        XCTAssertEqual(model.mtu, 1440)
        XCTAssertTrue(model.latencyFirst)
        XCTAssertFalse(model.enableIPv6)
        XCTAssertFalse(model.enableEncryption)
        XCTAssertTrue(model.useSmoltcp)
        XCTAssertTrue(model.noTun)
        XCTAssertTrue(model.disableP2P)
        XCTAssertTrue(model.onlyP2P)
        XCTAssertTrue(model.disableUdpHolePunching)
        XCTAssertTrue(model.enableExitNode)
        XCTAssertTrue(model.bindDevice)
        XCTAssertTrue(model.enableKcpProxy)
        XCTAssertTrue(model.disableKcpInput)
        XCTAssertTrue(model.enableQuicProxy)
        XCTAssertTrue(model.disableQuicInput)
        XCTAssertTrue(model.relayAllPeerRpc)
        XCTAssertFalse(model.multiThread)
        XCTAssertTrue(model.proxyForwardBySystem)
        XCTAssertTrue(model.disableSymHolePunching)
        XCTAssertTrue(model.enableMagicDns)
        XCTAssertTrue(model.enablePrivateMode)
        XCTAssertTrue(model.enableRelayNetworkWhitelist)
        XCTAssertEqual(model.relayNetworkWhitelist.values, ["corp", "office"])
        XCTAssertTrue(model.enableVpnPortal)
        XCTAssertEqual(model.vpnPortalClientCidr, "10.14.14.0/24")
        XCTAssertEqual(model.vpnPortalListenPort, 22022)
        XCTAssertEqual(model.proxySubnets.map(\.cidr), ["192.168.0.0/24"])
        XCTAssertEqual(model.portForwards.count, 1)
        XCTAssertEqual(model.portForwards[0].protocolType, "UDP")
        XCTAssertEqual(model.portForwards[0].bindIp, "0.0.0.0")
        XCTAssertEqual(model.portForwards[0].bindPort, "8080")
        XCTAssertEqual(model.portForwards[0].targetIp, "10.0.0.8")
        XCTAssertEqual(model.portForwards[0].targetPort, "80")
    }

    func testGenerateWritesExpectedSectionsFromModel() {
        var model = SpotierConfigModel()
        model.instanceName = "generated-node"
        model.instanceId = "generated-id"
        model.dhcp = false
        model.ipv4 = "10.99.0.5"
        model.cidr = "24"
        model.networkName = "prodnet"
        model.networkSecret = "secret"
        model.listeners = .init(values: ["tcp://0.0.0.0:11010", ""])
        model.mappedListeners = .init(values: ["tcp://203.0.113.8:11010"])
        model.enableSocks5 = true
        model.socks5Port = 1088
        model.exitNodes = .init(values: ["exit-1"])
        model.enableManualRoutes = true
        model.manualRoutes = .init(values: ["10.8.0.0/16"])
        model.peerMode = .manual
        model.manualPeers = .init(values: ["tcp://peer-a:11010", ""])
        model.mtu = 1500
        model.latencyFirst = true
        model.enableIPv6 = false
        model.enableEncryption = false
        model.useSmoltcp = true
        model.noTun = true
        model.disableP2P = true
        model.onlyP2P = true
        model.disableUdpHolePunching = true
        model.enableExitNode = true
        model.bindDevice = true
        model.enableKcpProxy = true
        model.disableKcpInput = true
        model.enableQuicProxy = true
        model.disableQuicInput = true
        model.relayAllPeerRpc = true
        model.multiThread = false
        model.proxyForwardBySystem = true
        model.disableSymHolePunching = true
        model.enableMagicDns = true
        model.enablePrivateMode = true
        model.enableRelayNetworkWhitelist = true
        model.relayNetworkWhitelist = .init(values: ["corp", "office"])
        model.enableVpnPortal = true
        model.vpnPortalClientCidr = "10.14.14.0/24"
        model.vpnPortalListenPort = 22022
        model.proxySubnets = [.init(cidr: "192.168.1.0/24")]
        model.portForwards = [
            PortForwardRule(protocolType: "TCP", bindIp: "0.0.0.0", bindPort: "8080", targetIp: "10.0.0.8", targetPort: "80")
        ]

        let generated = SpotierConfigCodec.generate(from: model, peers: model.manualPeers.values)

        XCTAssertTrue(generated.contains("instance_name = \"generated-node\""))
        XCTAssertTrue(generated.contains("instance_id = \"generated-id\""))
        XCTAssertTrue(generated.contains("dhcp = false"))
        XCTAssertTrue(generated.contains("listeners = [\"tcp://0.0.0.0:11010\"]"))
        XCTAssertTrue(generated.contains("mapped_listeners = [\"tcp://203.0.113.8:11010\"]"))
        XCTAssertTrue(generated.contains("ipv4 = \"10.99.0.5/24\""))
        XCTAssertTrue(generated.contains("socks5_proxy = \"socks5://0.0.0.0:1088\""))
        XCTAssertTrue(generated.contains("exit_nodes = [\"exit-1\"]"))
        XCTAssertTrue(generated.contains("routes = [\"10.8.0.0/16\"]"))
        XCTAssertTrue(generated.contains("[network_identity]"))
        XCTAssertTrue(generated.contains("network_name = \"prodnet\""))
        XCTAssertTrue(generated.contains("network_secret = \"secret\""))
        XCTAssertTrue(generated.contains("[[peer]]\nuri = \"tcp://peer-a:11010\""))
        XCTAssertTrue(generated.contains("[flags]"))
        XCTAssertTrue(generated.contains("mtu = 1500"))
        XCTAssertTrue(generated.contains("multi_thread = false"))
        XCTAssertTrue(generated.contains("relay_network_whitelist = \"corp office\""))
        XCTAssertTrue(generated.contains("[vpn_portal_config]"))
        XCTAssertTrue(generated.contains("wireguard_listen = \"0.0.0.0:22022\""))
        XCTAssertTrue(generated.contains("[[proxy_network]]\ncidr = \"192.168.1.0/24\""))
        XCTAssertTrue(generated.contains("[[port_forward]]\nproto = \"tcp\""))
        XCTAssertFalse(generated.contains("\"\""))
    }
}

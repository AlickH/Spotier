import XCTest
@testable import Spotier

final class CoreConfigParserTests: XCTestCase {
    func testParsesCurrentGeneratedConfigShape() throws {
        let result = try CoreConfigParser.parse("""
        instance_name = "Mac"
        instance_id = "abc"
        dhcp = false
        listeners = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010"]
        mapped_listeners = ["udp://198.51.100.9:21010"]
        ipv4 = "10.126.126.4/24"
        routes = ["192.168.50.0/24", "10.88.0.0/16"]
        exit_nodes = ["10.126.126.9", "fd00::9"]

        [network_identity]
        network_name = "easytier"
        network_secret = "secret"

        [[peer]]
        uri = "tcp://public.easytier.top:11010"

        [flags]
        mtu = 1380
        enable_magic_dns = true
        enable_exit_node = true
        """)

        XCTAssertEqual(result.configuration.networkName, "easytier")
        XCTAssertEqual(result.configuration.networkSecret, "secret")
        XCTAssertEqual(result.configuration.instanceName, "Mac")
        XCTAssertEqual(result.configuration.virtualIPv4, "10.126.126.4/24")
        XCTAssertEqual(result.configuration.peers, ["tcp://public.easytier.top:11010"])
        XCTAssertEqual(result.configuration.listeners, [
            "tcp://0.0.0.0:11010",
            "udp://0.0.0.0:11010"
        ])
        XCTAssertEqual(result.configuration.mappedListeners, ["udp://198.51.100.9:21010"])
        XCTAssertEqual(result.configuration.mtu, 1380)
        XCTAssertEqual(result.configuration.advertisedRoutes, ["192.168.50.0/24", "10.88.0.0/16"])
        XCTAssertEqual(result.configuration.exitNodes, ["10.126.126.9", "fd00::9"])
        XCTAssertTrue(result.configuration.enableExitNode)
        XCTAssertTrue(result.configuration.magicDNS)
        XCTAssertEqual(result.configuration.magicDNSZone, "et.net")
        XCTAssertEqual(result.hints.ipv4, "10.126.126.4")
        XCTAssertEqual(result.hints.subnet, "255.255.255.0")
        XCTAssertTrue(result.hints.magicDNS)
    }

    func testParsesIPv6CIDR() throws {
        let result = try CoreConfigParser.parse("""
        ipv6 = "fd00::4/64"

        [network_identity]
        network_name = "easytier"
        network_secret = "secret"
        """)

        XCTAssertEqual(result.configuration.virtualIPv6, "fd00::4/64")
        XCTAssertEqual(result.hints.ipv6, "fd00::4")
        XCTAssertEqual(result.hints.ipv6Prefix, 64)
    }

    func testDisableIPv6ClearsVirtualIPv6() throws {
        let result = try CoreConfigParser.parse("""
        ipv6 = "fd00::4/64"

        [network_identity]
        network_name = "easytier"
        network_secret = "secret"

        [flags]
        disable_ipv6 = true
        """)

        XCTAssertNil(result.configuration.virtualIPv6)
        XCTAssertNil(result.hints.ipv6)
        XCTAssertNil(result.hints.ipv6Prefix)
    }

    func testParsesP2PDisableFlags() throws {
        let result = try CoreConfigParser.parse("""
        [network_identity]
        network_name = "easytier"
        network_secret = "secret"

        [flags]
        disable_p2p = true
        disable_udp_hole_punching = true
        """)

        XCTAssertTrue(result.configuration.disableP2P)
        XCTAssertTrue(result.configuration.disableUDPHolePunching)
    }

    func testParsesProxyNetworkCIDRsAsAdvertisedRoutes() throws {
        let result = try CoreConfigParser.parse("""
        routes = ["10.88.0.0/16"]

        [network_identity]
        network_name = "easytier"
        network_secret = "secret"

        [[proxy_network]]
        cidr = "192.168.1.0/24"

        [[proxy_network]]
        cidr = "172.16.0.0/16"
        """)

        XCTAssertEqual(result.configuration.advertisedRoutes, [
            "10.88.0.0/16",
            "192.168.1.0/24",
            "172.16.0.0/16"
        ])
    }

    func testDefaultsMTUTo1380() throws {
        let result = try CoreConfigParser.parse("""
        [network_identity]
        network_name = "easytier"
        network_secret = "secret"
        """)

        XCTAssertEqual(result.configuration.mtu, 1380)
        XCTAssertEqual(result.hints.mtu, 1380)
    }

    func testAllowsEmptyNetworkSecretBecauseCurrentConfigTreatsItAsOptional() throws {
        let result = try CoreConfigParser.parse("""
        [network_identity]
        network_name = "easytier"
        network_secret = ""
        """)

        XCTAssertEqual(result.configuration.networkSecret, "")
    }

    func testParsesMagicDNSZone() throws {
        let result = try CoreConfigParser.parse("""
        [network_identity]
        network_name = "easytier"
        network_secret = "secret"

        [flags]
        accept_dns = true
        tld_dns_zone = ".spotier.test."
        """)

        XCTAssertTrue(result.hints.magicDNS)
        XCTAssertEqual(result.hints.magicDNSZone, "spotier.test")
        XCTAssertTrue(result.configuration.magicDNS)
        XCTAssertEqual(result.configuration.magicDNSZone, "spotier.test")
    }

    func testRejectsMissingNetworkName() {
        XCTAssertThrowsError(try CoreConfigParser.parse("""
        [network_identity]
        network_secret = "secret"
        """)) { error in
            XCTAssertEqual(error as? CoreConfigParserError, .missingNetworkName)
        }
    }

    func testRejectsMissingNetworkSecret() {
        XCTAssertThrowsError(try CoreConfigParser.parse("""
        [network_identity]
        network_name = "easytier"
        """)) { error in
            XCTAssertEqual(error as? CoreConfigParserError, .missingNetworkSecret)
        }
    }
}

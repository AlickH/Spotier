import XCTest
@testable import Spotier

final class CoreConfigParserTests: XCTestCase {
    func testParsesCurrentGeneratedConfigShape() throws {
        let result = try CoreConfigParser.parse("""
        instance_name = "Mac"
        instance_id = "abc"
        dhcp = false
        listeners = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010"]
        ipv4 = "10.126.126.4/24"
        routes = ["192.168.50.0/24", "10.88.0.0/16"]

        [network_identity]
        network_name = "easytier"
        network_secret = "secret"

        [[peer]]
        uri = "tcp://public.easytier.top:11010"

        [flags]
        mtu = 1380
        enable_magic_dns = true
        """)

        XCTAssertEqual(result.configuration.networkName, "easytier")
        XCTAssertEqual(result.configuration.networkSecret, "secret")
        XCTAssertEqual(result.configuration.virtualIPv4, "10.126.126.4/24")
        XCTAssertEqual(result.configuration.peers, ["tcp://public.easytier.top:11010"])
        XCTAssertEqual(result.configuration.listeners, [
            "tcp://0.0.0.0:11010",
            "udp://0.0.0.0:11010"
        ])
        XCTAssertEqual(result.configuration.mtu, 1380)
        XCTAssertEqual(result.configuration.advertisedRoutes, ["192.168.50.0/24", "10.88.0.0/16"])
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

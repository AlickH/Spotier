import XCTest
@testable import Spotier

final class MeshEngineConfigurationTests: XCTestCase {
    func testAcceptsCurrentSwiftCoreConfigurationFields() throws {
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.126.126.4/24",
            virtualIPv6: "fd00::4/64",
            peers: ["udp://192.0.2.10:11010"],
            listeners: [
                "udp://0.0.0.0:11010",
                "wg://0.0.0.0:11011"
            ],
            mtu: 1380
        )

        XCTAssertNoThrow(try config.validate())
        XCTAssertEqual(config.networkName, "easytier")
        XCTAssertEqual(config.mtu, 1380)
    }

    func testRejectsEmptyNetworkName() {
        let config = MeshEngineConfiguration(networkName: " ", networkSecret: "secret")

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? MeshEngineConfigurationError, .emptyNetworkName)
        }
    }

    func testAllowsEmptyNetworkSecretBecauseCurrentConfigTreatsItAsOptional() {
        let config = MeshEngineConfiguration(networkName: "easytier", networkSecret: "")

        XCTAssertNoThrow(try config.validate())
    }

    func testRejectsInvalidMTU() {
        let config = MeshEngineConfiguration(networkName: "easytier", networkSecret: "secret", mtu: 128)

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? MeshEngineConfigurationError, .invalidMTU(128))
        }
    }
}

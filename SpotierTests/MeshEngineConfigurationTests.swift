import XCTest
@testable import Spotier

final class MeshEngineConfigurationTests: XCTestCase {
    func testAcceptsCurrentSpotierConfigurationFields() throws {
        let config = MeshEngineConfiguration(
            networkName: "easytier",
            networkSecret: "secret",
            virtualIPv4: "10.126.126.4/24",
            virtualIPv6: "fd00::4/64",
            peers: ["tcp://public.easytier.top:11010"],
            listeners: [
                "tcp://0.0.0.0:11010",
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

    func testRejectsEmptyNetworkSecret() {
        let config = MeshEngineConfiguration(networkName: "easytier", networkSecret: "")

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? MeshEngineConfigurationError, .emptyNetworkSecret)
        }
    }

    func testRejectsInvalidMTU() {
        let config = MeshEngineConfiguration(networkName: "easytier", networkSecret: "secret", mtu: 128)

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? MeshEngineConfigurationError, .invalidMTU(128))
        }
    }
}

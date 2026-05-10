import XCTest
@testable import Spotier

final class IdentityTests: XCTestCase {
    func testDeterministicIdentityGenerationWithFixedSeed() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let seed = Data(repeating: 7, count: 32)

        let first = try NodeIdentity.derive(
            network: network,
            deviceSeed: seed,
            hostname: "host-a",
            virtualIPv4: "10.0.0.2/24",
            virtualIPv6: nil
        )
        let second = try NodeIdentity.derive(
            network: network,
            deviceSeed: seed,
            hostname: "host-b",
            virtualIPv4: "10.0.0.9/24",
            virtualIPv6: "fd00::9/64"
        )

        XCTAssertEqual(first.peerID, second.peerID)
        XCTAssertEqual(first.publicKey, second.publicKey)
    }

    func testDifferentSecretsProduceDifferentIdentities() throws {
        let seed = Data(repeating: 3, count: 32)
        let first = try NodeIdentity.derive(
            network: NetworkSecret(networkName: "easytier", secret: "one"),
            deviceSeed: seed,
            hostname: "host",
            virtualIPv4: nil,
            virtualIPv6: nil
        )
        let second = try NodeIdentity.derive(
            network: NetworkSecret(networkName: "easytier", secret: "two"),
            deviceSeed: seed,
            hostname: "host",
            virtualIPv4: nil,
            virtualIPv6: nil
        )

        XCTAssertNotEqual(first.peerID, second.peerID)
        XCTAssertNotEqual(first.publicKey, second.publicKey)
    }

    func testRejectsEmptySeed() {
        XCTAssertThrowsError(try NodeIdentity.derive(
            network: NetworkSecret(networkName: "easytier", secret: "secret"),
            deviceSeed: Data(),
            hostname: "host",
            virtualIPv4: nil,
            virtualIPv6: nil
        )) { error in
            XCTAssertEqual(error as? NodeIdentityError, .emptyDeviceSeed)
        }
    }

    func testPersistedSeedReuse() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotier-seed-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = DeviceSeedStore(directoryURL: directory)
        let first = try store.loadOrCreate()
        let second = try store.loadOrCreate()

        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(first, second)
    }
}

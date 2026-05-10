import XCTest
@testable import Spotier

final class LogSettingsStoreTests: XCTestCase {
    func testReadLevelDefaultsToInfo() {
        let suiteName = "LogSettingsStoreTests.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        let store = LogSettingsStore(defaults: defaults)

        XCTAssertEqual(store.readLevel(), .info)
    }

    func testWriteLevelRoundTripsOffValue() {
        let suiteName = "LogSettingsStoreTests.roundtrip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        let store = LogSettingsStore(defaults: defaults)

        store.writeLevel(.off)

        XCTAssertEqual(store.readLevel(), .off)
        XCTAssertEqual(readStoredLogLevel(defaults: defaults), .off)
    }

    func testStoredLogLevelAllowsExpectedRuntimeLevels() {
        XCTAssertTrue(StoredLogLevel.warn.allows(.error))
        XCTAssertTrue(StoredLogLevel.warn.allows(.warn))
        XCTAssertFalse(StoredLogLevel.warn.allows(.info))
        XCTAssertFalse(StoredLogLevel.off.allows(.error))
    }
}

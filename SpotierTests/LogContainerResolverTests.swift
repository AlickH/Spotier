import XCTest
@testable import Spotier

final class LogContainerResolverTests: XCTestCase {
    func testResolverUsesProvidedContainerURL() {
        let expectedURL = URL(fileURLWithPath: "/tmp/easytier.log")
        let resolver = LogContainerResolver(
            fileManager: .default,
            fileURLProvider: { _, _ in expectedURL }
        )

        XCTAssertEqual(resolver.logFileURL(), expectedURL)
    }

    func testResolverReturnsNilWhenContainerURLMissing() {
        let resolver = LogContainerResolver(
            fileManager: .default,
            fileURLProvider: { _, _ in nil }
        )

        XCTAssertNil(resolver.logFileURL())
    }
}

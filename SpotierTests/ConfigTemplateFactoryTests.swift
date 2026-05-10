import XCTest
@testable import Spotier

final class ConfigTemplateFactoryTests: XCTestCase {
    func testSanitizedNameFallsBackForBlankInput() {
        XCTAssertEqual(ConfigTemplateFactory.sanitizedName(from: "   "), "new-network")
        XCTAssertEqual(ConfigTemplateFactory.filename(from: "   "), "new-network.toml")
    }

    func testFilenameAndContentUseTrimmedUserName() {
        let content = ConfigTemplateFactory.content(
            for: " office-node ",
            instanceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )

        XCTAssertEqual(ConfigTemplateFactory.filename(from: " office-node "), "office-node.toml")
        XCTAssertTrue(content.contains("instance_name = \"office-node\""))
        XCTAssertTrue(content.contains("instance_id = \"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\""))
        XCTAssertTrue(content.contains("listeners = [\"udp://0.0.0.0:11010\"]"))
        XCTAssertTrue(content.contains("network_name = \"easytier\""))
        XCTAssertTrue(content.contains("uri = \"udp://public.easytier.top:11010\""))
    }
}

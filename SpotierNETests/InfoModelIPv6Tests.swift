import XCTest

final class InfoModelIPv6Tests: XCTestCase {
    func testRunningIPv6AddrDescriptionUsesNetworkByteOrder() {
        let addr = RunningIPv6Addr(
            part1: 0x20010DB8,
            part2: 0x00010002,
            part3: 0x00030004,
            part4: 0x00050006
        )

        XCTAssertEqual(addr.description, "2001:db8:1:2:3:4:5:6")
    }

    func testMaskedIPv6AddressMasksHostBits() throws {
        let masked = try XCTUnwrap(maskedIPv6Address("2001:db8:1:2:3:4:5:6", networkLength: 64))
        XCTAssertEqual(masked, "2001:db8:1:2::")
    }
}

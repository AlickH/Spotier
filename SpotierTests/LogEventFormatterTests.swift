import XCTest
@testable import Spotier

final class LogEventFormatterTests: XCTestCase {
    func testParseEventEntryMapsWrappedEventTypeAndTimestamp() {
        let input = """
        {
          "time": "2026-03-22T10:20:30Z",
          "event": {
            "PeerAdded": {
              "peer_id": 7,
              "hostname": "demo"
            }
          }
        }
        """

        let event = LogEventFormatter.parseEventEntry(from: input)

        XCTAssertEqual(event?.type, .peerAdded)
        XCTAssertEqual(event?.name, "PeerAdded")
        XCTAssertEqual(event?.timestamp, "2026-03-22 10:20:30")
        XCTAssertTrue(event?.details.contains("\"peer_id\" : 7") ?? false)
    }

    func testParseEventEntryReturnsUnknownForUnexpectedEventName() {
        let input: [String: Any] = [
            "time": "2026-03-22T10:20:30Z",
            "event": [
                "CustomEvent": [
                    "enabled": true
                ]
            ]
        ]

        let event = LogEventFormatter.parseEventEntry(from: input)

        XCTAssertEqual(event?.type, .unknown)
        XCTAssertEqual(event?.name, "CustomEvent")
        XCTAssertTrue(event?.details.contains("\"enabled\" : true") ?? false)
    }

    func testCalculateHighlightsMarksStringsNumbersAndKeywords() {
        let highlights = LogEventFormatter.calculateHighlights(
            for: """
            {
              "peer_id" : 7,
              "enabled" : true,
              "name" : "demo"
            }
            """
        )

        XCTAssertTrue(highlights.contains(where: { $0.color == "green" }))
        XCTAssertTrue(highlights.contains(where: { $0.color == "blue" && $0.bold }))
        XCTAssertTrue(highlights.contains(where: { $0.color == "orange" }))
        XCTAssertTrue(highlights.contains(where: { $0.color == "purple" && $0.bold }))
    }
}

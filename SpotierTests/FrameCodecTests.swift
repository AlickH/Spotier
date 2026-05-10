import XCTest
@testable import Spotier

final class FrameCodecTests: XCTestCase {
    func testRoundTripEveryControlMessage() throws {
        let messages: [ControlMessage] = [
            .hello(.init(
                hostname: "mac",
                virtualIPv4: "10.0.0.2/24",
                virtualIPv6: "fd00::2/64",
                publicKey: Data([1, 2, 3, 4])
            )),
            .sessionOffer(Data([5, 6, 7])),
            .sessionAnswer(Data([8, 9, 10])),
            .routeUpdate(Data([11, 12, 13])),
            .peerPing,
            .peerPong,
            .relayRequest(PeerID(42)),
            .relayResponse(true),
            .relayResponse(false),
            .endpointCandidate("udp://203.0.113.10:11010")
        ]

        for message in messages {
            let frame = CoreFrame(
                type: .control,
                flags: 7,
                sender: PeerID(1),
                receiver: PeerID(2),
                sequence: 99,
                payload: .control(message)
            )

            let decoded = try FrameCodec.decode(try FrameCodec.encode(frame))

            XCTAssertEqual(decoded, frame)
        }
    }

    func testRoundTripDataPacket() throws {
        let frame = CoreFrame(
            type: .data,
            flags: 0,
            sender: PeerID(10),
            receiver: PeerID(20),
            sequence: 30,
            payload: .data(DataPacket(encryptedIPPacket: Data([0x45, 0x00, 0x00, 0x54])))
        )

        let decoded = try FrameCodec.decode(try FrameCodec.encode(frame))

        XCTAssertEqual(decoded, frame)
    }

    func testRejectsUnknownProtocolVersion() throws {
        var encoded = try FrameCodec.encode(sampleFrame())
        encoded[0] = 2

        XCTAssertThrowsError(try FrameCodec.decode(encoded)) { error in
            XCTAssertEqual(error as? FrameCodecError, .unknownProtocolVersion(2))
        }
    }

    func testRejectsTruncatedFrame() {
        XCTAssertThrowsError(try FrameCodec.decode(Data([1, 1, 0]))) { error in
            XCTAssertEqual(error as? FrameCodecError, .truncatedFrame)
        }
    }

    func testRejectsInvalidPayloadLength() throws {
        var encoded = try FrameCodec.encode(sampleFrame())
        encoded[28] = 0
        encoded[29] = 0
        encoded[30] = 0
        encoded[31] = 99

        XCTAssertThrowsError(try FrameCodec.decode(encoded)) { error in
            XCTAssertEqual(error as? FrameCodecError, .invalidPayloadLength)
        }
    }

    func testRejectsUnknownControlMessage() throws {
        var encoded = try FrameCodec.encode(sampleFrame())
        encoded[CoreFrame.headerLength] = 99

        XCTAssertThrowsError(try FrameCodec.decode(encoded)) { error in
            XCTAssertEqual(error as? FrameCodecError, .unknownControlMessage(99))
        }
    }

    private func sampleFrame() -> CoreFrame {
        CoreFrame(
            type: .control,
            flags: 0,
            sender: PeerID(1),
            receiver: PeerID(2),
            sequence: 3,
            payload: .control(.peerPing)
        )
    }
}

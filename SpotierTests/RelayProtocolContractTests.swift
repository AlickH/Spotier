import Foundation
import XCTest
@testable import Spotier

final class RelayProtocolContractTests: XCTestCase {
    func testRelayV1LengthPrefixedEncryptedRecord() throws {
        let pair = try relayContractSessionPair()
        let frame = CoreFrame(
            type: .control,
            sender: PeerID(1),
            receiver: PeerID(2),
            sequence: 41,
            payload: .control(.peerPing)
        )

        let encoded = try RelayFrameCodec.encode(frame, crypto: pair.client)
        let recordLength = encoded.readUInt32(at: 0)
        let sequence = encoded.readUInt64(at: RelayProtocolV1.lengthPrefixLength)
        let record = Data(encoded[RelayProtocolV1.lengthPrefixLength..<encoded.count])

        XCTAssertEqual(recordLength, UInt32(encoded.count - RelayProtocolV1.lengthPrefixLength))
        XCTAssertEqual(sequence, frame.sequence)
        assertPeerPingFrame(try RelayFrameCodec.decode(record, crypto: pair.server), sequence: frame.sequence)
    }

    func testRelayV1StreamDecoderWaitsForCompleteRecord() throws {
        let pair = try relayContractSessionPair()
        let first = try RelayFrameCodec.encode(frame(sequence: 1), crypto: pair.client)
        let second = try RelayFrameCodec.encode(frame(sequence: 2), crypto: pair.client)
        let decoder = RelayFrameStreamDecoder()

        XCTAssertEqual(try decoder.append(Data(first.prefix(6))).count, 0)

        let records = try decoder.append(Data(first.dropFirst(6)) + second)

        XCTAssertEqual(records.count, 2)
        guard records.count == 2 else { return }
        assertPeerPingFrame(try RelayFrameCodec.decode(records[0], crypto: pair.server), sequence: 1)
        assertPeerPingFrame(try RelayFrameCodec.decode(records[1], crypto: pair.server), sequence: 2)
    }

    func testRelayV1AcceptsOnlyTCPAndTLSSchemes() throws {
        let pair = try relayContractSessionPair()

        let tcpTransport = try RelayTransport(urlString: "tcp://127.0.0.1:19098", sessionCrypto: pair.client)
        let tlsTransport = try RelayTransport(urlString: "tls://relay.example.com:443", sessionCrypto: pair.client)

        XCTAssertFalse(tcpTransport.usesTLS)
        XCTAssertTrue(tlsTransport.usesTLS)
        XCTAssertThrowsError(try RelayTransport(urlString: "udp://relay.example.com:443", sessionCrypto: pair.client)) { error in
            XCTAssertEqual(error as? RelayTransportError, .unsupportedScheme("udp"))
        }
    }

    private func frame(sequence: UInt64) -> CoreFrame {
        CoreFrame(
            type: .control,
            sender: PeerID(1),
            receiver: PeerID(2),
            sequence: sequence,
            payload: .control(.peerPing)
        )
    }

    private func assertPeerPingFrame(
        _ frame: CoreFrame,
        sequence: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frame.type.rawValue, CoreFrameType.control.rawValue, file: file, line: line)
        XCTAssertEqual(frame.sender.rawValue, 1, file: file, line: line)
        XCTAssertEqual(frame.receiver.rawValue, 2, file: file, line: line)
        XCTAssertEqual(frame.sequence, sequence, file: file, line: line)
        guard case .control(.peerPing) = frame.payload else {
            XCTFail("Expected peer ping control frame", file: file, line: line)
            return
        }
    }
}

private func relayContractSessionPair() throws -> (client: SessionCrypto, server: SessionCrypto) {
    let network = NetworkSecret(networkName: "easytier", secret: "secret")
    let clientIdentity = try NodeIdentity.derive(
        network: network,
        deviceSeed: Data(repeating: 1, count: 32),
        hostname: "client",
        virtualIPv4: nil,
        virtualIPv6: nil
    )
    let serverIdentity = try NodeIdentity.derive(
        network: network,
        deviceSeed: Data(repeating: 2, count: 32),
        hostname: "server",
        virtualIPv4: nil,
        virtualIPv6: nil
    )

    return (
        try SessionCrypto.establish(
            localIdentity: clientIdentity,
            handshake: HandshakeState(
                network: network,
                localPeerID: clientIdentity.peerID,
                remotePeerID: serverIdentity.peerID,
                remotePublicKey: serverIdentity.publicKey,
                role: .initiator
            )
        ),
        try SessionCrypto.establish(
            localIdentity: serverIdentity,
            handshake: HandshakeState(
                network: network,
                localPeerID: serverIdentity.peerID,
                remotePeerID: clientIdentity.peerID,
                remotePublicKey: clientIdentity.publicKey,
                role: .responder
            )
        )
    )
}

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        self[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func readUInt64(at offset: Int) -> UInt64 {
        self[offset..<offset + 8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

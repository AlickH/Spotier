import XCTest
@testable import Spotier

final class SessionCryptoTests: XCTestCase {
    func testTwoPeersDeriveMatchingSessionKeys() throws {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let alice = try identity(seedByte: 1, network: network)
        let bob = try identity(seedByte: 2, network: network)

        let aliceCrypto = try SessionCrypto.establish(
            localIdentity: alice,
            handshake: HandshakeState(
                network: network,
                localPeerID: alice.peerID,
                remotePeerID: bob.peerID,
                remotePublicKey: bob.publicKey,
                role: .initiator
            )
        )
        let bobCrypto = try SessionCrypto.establish(
            localIdentity: bob,
            handshake: HandshakeState(
                network: network,
                localPeerID: bob.peerID,
                remotePeerID: alice.peerID,
                remotePublicKey: alice.publicKey,
                role: .responder
            )
        )

        let ciphertext = try aliceCrypto.encrypt(sequence: 1, plaintext: Data("hello".utf8))
        let plaintext = try bobCrypto.decrypt(sequence: 1, ciphertext: ciphertext)

        XCTAssertEqual(String(data: plaintext, encoding: .utf8), "hello")
    }

    func testWrongNetworkSecretFailsAuthentication() throws {
        let correctNetwork = NetworkSecret(networkName: "easytier", secret: "secret")
        let wrongNetwork = NetworkSecret(networkName: "easytier", secret: "wrong")
        let alice = try identity(seedByte: 1, network: correctNetwork)
        let bob = try identity(seedByte: 2, network: correctNetwork)

        let aliceCrypto = try SessionCrypto.establish(
            localIdentity: alice,
            handshake: HandshakeState(
                network: correctNetwork,
                localPeerID: alice.peerID,
                remotePeerID: bob.peerID,
                remotePublicKey: bob.publicKey,
                role: .initiator
            )
        )
        let bobCrypto = try SessionCrypto.establish(
            localIdentity: bob,
            handshake: HandshakeState(
                network: wrongNetwork,
                localPeerID: bob.peerID,
                remotePeerID: alice.peerID,
                remotePublicKey: alice.publicKey,
                role: .responder
            )
        )

        let ciphertext = try aliceCrypto.encrypt(sequence: 1, plaintext: Data("hello".utf8))

        XCTAssertThrowsError(try bobCrypto.decrypt(sequence: 1, ciphertext: ciphertext))
    }

    func testRejectsReplay() throws {
        let (aliceCrypto, bobCrypto) = try sessionPair()
        let ciphertext = try aliceCrypto.encrypt(sequence: 7, plaintext: Data("hello".utf8))

        _ = try bobCrypto.decrypt(sequence: 7, ciphertext: ciphertext)

        XCTAssertThrowsError(try bobCrypto.decrypt(sequence: 7, ciphertext: ciphertext)) { error in
            XCTAssertEqual(error as? SessionCryptoError, .replayedSequence(7))
        }
    }

    func testRejectsTamperedCiphertext() throws {
        let (aliceCrypto, bobCrypto) = try sessionPair()
        var ciphertext = try aliceCrypto.encrypt(sequence: 1, plaintext: Data("hello".utf8))
        ciphertext[ciphertext.count - 1] ^= 0xFF

        XCTAssertThrowsError(try bobCrypto.decrypt(sequence: 1, ciphertext: ciphertext))
    }

    private func sessionPair() throws -> (SessionCrypto, SessionCrypto) {
        let network = NetworkSecret(networkName: "easytier", secret: "secret")
        let alice = try identity(seedByte: 1, network: network)
        let bob = try identity(seedByte: 2, network: network)
        return (
            try SessionCrypto.establish(
                localIdentity: alice,
                handshake: HandshakeState(
                    network: network,
                    localPeerID: alice.peerID,
                    remotePeerID: bob.peerID,
                    remotePublicKey: bob.publicKey,
                    role: .initiator
                )
            ),
            try SessionCrypto.establish(
                localIdentity: bob,
                handshake: HandshakeState(
                    network: network,
                    localPeerID: bob.peerID,
                    remotePeerID: alice.peerID,
                    remotePublicKey: alice.publicKey,
                    role: .responder
                )
            )
        )
    }

    private func identity(seedByte: UInt8, network: NetworkSecret) throws -> NodeIdentity {
        try NodeIdentity.derive(
            network: network,
            deviceSeed: Data(repeating: seedByte, count: 32),
            hostname: "host-\(seedByte)",
            virtualIPv4: nil,
            virtualIPv6: nil
        )
    }
}

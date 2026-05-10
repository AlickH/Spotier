import CryptoKit
import Foundation

final class SessionCrypto {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var receivedSequences = Set<UInt64>()

    private init(sendKey: SymmetricKey, receiveKey: SymmetricKey) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
    }

    static func establish(
        localIdentity: NodeIdentity,
        handshake: HandshakeState
    ) throws -> SessionCrypto {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: localIdentity.privateKey
        )
        let remotePublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: handshake.remotePublicKey
        )
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: remotePublicKey)
        let orderedPeerIDs = [handshake.localPeerID.rawValue, handshake.remotePeerID.rawValue].sorted()

        var salt = Data("spotier.v1.session.salt".utf8)
        salt.append(handshake.network.bindingMaterial)
        salt.appendUInt64(orderedPeerIDs[0])
        salt.appendUInt64(orderedPeerIDs[1])

        let initiatorToResponder = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("spotier.v1.session.i2r".utf8),
            outputByteCount: 32
        )
        let responderToInitiator = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("spotier.v1.session.r2i".utf8),
            outputByteCount: 32
        )

        switch handshake.role {
        case .initiator:
            return SessionCrypto(
                sendKey: initiatorToResponder,
                receiveKey: responderToInitiator
            )
        case .responder:
            return SessionCrypto(
                sendKey: responderToInitiator,
                receiveKey: initiatorToResponder
            )
        }
    }

    func encrypt(sequence: UInt64, plaintext: Data) throws -> Data {
        let sealed = try ChaChaPoly.seal(
            plaintext,
            using: sendKey,
            authenticating: associatedData(sequence: sequence)
        )
        return sealed.combined
    }

    func decrypt(sequence: UInt64, ciphertext: Data) throws -> Data {
        guard !receivedSequences.contains(sequence) else {
            throw SessionCryptoError.replayedSequence(sequence)
        }

        let sealed = try ChaChaPoly.SealedBox(combined: ciphertext)
        let plaintext = try ChaChaPoly.open(
            sealed,
            using: receiveKey,
            authenticating: associatedData(sequence: sequence)
        )
        receivedSequences.insert(sequence)
        return plaintext
    }

    private func associatedData(sequence: UInt64) -> Data {
        var data = Data("spotier.v1.session.sequence".utf8)
        data.appendUInt64(sequence)
        return data
    }
}

enum SessionCryptoError: Error, Equatable {
    case replayedSequence(UInt64)
}

private extension Data {
    mutating func appendUInt64(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xFF))
        append(UInt8((value >> 48) & 0xFF))
        append(UInt8((value >> 40) & 0xFF))
        append(UInt8((value >> 32) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}

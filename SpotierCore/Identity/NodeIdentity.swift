import CryptoKit
import Foundation
import Security

struct NodeIdentity: Equatable {
    var peerID: PeerID
    var hostname: String
    var virtualIPv4: String?
    var virtualIPv6: String?
    var publicKey: Data

    static func derive(
        network: NetworkSecret,
        deviceSeed: Data,
        hostname: String,
        virtualIPv4: String?,
        virtualIPv6: String?
    ) throws -> NodeIdentity {
        guard !deviceSeed.isEmpty else {
            throw NodeIdentityError.emptyDeviceSeed
        }

        let privateKeySeed = SHA256.hash(data: network.bindingMaterial + deviceSeed + Data("identity-key".utf8))
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(privateKeySeed))
        let peerIDMaterial = SHA256.hash(data: network.bindingMaterial + deviceSeed + Data("peer-id".utf8))

        return NodeIdentity(
            peerID: PeerID(bytes: Data(peerIDMaterial)),
            hostname: hostname,
            virtualIPv4: virtualIPv4,
            virtualIPv6: virtualIPv6,
            publicKey: privateKey.publicKey.rawRepresentation
        )
    }
}

enum NodeIdentityError: Error, Equatable {
    case emptyDeviceSeed
}

struct DeviceSeedStore {
    static let filename = "spotier-device-seed.bin"

    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func loadOrCreate() throws -> Data {
        let fileURL = directoryURL.appendingPathComponent(Self.filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            return try Data(contentsOf: fileURL)
        }

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw DeviceSeedStoreError.randomGenerationFailed(status)
        }

        let seed = Data(bytes)
        try seed.write(to: fileURL, options: [.atomic])
        return seed
    }
}

enum DeviceSeedStoreError: Error, Equatable {
    case randomGenerationFailed(Int32)
}

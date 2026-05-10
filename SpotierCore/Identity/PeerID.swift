import Foundation

struct PeerID: Hashable, Codable, Equatable, CustomStringConvertible {
    let rawValue: UInt64

    init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init(bytes: some Collection<UInt8>) {
        var value: UInt64 = 0
        for byte in bytes.prefix(8) {
            value = (value << 8) | UInt64(byte)
        }
        self.rawValue = value
    }

    var description: String {
        String(rawValue)
    }
}

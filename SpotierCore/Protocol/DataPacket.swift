import Foundation

struct DataPacket: Equatable {
    var encryptedIPPacket: Data

    init(encryptedIPPacket: Data) {
        self.encryptedIPPacket = encryptedIPPacket
    }
}

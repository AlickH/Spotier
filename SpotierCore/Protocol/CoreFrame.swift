import Foundation

enum CoreFrameType: UInt8, Equatable {
    case control = 1
    case data = 2
}

enum CoreFramePayload: Equatable {
    case control(ControlMessage)
    case data(DataPacket)
}

struct CoreFrame: Equatable {
    static let protocolVersion: UInt8 = 1
    static let headerLength = 32
    static let exitNodeFlag: UInt16 = 1 << 0

    var type: CoreFrameType
    var flags: UInt16
    var sender: PeerID
    var receiver: PeerID
    var sequence: UInt64
    var payload: CoreFramePayload

    init(
        type: CoreFrameType,
        flags: UInt16 = 0,
        sender: PeerID,
        receiver: PeerID,
        sequence: UInt64,
        payload: CoreFramePayload
    ) {
        self.type = type
        self.flags = flags
        self.sender = sender
        self.receiver = receiver
        self.sequence = sequence
        self.payload = payload
    }
}

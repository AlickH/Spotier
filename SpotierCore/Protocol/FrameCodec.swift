import Foundation

enum FrameCodecError: Error, Equatable {
    case unknownProtocolVersion(UInt8)
    case unknownFrameType(UInt8)
    case unknownControlMessage(UInt8)
    case truncatedFrame
    case invalidPayloadLength
    case malformedPayload
}

enum FrameCodec {
    private enum ControlType: UInt8 {
        case hello = 1
        case sessionOffer = 2
        case sessionAnswer = 3
        case routeUpdate = 4
        case peerPing = 5
        case peerPong = 6
        case relayRequest = 7
        case relayResponse = 8
        case endpointCandidate = 9
    }

    static func encode(_ frame: CoreFrame) throws -> Data {
        let payload = try encodePayload(frame.payload)
        var data = Data()
        data.reserveCapacity(CoreFrame.headerLength + payload.count)

        data.append(CoreFrame.protocolVersion)
        data.append(frame.type.rawValue)
        data.appendUInt16(frame.flags)
        data.appendUInt64(frame.sender.rawValue)
        data.appendUInt64(frame.receiver.rawValue)
        data.appendUInt64(frame.sequence)
        data.appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    static func decode(_ data: Data) throws -> CoreFrame {
        guard data.count >= CoreFrame.headerLength else {
            throw FrameCodecError.truncatedFrame
        }

        var cursor = DataCursor(data)
        let version = try cursor.readUInt8()
        guard version == CoreFrame.protocolVersion else {
            throw FrameCodecError.unknownProtocolVersion(version)
        }

        let typeRaw = try cursor.readUInt8()
        guard let type = CoreFrameType(rawValue: typeRaw) else {
            throw FrameCodecError.unknownFrameType(typeRaw)
        }

        let flags = try cursor.readUInt16()
        let sender = PeerID(try cursor.readUInt64())
        let receiver = PeerID(try cursor.readUInt64())
        let sequence = try cursor.readUInt64()
        let payloadLength = Int(try cursor.readUInt32())

        guard payloadLength == data.count - CoreFrame.headerLength else {
            throw FrameCodecError.invalidPayloadLength
        }

        let payloadBytes = try cursor.readData(count: payloadLength)
        let payload = try decodePayload(payloadBytes, type: type)

        return CoreFrame(
            type: type,
            flags: flags,
            sender: sender,
            receiver: receiver,
            sequence: sequence,
            payload: payload
        )
    }

    private static func encodePayload(_ payload: CoreFramePayload) throws -> Data {
        switch payload {
        case .control(let message):
            return try encodeControlMessage(message)
        case .data(let packet):
            return packet.encryptedIPPacket
        }
    }

    private static func decodePayload(_ data: Data, type: CoreFrameType) throws -> CoreFramePayload {
        switch type {
        case .control:
            return .control(try decodeControlMessage(data))
        case .data:
            return .data(DataPacket(encryptedIPPacket: data))
        }
    }

    private static func encodeControlMessage(_ message: ControlMessage) throws -> Data {
        var data = Data()

        switch message {
        case .hello(let hello):
            data.append(ControlType.hello.rawValue)
            try data.appendString(hello.hostname)
            try data.appendOptionalString(hello.virtualIPv4)
            try data.appendOptionalString(hello.virtualIPv6)
            data.appendDataField(hello.publicKey)
        case .sessionOffer(let payload):
            data.append(ControlType.sessionOffer.rawValue)
            data.appendDataField(payload)
        case .sessionAnswer(let payload):
            data.append(ControlType.sessionAnswer.rawValue)
            data.appendDataField(payload)
        case .routeUpdate(let payload):
            data.append(ControlType.routeUpdate.rawValue)
            data.appendDataField(payload)
        case .peerPing:
            data.append(ControlType.peerPing.rawValue)
        case .peerPong:
            data.append(ControlType.peerPong.rawValue)
        case .relayRequest(let peerID):
            data.append(ControlType.relayRequest.rawValue)
            data.appendUInt64(peerID.rawValue)
        case .relayResponse(let accepted):
            data.append(ControlType.relayResponse.rawValue)
            data.append(accepted ? 1 : 0)
        case .endpointCandidate(let endpoint):
            data.append(ControlType.endpointCandidate.rawValue)
            try data.appendString(endpoint)
        }

        return data
    }

    private static func decodeControlMessage(_ data: Data) throws -> ControlMessage {
        var cursor = DataCursor(data)
        let rawType = try cursor.readUInt8()
        guard let type = ControlType(rawValue: rawType) else {
            throw FrameCodecError.unknownControlMessage(rawType)
        }

        let message: ControlMessage
        switch type {
        case .hello:
            message = .hello(ControlMessage.Hello(
                hostname: try cursor.readString(),
                virtualIPv4: try cursor.readOptionalString(),
                virtualIPv6: try cursor.readOptionalString(),
                publicKey: try cursor.readDataField()
            ))
        case .sessionOffer:
            message = .sessionOffer(try cursor.readDataField())
        case .sessionAnswer:
            message = .sessionAnswer(try cursor.readDataField())
        case .routeUpdate:
            message = .routeUpdate(try cursor.readDataField())
        case .peerPing:
            message = .peerPing
        case .peerPong:
            message = .peerPong
        case .relayRequest:
            message = .relayRequest(PeerID(try cursor.readUInt64()))
        case .relayResponse:
            message = .relayResponse(try cursor.readBool())
        case .endpointCandidate:
            message = .endpointCandidate(try cursor.readString())
        }

        guard cursor.isAtEnd else {
            throw FrameCodecError.malformedPayload
        }

        return message
    }
}

private struct DataCursor {
    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else {
            throw FrameCodecError.truncatedFrame
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try readBytes(count: 8)
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func readBool() throws -> Bool {
        switch try readUInt8() {
        case 0:
            return false
        case 1:
            return true
        default:
            throw FrameCodecError.malformedPayload
        }
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw FrameCodecError.truncatedFrame
        }
        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    mutating func readDataField() throws -> Data {
        try readData(count: Int(readUInt32()))
    }

    mutating func readString() throws -> String {
        let bytes = try readData(count: Int(readUInt16()))
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw FrameCodecError.malformedPayload
        }
        return value
    }

    mutating func readOptionalString() throws -> String? {
        switch try readUInt8() {
        case 0:
            return nil
        case 1:
            return try readString()
        default:
            throw FrameCodecError.malformedPayload
        }
    }

    private mutating func readBytes(count: Int) throws -> [UInt8] {
        Array(try readData(count: count))
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

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

    mutating func appendString(_ value: String) throws {
        let bytes = Data(value.utf8)
        guard bytes.count <= Int(UInt16.max) else {
            throw FrameCodecError.malformedPayload
        }
        appendUInt16(UInt16(bytes.count))
        append(bytes)
    }

    mutating func appendOptionalString(_ value: String?) throws {
        guard let value else {
            append(0)
            return
        }
        append(1)
        try appendString(value)
    }

    mutating func appendDataField(_ value: Data) {
        appendUInt32(UInt32(value.count))
        append(value)
    }
}

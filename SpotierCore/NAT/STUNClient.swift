import Foundation

struct STUNBindingRequest: Equatable {
    static let magicCookie: UInt32 = 0x2112A442

    var transactionID: Data

    init(transactionID: Data) throws {
        guard transactionID.count == 12 else {
            throw STUNError.invalidTransactionID
        }
        self.transactionID = transactionID
    }

    func encode() -> Data {
        var data = Data()
        data.appendUInt16(0x0001)
        data.appendUInt16(0)
        data.appendUInt32(Self.magicCookie)
        data.append(transactionID)
        return data
    }
}

struct STUNClient {
    let server: TransportEndpoint

    func bindingRequest(transactionID: Data) throws -> Data {
        try STUNBindingRequest(transactionID: transactionID).encode()
    }

    func discoverPublicEndpoint(from response: Data, transactionID: Data) throws -> TransportEndpoint {
        try Self.parseBindingResponse(response, transactionID: transactionID)
    }

    static func parseBindingResponse(_ data: Data, transactionID: Data) throws -> TransportEndpoint {
        guard transactionID.count == 12 else {
            throw STUNError.invalidTransactionID
        }
        guard data.count >= 20 else {
            throw STUNError.truncatedMessage
        }
        guard data.readUInt16(at: 0) == 0x0101 else {
            throw STUNError.unexpectedMessageType
        }
        guard data.readUInt32(at: 4) == STUNBindingRequest.magicCookie else {
            throw STUNError.invalidMagicCookie
        }
        guard data[8..<20] == transactionID[0..<12] else {
            throw STUNError.transactionMismatch
        }

        let messageLength = Int(data.readUInt16(at: 2))
        guard data.count >= 20 + messageLength else {
            throw STUNError.truncatedMessage
        }

        var offset = 20
        while offset + 4 <= 20 + messageLength {
            let attributeType = data.readUInt16(at: offset)
            let attributeLength = Int(data.readUInt16(at: offset + 2))
            let valueOffset = offset + 4
            guard valueOffset + attributeLength <= data.count else {
                throw STUNError.truncatedMessage
            }

            if attributeType == 0x0020 {
                return try parseXORMappedAddress(data, valueOffset: valueOffset, valueLength: attributeLength)
            }

            offset = valueOffset + paddedLength(attributeLength)
        }

        throw STUNError.missingXORMappedAddress
    }

    private static func parseXORMappedAddress(
        _ data: Data,
        valueOffset: Int,
        valueLength: Int
    ) throws -> TransportEndpoint {
        guard valueLength >= 8 else {
            throw STUNError.malformedAttribute
        }
        guard data[valueOffset + 1] == 0x01 else {
            throw STUNError.unsupportedAddressFamily
        }

        let xorPort = data.readUInt16(at: valueOffset + 2)
        let port = xorPort ^ UInt16(STUNBindingRequest.magicCookie >> 16)
        let xorAddress = data.readUInt32(at: valueOffset + 4)
        let address = xorAddress ^ STUNBindingRequest.magicCookie

        return TransportEndpoint(
            host: [
                String((address >> 24) & 0xFF),
                String((address >> 16) & 0xFF),
                String((address >> 8) & 0xFF),
                String(address & 0xFF)
            ].joined(separator: "."),
            port: port
        )
    }

    private static func paddedLength(_ length: Int) -> Int {
        let remainder = length % 4
        return remainder == 0 ? length : length + 4 - remainder
    }
}

enum STUNError: Error, Equatable {
    case invalidTransactionID
    case truncatedMessage
    case unexpectedMessageType
    case invalidMagicCookie
    case transactionMismatch
    case missingXORMappedAddress
    case malformedAttribute
    case unsupportedAddressFamily
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

    func readUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func readUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }
}

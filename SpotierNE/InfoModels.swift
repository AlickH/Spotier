import Darwin
import Foundation

struct RunningInfo: Decodable {
    var myNodeInfo: RunningNodeInfo?
    var routes: [RunningRoute]

    enum CodingKeys: String, CodingKey {
        case myNodeInfo = "my_node_info"
        case routes
    }
}

struct RunningNodeInfo: Decodable {
    var virtualIPv4: RunningIPv4CIDR?
    var virtualIPv6: RunningIPv6CIDR?

    enum CodingKeys: String, CodingKey {
        case virtualIPv4 = "virtual_ipv4"
        case virtualIPv6 = "virtual_ipv6"
    }
}

struct RunningRoute: Decodable {
    var proxyCIDRs: [String]

    enum CodingKeys: String, CodingKey {
        case proxyCIDRs = "proxy_cidrs"
    }
}

struct RunningIPv4CIDR: Decodable, Hashable {
    var address: RunningIPv4Addr
    var networkLength: Int

    init?(from string: String) {
        // Expect CIDR notation like "192.168.1.10/24"
        let toParsed = string.contains("/") ? string : string + "/32"
        let parts = toParsed.split(separator: "/")
        guard parts.count == 2,
              let addr = RunningIPv4Addr(from: String(parts[0])),
              let length = Int(parts[1]),
              (0...32).contains(length) else {
            return nil
        }
        self.address = addr
        self.networkLength = length
    }
    
    init(address: RunningIPv4Addr, length: Int) {
        self.address = address
        networkLength = length
    }

    enum CodingKeys: String, CodingKey {
        case address
        case networkLength = "network_length"
    }
}

struct RunningIPv4Addr: Decodable, Hashable {
    var addr: UInt32
    
    init(addr: UInt32) {
        self.addr = addr
    }

    init?(from string: String) {
        // Expect dotted-quad IPv4, e.g., "192.168.1.10"
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var bytes = [UInt32]()
        bytes.reserveCapacity(4)
        for p in parts {
            guard let val = UInt32(p), val <= 255 else { return nil }
            bytes.append(val)
        }
        // Pack into network-order (big-endian) 32-bit integer
        self.addr = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
    }

    var description: String {
        let ip = addr
        return "\((ip >> 24) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
    }
}

struct RunningIPv6CIDR: Decodable, Hashable {
    var address: RunningIPv6Addr
    var networkLength: Int

    enum CodingKeys: String, CodingKey {
        case address
        case networkLength = "network_length"
    }
}

struct RunningIPv6Addr: Decodable, Hashable {
    var part1: UInt32
    var part2: UInt32
    var part3: UInt32
    var part4: UInt32

    var description: String {
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        bytes.append(contentsOf: part1.bigEndianBytes)
        bytes.append(contentsOf: part2.bigEndianBytes)
        bytes.append(contentsOf: part3.bigEndianBytes)
        bytes.append(contentsOf: part4.bigEndianBytes)

        var ipv6 = in6_addr()
        withUnsafeMutableBytes(of: &ipv6) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }

        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result = inet_ntop(AF_INET6, &ipv6, &buffer, socklen_t(buffer.count))
        guard result != nil else { return "::" }
        return String(cString: buffer)
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        return [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}

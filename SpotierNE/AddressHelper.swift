import Darwin
import Foundation

func normalizeCIDR(_ cidr: String) -> RunningIPv4CIDR? {
    guard var cidrStruct = RunningIPv4CIDR(from: cidr) else { return nil }
    cidrStruct.address = ipv4MaskedSubnet(cidrStruct)
    return cidrStruct
}

func cidrToSubnetMask(_ cidr: Int) -> String? {
    guard cidr >= 0 && cidr <= 32 else { return nil }
    
    let mask: UInt32 = cidr == 0 ? 0 : UInt32.max << (32 - cidr)
    
    let octet1 = (mask >> 24) & 0xFF
    let octet2 = (mask >> 16) & 0xFF
    let octet3 = (mask >> 8) & 0xFF
    let octet4 = mask & 0xFF
    
    return "\(octet1).\(octet2).\(octet3).\(octet4)"
}

func ipv4MaskedSubnet(_ cidr: RunningIPv4CIDR) -> RunningIPv4Addr {
    let mask: UInt32 = cidr.networkLength == 0 ? 0 : UInt32.max << (32 - cidr.networkLength)
    return RunningIPv4Addr(addr: cidr.address.addr & mask)
}

func ipv4SubnetsOverlap(bigger: RunningIPv4CIDR, smaller: RunningIPv4CIDR) -> Bool {
    if bigger.networkLength > smaller.networkLength {
        return ipv4SubnetsOverlap(bigger: smaller, smaller: bigger)
    }
    let mask: UInt32 = bigger.networkLength == 0 ? 0 : UInt32.max << (32 - bigger.networkLength)
    return (bigger.address.addr & mask) == (smaller.address.addr & mask)
}

// Added from PacketTunnelProvider.swift to centralize logic

func maskedAddress(_ addr: RunningIPv4Addr, networkLength: Int) -> String {
    let mask = networkLength == 0 ? UInt32(0) : UInt32.max << (32 - networkLength)
    let network = addr.addr & mask
    return "\((network >> 24) & 0xFF).\((network >> 16) & 0xFF).\((network >> 8) & 0xFF).\(network & 0xFF)"
}

func maskedAddressFromStrings(_ ip: String, mask: String) -> String {
    let ipParts = ip.split(separator: ".").compactMap { UInt32($0) }
    let maskParts = mask.split(separator: ".").compactMap { UInt32($0) }
    guard ipParts.count == 4, maskParts.count == 4 else { return ip }
    return "\(ipParts[0] & maskParts[0]).\(ipParts[1] & maskParts[1]).\(ipParts[2] & maskParts[2]).\(ipParts[3] & maskParts[3])"
}

func parseCIDR(_ cidrStr: String) -> (address: String, mask: String)? {
    let parts = cidrStr.split(separator: "/")
    guard parts.count == 2,
          let cidr = Int(parts[1]),
          let mask = cidrToSubnetMask(cidr) else { return nil }
    
    // Apply mask to get network address
    let ipParts = String(parts[0]).split(separator: ".").compactMap { UInt32($0) }
    let maskParts = mask.split(separator: ".").compactMap { UInt32($0) }
    guard ipParts.count == 4, maskParts.count == 4 else { return nil }
    
    let networkAddr = "\(ipParts[0] & maskParts[0]).\(ipParts[1] & maskParts[1]).\(ipParts[2] & maskParts[2]).\(ipParts[3] & maskParts[3])"
    return (networkAddr, mask)
}

func parseIPv6CIDR(_ cidrStr: String) -> (address: String, prefixLength: Int)? {
    let parts = cidrStr.split(separator: "/")
    guard parts.count == 2,
          let prefixLength = Int(parts[1]),
          (0...128).contains(prefixLength) else { return nil }
    return (String(parts[0]), prefixLength)
}

func maskedIPv6Address(_ address: String, networkLength: Int) -> String? {
    guard (0...128).contains(networkLength) else { return nil }

    var ipv6 = in6_addr()
    let parseResult = address.withCString { ptr in
        inet_pton(AF_INET6, ptr, &ipv6)
    }
    guard parseResult == 1 else { return nil }

    var bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
    let fullBytes = networkLength / 8
    let remainingBits = networkLength % 8

    if fullBytes < bytes.count {
        if remainingBits > 0 {
            let mask = UInt8(0xFF << (8 - remainingBits))
            bytes[fullBytes] &= mask
            if fullBytes + 1 < bytes.count {
                for index in (fullBytes + 1)..<bytes.count {
                    bytes[index] = 0
                }
            }
        } else {
            for index in fullBytes..<bytes.count {
                bytes[index] = 0
            }
        }
    }

    var masked = in6_addr()
    withUnsafeMutableBytes(of: &masked) { destination in
        bytes.withUnsafeBytes { source in
            destination.copyBytes(from: source)
        }
    }

    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    let result = inet_ntop(AF_INET6, &masked, &buffer, socklen_t(buffer.count))
    guard result != nil else { return nil }

    return String(cString: buffer)
}

func ipv4RouteContainsAddress(destination: String, subnetMask: String, address: String) -> Bool {
    maskedAddressFromStrings(address, mask: subnetMask) == destination
}

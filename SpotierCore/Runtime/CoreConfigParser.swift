import Foundation

struct CoreConfigHints: Equatable {
    var ipv4: String?
    var subnet: String?
    var ipv6: String?
    var ipv6Prefix: Int?
    var mtu: Int?
    var magicDNS = false
    var magicDNSZone = "et.net"
}

struct CoreConfigParseResult: Equatable {
    var configuration: MeshEngineConfiguration
    var hints: CoreConfigHints
}

enum CoreConfigParserError: Error, Equatable {
    case missingNetworkName
    case missingNetworkSecret
}

enum CoreConfigParser {
    static func parse(_ toml: String) throws -> CoreConfigParseResult {
        var topLevel: [String: String] = [:]
        var networkIdentity: [String: String] = [:]
        var flags: [String: String] = [:]
        var peers: [String] = []
        var currentSection = ""

        for rawLine in toml.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]") {
                currentSection = String(trimmed.dropFirst(2).dropLast(2))
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }

            let key = parts[0]
            let value = unquote(parts[1])

            switch currentSection {
            case "":
                topLevel[key] = value
            case "network_identity":
                networkIdentity[key] = value
            case "flags":
                flags[key] = value
            case "peer":
                if key == "uri" {
                    peers.append(value)
                }
            default:
                break
            }
        }

        guard let networkName = networkIdentity["network_name"], !networkName.isEmpty else {
            throw CoreConfigParserError.missingNetworkName
        }

        guard let networkSecret = networkIdentity["network_secret"] else {
            throw CoreConfigParserError.missingNetworkSecret
        }

        let listeners = parseStringArray(topLevel["listeners"] ?? "")
        let advertisedRoutes = parseStringArray(topLevel["routes"] ?? "")
        let mtu = Int(flags["mtu"] ?? topLevel["mtu"] ?? "") ?? 1380
        let hints = configHints(topLevel: topLevel, flags: flags, mtu: mtu)

        let configuration = MeshEngineConfiguration(
            networkName: networkName,
            networkSecret: networkSecret,
            virtualIPv4: topLevel["ipv4"],
            virtualIPv6: topLevel["ipv6"],
            peers: peers,
            listeners: listeners,
            advertisedRoutes: advertisedRoutes,
            mtu: mtu
        )

        try configuration.validate()
        return CoreConfigParseResult(configuration: configuration, hints: hints)
    }

    private static func configHints(
        topLevel: [String: String],
        flags: [String: String],
        mtu: Int
    ) -> CoreConfigHints {
        var hints = CoreConfigHints()
        hints.mtu = mtu

        if let ipv4 = topLevel["ipv4"] {
            let cidrParts = ipv4.split(separator: "/")
            if cidrParts.count == 2 {
                hints.ipv4 = String(cidrParts[0])
                if let cidr = Int(cidrParts[1]) {
                    hints.subnet = cidrToSubnetMask(cidr)
                }
            }
        }

        if let ipv6 = topLevel["ipv6"],
           let parsed = parseIPv6CIDR(ipv6) {
            hints.ipv6 = parsed.address
            hints.ipv6Prefix = parsed.prefixLength
        }

        if ["enable_magic_dns", "accept_dns"].contains(where: { key in
            (flags[key] ?? topLevel[key])?.lowercased() == "true"
        }) {
            hints.magicDNS = true
        }

        if let rawZone = flags["tld_dns_zone"] ?? topLevel["tld_dns_zone"] {
            let zone = rawZone.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if !zone.isEmpty {
                hints.magicDNSZone = zone
            }
        }

        return hints
    }

    private static func unquote(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("\""), result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    private static func parseStringArray(_ value: String) -> [String] {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return [] }
        let inner = value.dropFirst().dropLast()
        return inner
            .split(separator: ",")
            .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func cidrToSubnetMask(_ cidr: Int) -> String? {
        guard (0...32).contains(cidr) else { return nil }

        let mask: UInt32 = cidr == 0 ? 0 : UInt32.max << (32 - cidr)
        return "\((mask >> 24) & 0xFF).\((mask >> 16) & 0xFF).\((mask >> 8) & 0xFF).\(mask & 0xFF)"
    }

    private static func parseIPv6CIDR(_ cidr: String) -> (address: String, prefixLength: Int)? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefixLength = Int(parts[1]),
              (0...128).contains(prefixLength) else {
            return nil
        }
        return (String(parts[0]), prefixLength)
    }
}

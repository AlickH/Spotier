import Foundation

enum ConfigTemplateFactory {
    static func sanitizedName(from rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "new-network" : trimmed
    }

    static func filename(from rawName: String) -> String {
        "\(sanitizedName(from: rawName)).toml"
    }

    static func content(for rawName: String, instanceID: UUID = UUID()) -> String {
        let safeName = sanitizedName(from: rawName)

        return """
        instance_name = "\(safeName)"
        instance_id = "\(instanceID.uuidString.lowercased())"
        dhcp = true
        listeners = ["udp://0.0.0.0:11010"]

        [network_identity]
        network_name = "easytier"
        network_secret = ""

        [[peer]]
        uri = "udp://public.easytier.top:11010"

        [flags]
        mtu = 1380
        disable_ipv6 = false
        disable_encryption = false
        """
    }
}

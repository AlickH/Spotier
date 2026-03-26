import Foundation

enum CIDRStringBehavior {
    static func ip(from value: String) -> String {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.isEmpty ? "" : parts[0]
    }

    static func mask(from value: String, defaultMask: String = "24") -> String {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1, !parts[1].isEmpty else { return defaultMask }
        return parts[1]
    }

    static func updatingIP(_ newIP: String, in value: String, defaultMask: String = "24") -> String {
        "\(newIP)/\(mask(from: value, defaultMask: defaultMask))"
    }

    static func updatingMask(_ newMask: String, in value: String, defaultMask: String = "24") -> String {
        "\(ip(from: value))/\(newMask.isEmpty ? defaultMask : newMask)"
    }
}

enum ConfigGeneratorListBehavior {
    static func appended(_ items: [EditableStringItem], value: String = "") -> [EditableStringItem] {
        items + [EditableStringItem(value: value)]
    }

    static func removing(_ id: EditableStringItem.ID, from items: [EditableStringItem]) -> [EditableStringItem] {
        items.filter { $0.id != id }
    }

    static func appended(_ items: [SpotierConfigModel.ProxySubnet], cidr: String = "0.0.0.0/0") -> [SpotierConfigModel.ProxySubnet] {
        items + [SpotierConfigModel.ProxySubnet(cidr: cidr)]
    }

    static func removing(_ id: SpotierConfigModel.ProxySubnet.ID, from items: [SpotierConfigModel.ProxySubnet]) -> [SpotierConfigModel.ProxySubnet] {
        items.filter { $0.id != id }
    }

    static func appended(_ items: [PortForwardRule], rule: PortForwardRule = PortForwardRule()) -> [PortForwardRule] {
        items + [rule]
    }

    static func removing(_ id: PortForwardRule.ID, from items: [PortForwardRule]) -> [PortForwardRule] {
        items.filter { $0.id != id }
    }
}

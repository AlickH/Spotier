import Foundation

struct VPNProfileDescriptor: Equatable {
    var localizedDescription: String?
    var providerBundleIdentifier: String?
}

enum VPNProfileSelection {
    static let expectedDescription = "Spotier VPN"
    static let expectedProviderBundleIdentifier = "com.alick.spotier.SpotierNE"

    static func firstMatchingProfileIndex(in profiles: [VPNProfileDescriptor]) -> Int? {
        profiles.firstIndex {
            $0.localizedDescription == expectedDescription &&
            $0.providerBundleIdentifier == expectedProviderBundleIdentifier
        }
    }
}

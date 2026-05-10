import XCTest
@testable import Spotier

final class VPNProfileSelectionTests: XCTestCase {
    func testSelectsProfileWithCurrentProviderBundleIdentifier() {
        let profiles = [
            VPNProfileDescriptor(
                localizedDescription: "Spotier VPN",
                providerBundleIdentifier: "com.alick.spotier.testflight.SpotierNE"
            ),
            VPNProfileDescriptor(
                localizedDescription: "Spotier VPN",
                providerBundleIdentifier: VPNProfileSelection.expectedProviderBundleIdentifier
            )
        ]

        XCTAssertEqual(VPNProfileSelection.firstMatchingProfileIndex(in: profiles), 1)
    }

    func testRejectsNonSpotierProfiles() {
        let profiles = [
            VPNProfileDescriptor(
                localizedDescription: "Other VPN",
                providerBundleIdentifier: VPNProfileSelection.expectedProviderBundleIdentifier
            )
        ]

        XCTAssertNil(VPNProfileSelection.firstMatchingProfileIndex(in: profiles))
    }
}

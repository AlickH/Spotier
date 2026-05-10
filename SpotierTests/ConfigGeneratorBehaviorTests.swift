import XCTest
@testable import Spotier

final class ConfigGeneratorBehaviorTests: XCTestCase {
    func testCIDRStringBehaviorParsesAndUpdatesConsistently() {
        XCTAssertEqual(CIDRStringBehavior.ip(from: "10.0.0.1/16"), "10.0.0.1")
        XCTAssertEqual(CIDRStringBehavior.mask(from: "10.0.0.1/16"), "16")
        XCTAssertEqual(CIDRStringBehavior.mask(from: "10.0.0.1"), "24")
        XCTAssertEqual(CIDRStringBehavior.updatingIP("10.0.0.9", in: "10.0.0.1/16"), "10.0.0.9/16")
        XCTAssertEqual(CIDRStringBehavior.updatingMask("20", in: "10.0.0.1/16"), "10.0.0.1/20")
        XCTAssertEqual(CIDRStringBehavior.updatingMask("", in: "10.0.0.1/16"), "10.0.0.1/24")
    }

    func testVpnPortalBindingsUseCentralizedCIDRBehavior() {
        var model = SpotierConfigModel()
        model.vpnPortalClientCidr = "10.14.14.0/24"

        XCTAssertEqual(model.vpnPortalIpBinding, "10.14.14.0")
        XCTAssertEqual(model.vpnPortalCidrBinding, "24")

        model.vpnPortalIpBinding = "10.20.30.0"
        XCTAssertEqual(model.vpnPortalClientCidr, "10.20.30.0/24")

        model.vpnPortalCidrBinding = "20"
        XCTAssertEqual(model.vpnPortalClientCidr, "10.20.30.0/20")
    }

    func testEditableStringListBehaviorAppendsAndRemovesByStableIdentity() {
        let first = EditableStringItem(value: "a")
        let second = EditableStringItem(value: "b")

        let appended = ConfigGeneratorListBehavior.appended([first, second], value: "c")
        XCTAssertEqual(appended.map(\.value), ["a", "b", "c"])

        let removed = ConfigGeneratorListBehavior.removing(second.id, from: appended)
        XCTAssertEqual(removed.map(\.value), ["a", "c"])
    }

    func testStructuredListBehaviorRemovesProxySubnetAndPortForwardByIdentity() {
        let subnetA = SpotierConfigModel.ProxySubnet(cidr: "10.0.0.0/24")
        let subnetB = SpotierConfigModel.ProxySubnet(cidr: "10.0.1.0/24")
        XCTAssertEqual(
            ConfigGeneratorListBehavior.removing(subnetA.id, from: [subnetA, subnetB]).map(\.cidr),
            ["10.0.1.0/24"]
        )

        let ruleA = PortForwardRule(protocolType: "TCP", bindIp: "0.0.0.0", bindPort: "8080", targetIp: "10.0.0.8", targetPort: "80")
        let ruleB = PortForwardRule(protocolType: "UDP", bindIp: "0.0.0.0", bindPort: "5353", targetIp: "10.0.0.9", targetPort: "53")
        XCTAssertEqual(
            ConfigGeneratorListBehavior.removing(ruleA.id, from: [ruleA, ruleB]).map(\.bindPort),
            ["5353"]
        )
    }

    func testFormExamplesUseSwiftCoreSupportedUDPEndpoints() {
        XCTAssertFalse(ConfigGeneratorFormText.listenerPlaceholder.contains("tcp://"))
        XCTAssertFalse(ConfigGeneratorFormText.mappedListenerFooter.contains("tcp://"))
        XCTAssertFalse(ConfigGeneratorFormText.mappedListenerPlaceholder.contains("tcp://"))

        XCTAssertTrue(ConfigGeneratorFormText.listenerPlaceholder.contains("udp://"))
        XCTAssertTrue(ConfigGeneratorFormText.mappedListenerFooter.contains("udp://"))
        XCTAssertTrue(ConfigGeneratorFormText.mappedListenerPlaceholder.contains("udp://"))
    }

    func testNewConfigNavigationOnlyExposesSwiftCoreGeneratedScreens() {
        XCTAssertEqual(ConfigScreen.allCases, [.main, .advanced])
    }
}

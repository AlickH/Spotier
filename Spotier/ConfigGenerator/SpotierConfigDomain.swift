import Foundation
import SwiftUI

struct PortForwardRule: Identifiable, Equatable {
    let id = UUID()
    var protocolType: String = "TCP"
    var bindIp: String = "0.0.0.0"
    var bindPort: String = ""
    var targetIp: String = "10.126.126.1"
    var targetPort: String = ""
}

struct EditableStringItem: Identifiable, Equatable {
    let id: UUID
    var value: String

    init(id: UUID = UUID(), value: String = "") {
        self.id = id
        self.value = value
    }
}

struct SpotierConfigModel: Equatable {
    static let defaultListenerValues = [
        "udp://0.0.0.0:11010"
    ]

    var instanceName: String = Host.current().localizedName!
    var instanceId: String = UUID().uuidString.lowercased()

    mutating func regenerateInstanceId() {
        instanceId = UUID().uuidString.lowercased()
    }

    var dhcp: Bool = true
    var ipv4: String = "10.126.126.4"
    var cidr: String = "24"
    var mtu: Int = 1380

    var networkName: String = "easytier"
    var networkSecret: String = ""

    var peerMode: PeerMode = .standalone
    var manualPeers: [EditableStringItem] = [
        EditableStringItem(value: "udp://")
    ]

    var listeners: [EditableStringItem] = Array(values: SpotierConfigModel.defaultListenerValues)

    var portForwards: [PortForwardRule] = []

    var latencyFirst: Bool = false
    var enableIPv6: Bool = true
    var enableEncryption: Bool = true
    var useSmoltcp: Bool = false
    var noTun: Bool = false
    var disableP2P: Bool = false
    var disableUdpHolePunching: Bool = false
    var enableExitNode: Bool = false
    var enableKcpProxy: Bool = false
    var enableQuicProxy: Bool = false
    var rpcPort: Int = 15888

    var disableKcpInput: Bool = false
    var disableQuicInput: Bool = false
    var disableUdp: Bool = false
    var relayAllPeerRpc: Bool = false
    var disableEntryNode: Bool = false
    var enableSocks5: Bool = false
    var socks5Port: Int = 1080
    var foreignNetworkWhitelist: String = ""

    var enableVpnPortal: Bool = false
    var vpnPortalClientCidr: String = "10.14.14.0/24"
    var vpnPortalListenPort: Int = 22022

    struct ProxySubnet: Identifiable, Equatable {
        let id = UUID()
        var cidr: String = "192.168.1.0/24"
    }
    var proxySubnets: [ProxySubnet] = []

    var enableManualRoutes: Bool = false
    var manualRoutes: [EditableStringItem] = []
    var exitNodes: [EditableStringItem] = []
    var enableRelayNetworkWhitelist: Bool = false
    var relayNetworkWhitelist: [EditableStringItem] = []
    var mappedListeners: [EditableStringItem] = []
    var enableOverrideDns: Bool = false
    var overrideDns: [EditableStringItem] = []

    var bindDevice: Bool = false
    var multiThread: Bool = true
    var proxyForwardBySystem: Bool = false
    var disableSymHolePunching: Bool = false
    var enableMagicDns: Bool = false
    var enablePrivateMode: Bool = false
    var onlyP2P: Bool = false
}

extension SpotierConfigModel {
    var vpnPortalIpBinding: String {
        get {
            CIDRStringBehavior.ip(from: vpnPortalClientCidr)
        }
        set {
            vpnPortalClientCidr = CIDRStringBehavior.updatingIP(newValue, in: vpnPortalClientCidr)
        }
    }

    var vpnPortalCidrBinding: String {
        get {
            CIDRStringBehavior.mask(from: vpnPortalClientCidr)
        }
        set {
            vpnPortalClientCidr = CIDRStringBehavior.updatingMask(newValue, in: vpnPortalClientCidr)
        }
    }
}

extension Array where Element == EditableStringItem {
    init(values: [String]) {
        self = values.map { EditableStringItem(value: $0) }
    }

    var values: [String] {
        map(\.value)
    }
}

enum PeerMode: String, CaseIterable, Identifiable {
    case publicServer = "公共服务器"
    case manual = "手动"
    case standalone = "独立"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}

enum ConfigScreen {
    case main
    case advanced
    case portForwarding
}

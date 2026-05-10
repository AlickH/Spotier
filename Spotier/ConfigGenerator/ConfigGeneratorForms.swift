import SwiftUI

struct ConfigGeneratorAdvancedForm: View {
    @Binding var model: SpotierConfigModel

    var body: some View {
        Form {
            generalSection
            overrideDNSSection
            proxySubnetSection
            vpnPortalSection
            listenersSection
            relayWhitelistSection
            manualRoutesSection
            socks5Section
            exitNodesSection
            mappedListenersSection
            featureToggleSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var generalSection: some View {
        SwiftUI.Section(header: Text(LocalizedStringKey("通用"))) {
            HStack {
                Text(LocalizedStringKey("主机名称"))
                TextField(LocalizedStringKey("默认"), text: $model.instanceName)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .textContentType(.none)
                    .disableAutocorrection(true)
            }

            HStack {
                Text("实例 ID")
                    .fixedSize()
                Spacer()
                Text(model.instanceId)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospaced()

                Button {
                    model.regenerateInstanceId()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .help("重新生成 UUID")
            }

            HStack {
                Text("MTU")
                Spacer()
                TextField("默认", value: Binding<Int?>(
                    get: { model.mtu == 1380 ? nil : model.mtu },
                    set: { model.mtu = $0 ?? 1380 }
                ), format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.plain)
                .labelsHidden()
                .textContentType(.none)
            }
        }
    }

    private var overrideDNSSection: some View {
        SwiftUI.Section(header: Text("覆盖 DNS"), footer: Text("覆盖系统 DNS。如果也同时启用了魔法 DNS，需要手动添加。")) {
            Toggle("启用", isOn: $model.enableOverrideDns)
            if model.enableOverrideDns {
                ForEach($model.overrideDns) { $dns in
                    HStack {
                        Text("地址")
                        Spacer()
                        ConfigGeneratorView.IPv4Field(ip: $dns.value)
                            .fixedSize()

                        Button {
                            removeEditableString(withID: dns.id, from: \.overrideDns)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    appendEditableString(to: \.overrideDns)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("添加 DNS")
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var proxySubnetSection: some View {
        SwiftUI.Section(header: Text(LocalizedStringKey("代理网段"))) {
            ForEach($model.proxySubnets) { $subnet in
                HStack {
                    Text(LocalizedStringKey("代理："))
                        .foregroundColor(.secondary)
                    Spacer()
                    ConfigGeneratorView.IPv4CidrField(
                        ip: Binding(
                            get: { CIDRStringBehavior.ip(from: subnet.cidr) },
                            set: { subnet.cidr = CIDRStringBehavior.updatingIP($0, in: subnet.cidr, defaultMask: "0") }
                        ),
                        cidr: Binding(
                            get: { CIDRStringBehavior.mask(from: subnet.cidr, defaultMask: "0") },
                            set: { subnet.cidr = CIDRStringBehavior.updatingMask($0, in: subnet.cidr, defaultMask: "0") }
                        )
                    )
                    .fixedSize()

                    Button {
                        model.proxySubnets = ConfigGeneratorListBehavior.removing(subnet.id, from: model.proxySubnets)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                model.proxySubnets = ConfigGeneratorListBehavior.appended(model.proxySubnets, cidr: "0.0.0.0/0")
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("添加代理网段")
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private var vpnPortalSection: some View {
        SwiftUI.Section("VPN 门户配置") {
            Toggle("启用", isOn: $model.enableVpnPortal)
            if model.enableVpnPortal {
                HStack {
                    Text("客户端网段")
                    Spacer()
                    ConfigGeneratorView.IPv4CidrField(ip: $model.vpnPortalIpBinding, cidr: $model.vpnPortalCidrBinding)
                        .fixedSize()
                }
                HStack {
                    Text("监听端口")
                    Spacer()
                    TextField("22022", value: $model.vpnPortalListenPort, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .labelsHidden()
                        .textContentType(.none)
                }
            }
        }
    }

    private var listenersSection: some View {
        SwiftUI.Section("监听地址") {
            ForEach($model.listeners) { $listener in
                HStack {
                    TextField("如：tcp://1.1.1.1:11010", text: $listener.value)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .textContentType(.none)
                        .disableAutocorrection(true)

                    Spacer()

                    Button {
                        removeEditableString(withID: listener.id, from: \.listeners)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { appendEditableString(to: \.listeners) } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("添加监听地址")
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private var relayWhitelistSection: some View {
        SwiftUI.Section(header: Text("网络白名单"), footer: Text("仅转发白名单网络的流量，支持通配符字符串。多个网络名称间可以使用英文空格间隔。如果该参数为空，则禁用转发。默认允许所有网络。例如：* (所有网络), def* (以 def 为前缀的网络), net1 net2 (只允许 net1 和 net2)。")) {
            Toggle("启用", isOn: $model.enableRelayNetworkWhitelist)
            if model.enableRelayNetworkWhitelist {
                editableStringListSection(list: $model.relayNetworkWhitelist, placeholder: "CIDR (e.g. 10.0.0.0/24)")
            }
        }
    }

    private var manualRoutesSection: some View {
        SwiftUI.Section(header: Text("自定义路由"), footer: Text("手动分配路由 CIDR，将禁用子网代理和从对等节点传播的 wireguard 路由。例如：192.168.0.0/16")) {
            Toggle("启用", isOn: $model.enableManualRoutes)
            if model.enableManualRoutes {
                ForEach($model.manualRoutes) { $route in
                    HStack {
                        Text("路由：")
                            .foregroundColor(.secondary)
                        Spacer()
                        ConfigGeneratorView.IPv4CidrField(
                            ip: cidrIPBinding(for: $route.value),
                            cidr: cidrMaskBinding(for: $route.value)
                        )
                        .fixedSize()

                        Button {
                            removeEditableString(withID: route.id, from: \.manualRoutes)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { appendEditableString("0.0.0.0/0", to: \.manualRoutes) } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("添加路由")
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var socks5Section: some View {
        SwiftUI.Section(header: Text(LocalizedStringKey("SOCKS5 服务器")), footer: Text(LocalizedStringKey("开启 SOCKS5 代理功能，Surge 等外部程序可通过此端口连接 Swiftier 网络。"))) {
            Toggle(LocalizedStringKey("启用"), isOn: $model.enableSocks5)
            if model.enableSocks5 {
                HStack {
                    Text(LocalizedStringKey("监听端口"))
                    Spacer()
                    TextField("", value: $model.socks5Port, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textContentType(.none)
                }
            }
        }
    }

    private var exitNodesSection: some View {
        SwiftUI.Section(header: Text(LocalizedStringKey("出口节点列表")), footer: Text(LocalizedStringKey("转发所有流量的出口节点，虚拟 IPv4 地址，优先级由列表顺序决定。"))) {
            ForEach($model.exitNodes) { $node in
                HStack {
                    Text(LocalizedStringKey("节点："))
                        .foregroundColor(.secondary)
                    Spacer()
                    ConfigGeneratorView.IPv4Field(ip: $node.value)
                        .fixedSize()

                    Button {
                        removeEditableString(withID: node.id, from: \.exitNodes)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { appendEditableString(to: \.exitNodes) } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(LocalizedStringKey("添加出口节点"))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private var mappedListenersSection: some View {
        SwiftUI.Section(header: Text(LocalizedStringKey("监听映射")), footer: Text(LocalizedStringKey("手动指定监听器的公网地址，其他节点可以使用该地址连接到本节点。例如：tcp://123.123.123.123:11223，可以指定多个。"))) {
            editableStringListSection(list: $model.mappedListeners, placeholder: "URI (e.g. tcp://...)")
        }
    }

    private var featureToggleSection: some View {
        SwiftUI.Section(header: Text(LocalizedStringKey("功能开关"))) {
            toggleRow("延迟优先模式", "忽略中转跳数，选择总延迟最低的路径。", isOn: $model.latencyFirst)
            toggleRow("使用用户态协议栈", "使用用户态 TCP/IP 协议栈，避免操作系统防火墙问题导致无法子网代理 / KCP 代理。", isOn: $model.useSmoltcp)
            toggleRow("禁用 IPv6", "禁用此节点的 IPv6 功能，仅使用 IPv4 进行网络通信。", isOn: Binding(
                get: { !model.enableIPv6 },
                set: { model.enableIPv6 = !$0 }
            ))
            toggleRow("启用 KCP 代理", "将 TCP 流量转为 KCP 流量，降低传输延迟，提升传输速度。", isOn: $model.enableKcpProxy)
            toggleRow("禁用 KCP 输入", "禁用 KCP 入站流量，其他开启 KCP 代理的节点仍然使用 TCP 连接到本节点。", isOn: $model.disableKcpInput)
            toggleRow("启用 QUIC 代理", "将 TCP 流量转为 QUIC 流量，降低传输延迟，提升传输速度。", isOn: $model.enableQuicProxy)
            toggleRow("禁用 QUIC 输入", "禁用 QUIC 入站流量，其他开启 QUIC 代理的节点仍然使用 TCP 连接到本节点。", isOn: $model.disableQuicInput)
            toggleRow("禁用 P2P", "禁用 P2P 模式，所有流量通过手动指定的服务器中转。", isOn: $model.disableP2P)
            toggleRow("仅 P2P", "仅与已经建立 P2P 连接的对等节点通信，不通过其他节点中转。", isOn: $model.onlyP2P)
            toggleRow("仅使用物理网卡", "仅使用物理网卡，避免 Swiftier 通过其他虚拟网建立连接。", isOn: $model.bindDevice)
            toggleRow("无 TUN 模式", "不使用 TUN 网卡，适合无管理员权限时使用。本节点仅允许被访问。访问其他节点需要使用 SOCKS5。", isOn: $model.noTun)
            toggleRow("启用出口节点", "允许此节点成为出口节点。", isOn: $model.enableExitNode)
            toggleRow("转发 RPC 包", "允许转发所有对等节点的 RPC 数据包，即使对等节点不在转发网络白名单中。这可以帮助白名单外网络中的对等节点建立 P2P 连接。", isOn: $model.relayAllPeerRpc)
            toggleRow("启用多线程", "使用多线程运行时。", isOn: $model.multiThread)
            toggleRow("系统转发", "通过系统内核转发子网代理数据包，禁用内置 NAT。", isOn: $model.proxyForwardBySystem)
            toggleRow("禁用加密", "禁用对等节点通信的加密，默认为 false，必须与对等节点相同。", isOn: Binding(
                get: { !model.enableEncryption },
                set: { model.enableEncryption = !$0 }
            ))
            toggleRow("禁用 UDP 打洞", "禁用 UDP 打洞功能。", isOn: $model.disableUdpHolePunching)
            toggleRow("禁用对称 NAT 打洞", "禁用对标 NAT 的打洞 (生日攻击)，将对称 NAT 视为锥形 NAT 处理。", isOn: $model.disableSymHolePunching)
            toggleRow("启用 Magic DNS", "启用魔法 DNS，允许通过 Swiftier 的 DNS 服务器访问其他节点的虚拟 IPv4 地址，例如：node1.et.net。", isOn: $model.enableMagicDns)
            toggleRow("启用私有模式", "启用私有模式，则不允许使用了与本网络不同的网络名称和密码的节点通过本节点进行握手或中转。", isOn: $model.enablePrivateMode)
        }
    }

    private func editableStringListSection(list: Binding<[EditableStringItem]>, placeholder: String) -> some View {
        Group {
            ForEach(list) { $item in
                HStack {
                    TextField(placeholder, text: $item.value)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .textContentType(.none)
                        .disableAutocorrection(true)

                    Spacer()

                    Button {
                        list.wrappedValue = ConfigGeneratorListBehavior.removing(item.id, from: list.wrappedValue)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { list.wrappedValue = ConfigGeneratorListBehavior.appended(list.wrappedValue) } label: {
                Label(LocalizedStringKey("添加"), systemImage: "plus.circle.fill").foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleRow(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func appendEditableString(_ value: String = "", to keyPath: WritableKeyPath<SpotierConfigModel, [EditableStringItem]>) {
        model[keyPath: keyPath] = ConfigGeneratorListBehavior.appended(model[keyPath: keyPath], value: value)
    }

    private func removeEditableString(withID id: EditableStringItem.ID, from keyPath: WritableKeyPath<SpotierConfigModel, [EditableStringItem]>) {
        model[keyPath: keyPath] = ConfigGeneratorListBehavior.removing(id, from: model[keyPath: keyPath])
    }

    private func cidrIPBinding(for value: Binding<String>) -> Binding<String> {
        Binding(
            get: {
                CIDRStringBehavior.ip(from: value.wrappedValue)
            },
            set: { newIP in
                value.wrappedValue = CIDRStringBehavior.updatingIP(newIP, in: value.wrappedValue)
            }
        )
    }

    private func cidrMaskBinding(for value: Binding<String>) -> Binding<String> {
        Binding(
            get: {
                CIDRStringBehavior.mask(from: value.wrappedValue)
            },
            set: { newCIDR in
                value.wrappedValue = CIDRStringBehavior.updatingMask(newCIDR, in: value.wrappedValue)
            }
        )
    }
}

struct ConfigGeneratorMainForm: View {
    @Binding var model: SpotierConfigModel
    let onOpenAdvanced: () -> Void
    let onOpenPortForwarding: () -> Void

    var body: some View {
        Form {
            virtualIPv4Section
            networkSection
            navigationSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var virtualIPv4Section: some View {
        Section(header: Text(LocalizedStringKey("虚拟 IPv4 地址"))) {
            Toggle(LocalizedStringKey("DHCP"), isOn: $model.dhcp)

            if !model.dhcp {
                HStack(spacing: 0) {
                    Text(LocalizedStringKey("地址"))
                    Spacer()
                    ConfigGeneratorView.IPv4CidrField(ip: $model.ipv4, cidr: $model.cidr)
                        .fixedSize()
                }
            }
        }
    }

    private var networkSection: some View {
        Section(header: Text(LocalizedStringKey("网络"))) {
            HStack {
                Text(LocalizedStringKey("名称"))
                TextField("easytier", text: $model.networkName)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .textContentType(.none)
                    .disableAutocorrection(true)
            }

            HStack {
                Text(LocalizedStringKey("密码"))
                TextField(LocalizedStringKey("选填"), text: $model.networkSecret)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .textContentType(.none)
                    .disableAutocorrection(true)
            }

            Picker(LocalizedStringKey("节点模式"), selection: $model.peerMode) {
                ForEach(PeerMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)

            if model.peerMode == .manual {
                ForEach($model.manualPeers) { $peer in
                    HStack {
                        TextField("udp://...", text: $peer.value)
                            .textFieldStyle(.plain)
                            .labelsHidden()
                            .textContentType(.none)
                            .disableAutocorrection(true)

                        Spacer()

                        Button {
                            model.manualPeers = ConfigGeneratorListBehavior.removing(peer.id, from: model.manualPeers)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    model.manualPeers = ConfigGeneratorListBehavior.appended(model.manualPeers, value: "udp://")
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(LocalizedStringKey("添加节点"))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            } else if model.peerMode == .publicServer {
                HStack {
                    Text(LocalizedStringKey("服务器"))
                    Spacer()
                    Text(LocalizedStringKey("Swift core does not use EasyTier public servers"))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    private var navigationSection: some View {
        Section {
            Button(action: onOpenAdvanced) {
                HStack {
                    Text(LocalizedStringKey("高级设置"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onOpenPortForwarding) {
                HStack {
                    Text(LocalizedStringKey("端口转发"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct ConfigGeneratorPortForwardingForm: View {
    @Binding var model: SpotierConfigModel

    var body: some View {
        Form {
            ForEach($model.portForwards) { $rule in
                Section {
                    VStack(spacing: 12) {
                        HStack {
                            Text(LocalizedStringKey("协议"))
                            Spacer()
                            Picker("", selection: $rule.protocolType) {
                                Text("TCP").tag("TCP")
                                Text("UDP").tag("UDP")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }

                        Divider()

                        HStack {
                            Text(LocalizedStringKey("绑定地址"))
                            Spacer()
                            ConfigGeneratorView.IPv4Field(ip: $rule.bindIp)
                                .fixedSize()
                            Text(":")
                            TextField("0", text: $rule.bindPort)
                                .frame(width: 50)
                        }
                        .textFieldStyle(.plain)
                        .labelsHidden()

                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(LocalizedStringKey("转发到"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        HStack {
                            Text(LocalizedStringKey("目标地址"))
                            Spacer()
                            ConfigGeneratorView.IPv4Field(ip: $rule.targetIp)
                                .fixedSize()
                            Text(":")
                            TextField("0", text: $rule.targetPort)
                                .frame(width: 50)
                        }
                        .textFieldStyle(.plain)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Spacer()
                        Button("删除") {
                            model.portForwards = ConfigGeneratorListBehavior.removing(rule.id, from: model.portForwards)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button {
                    model.portForwards = ConfigGeneratorListBehavior.appended(model.portForwards)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(LocalizedStringKey("添加端口转发"))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

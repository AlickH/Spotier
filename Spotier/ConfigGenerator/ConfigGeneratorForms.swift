import SwiftUI

enum ConfigGeneratorFormText {
    static let listenerPlaceholder = "如：udp://1.1.1.1:11010"
    static let mappedListenerFooter = "手动指定监听器的公网地址，其他节点可以使用该地址连接到本节点。例如：udp://123.123.123.123:11223，可以指定多个。"
    static let mappedListenerPlaceholder = "URI (e.g. udp://...)"
}

struct ConfigGeneratorAdvancedForm: View {
    @Binding var model: SpotierConfigModel

    var body: some View {
        Form {
            ForEach(ConfigGeneratorAdvancedSection.allCases, id: \.self) { section in
                switch section {
                case .general:
                    generalSection
                case .proxySubnet:
                    proxySubnetSection
                case .listeners:
                    listenersSection
                case .manualRoutes:
                    manualRoutesSection
                case .exitNodes:
                    exitNodesSection
                case .mappedListeners:
                    mappedListenersSection
                case .featureToggle:
                    featureToggleSection
                }
            }
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

    private var listenersSection: some View {
        SwiftUI.Section("监听地址") {
            ForEach($model.listeners) { $listener in
                HStack {
                    TextField(ConfigGeneratorFormText.listenerPlaceholder, text: $listener.value)
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
        SwiftUI.Section(header: Text(LocalizedStringKey("监听映射")), footer: Text(ConfigGeneratorFormText.mappedListenerFooter)) {
            editableStringListSection(list: $model.mappedListeners, placeholder: ConfigGeneratorFormText.mappedListenerPlaceholder)
        }
    }

    private var featureToggleSection: some View {
        SwiftUI.Section(header: Text(LocalizedStringKey("功能开关"))) {
            ForEach(ConfigGeneratorFeatureToggle.allCases, id: \.self) { toggle in
                switch toggle {
                case .latencyFirst:
                    toggleRow("延迟优先模式", "忽略中转跳数，选择总延迟最低的路径。", isOn: $model.latencyFirst)
                case .disableIPv6:
                    toggleRow("禁用 IPv6", "禁用此节点的 IPv6 功能，仅使用 IPv4 进行网络通信。", isOn: Binding(
                        get: { !model.enableIPv6 },
                        set: { model.enableIPv6 = !$0 }
                    ))
                case .disableP2P:
                    toggleRow("禁用 P2P", "禁用 P2P 模式，所有流量通过手动指定的服务器中转。", isOn: $model.disableP2P)
                case .onlyP2P:
                    toggleRow("仅 P2P", "仅与已经建立 P2P 连接的对等节点通信，不通过其他节点中转。", isOn: $model.onlyP2P)
                case .enableExitNode:
                    toggleRow("启用出口节点", "允许此节点成为出口节点。", isOn: $model.enableExitNode)
                case .disableEncryption:
                    toggleRow("禁用加密", "禁用对等节点通信的加密，默认为 false，必须与对等节点相同。", isOn: Binding(
                        get: { !model.enableEncryption },
                        set: { model.enableEncryption = !$0 }
                    ))
                case .disableUdpHolePunching:
                    toggleRow("禁用 UDP 打洞", "禁用 UDP 打洞功能。", isOn: $model.disableUdpHolePunching)
                case .enableMagicDNS:
                    toggleRow("启用 Magic DNS", "启用魔法 DNS，允许通过 Swiftier 的 DNS 服务器访问其他节点的虚拟 IPv4 地址，例如：node1.et.net。", isOn: $model.enableMagicDns)
                case .enablePrivateMode:
                    toggleRow("启用私有模式", "启用私有模式，则不允许使用了与本网络不同的网络名称和密码的节点通过本节点进行握手或中转。", isOn: $model.enablePrivateMode)
                }
            }
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
        }
    }
}

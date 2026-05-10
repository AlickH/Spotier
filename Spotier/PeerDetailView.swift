import SwiftUI

struct PeerDetailView: View {
    let peer: PeerInfo

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 0) {
            Text(LocalizedStringKey("点击条目以复制内容"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)

            Form {
                if let myNode = peer.myNodeData {
                    localNodeSections(myNode)
                } else if let pair = peer.fullData {
                    remotePeerSections(pair)
                } else {
                    basicSections
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 320, height: 450)
    }

    @ViewBuilder
    private func localNodeSections(_ node: SpotierStatus.NodeInfo) -> some View {
        Section(header: Text(LocalizedStringKey("节点"))) {
            CopyableDetailRow(label: LocalizedStringKey("主机名"), value: node.hostname)
            CopyableDetailRow(label: LocalizedStringKey("版本"), value: node.version)
            if let virtualIPv4 = node.virtualIPv4 {
                CopyableDetailRow(label: LocalizedStringKey("虚拟 IP"), value: virtualIPv4.description)
            }
            if let stunInfo = node.stunInfo {
                if !stunInfo.udpNATType.description.isEmpty {
                    CopyableDetailRow(label: LocalizedStringKey("UDP NAT 类型"), value: stunInfo.udpNATType.description)
                }
                if !stunInfo.tcpNATType.description.isEmpty {
                    CopyableDetailRow(label: LocalizedStringKey("TCP NAT 类型"), value: stunInfo.tcpNATType.description)
                }
            }
        }

        if let listeners = node.listeners, !listeners.isEmpty {
            Section(header: Text(LocalizedStringKey("监听地址"))) {
                ForEach(listeners.indices, id: \.self) { index in
                    CopyableDetailRow(label: LocalizedStringKey("监听 \(index + 1)"), value: listeners[index].url)
                }
            }
        }
    }

    @ViewBuilder
    private func remotePeerSections(_ pair: SpotierStatus.PeerRoutePair) -> some View {
        let route = pair.route

        Section(header: Text(LocalizedStringKey("节点"))) {
            CopyableDetailRow(label: LocalizedStringKey("主机名"), value: route.hostname)
            CopyableDetailRow(label: LocalizedStringKey("节点 ID"), value: "\(route.peerId)", isMonospaced: true)
            CopyableDetailRow(label: LocalizedStringKey("实例 ID"), value: route.instId, isMonospaced: true)
            CopyableDetailRow(label: LocalizedStringKey("版本"), value: route.version)
            CopyableDetailRow(label: LocalizedStringKey("下一跳 ID"), value: "\(route.nextHopPeerId)", isMonospaced: true)
            CopyableDetailRow(label: LocalizedStringKey("代价"), value: "\(route.cost)")
            CopyableDetailRow(label: LocalizedStringKey("路径延迟"), value: "\(route.pathLatency / 1000) ms")

            if let nextHopLatencyFirst = route.nextHopPeerIdLatencyFirst {
                CopyableDetailRow(label: LocalizedStringKey("下一跳 (延迟优先)"), value: "\(nextHopLatencyFirst)", isMonospaced: true)
                CopyableDetailRow(label: LocalizedStringKey("代价 (延迟优先)"), value: "\(route.costLatencyFirst ?? 0)")
                CopyableDetailRow(label: LocalizedStringKey("路径延迟 (延迟优先)"), value: "\((route.pathLatencyLatencyFirst ?? 0) / 1000) ms")
            }

            if let flags = route.featureFlag {
                let formattedFlags = formatFlags(flags)
                if !formattedFlags.isEmpty {
                    CopyableDetailRow(label: LocalizedStringKey("特性标志"), value: formattedFlags)
                }
            }
        }

        if let peerInfo = pair.peer {
            Section(header: Text(LocalizedStringKey("连接状态"))) {
                if let defaultConnId = peerInfo.defaultConnId {
                    CopyableDetailRow(label: LocalizedStringKey("默认连接"), value: defaultConnId.description)
                }
            }

            ForEach(peerInfo.conns.indices, id: \.self) { index in
                let connection = peerInfo.conns[index]
                Section(header: Text(connectionTitle(for: connection, index: index))) {
                    CopyableDetailRow(label: LocalizedStringKey("角色"), value: connection.isClient ? "Client" : "Server")
                    CopyableDetailRow(label: LocalizedStringKey("丢包率"), value: String(format: "%.2f%%", connection.lossRate * 100))
                    if let localAddr = connection.tunnel?.localAddr.url {
                        CopyableDetailRow(label: LocalizedStringKey("本地地址"), value: localAddr)
                    }
                    if let remoteAddr = connection.tunnel?.remoteAddr.url {
                        CopyableDetailRow(label: LocalizedStringKey("远程地址"), value: remoteAddr)
                    }

                    if let stats = connection.stats {
                        CopyableDetailRow(label: LocalizedStringKey("接收"), value: formatBytes(stats.rxBytes))
                        CopyableDetailRow(label: LocalizedStringKey("发送"), value: formatBytes(stats.txBytes))
                        CopyableDetailRow(label: LocalizedStringKey("延迟"), value: String(format: "%.1f ms", Double(stats.latencyUs) / 1000.0))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var basicSections: some View {
        Section(header: Text(LocalizedStringKey("基础信息"))) {
            CopyableDetailRow(label: LocalizedStringKey("主机名"), value: peer.hostname)
            CopyableDetailRow(label: LocalizedStringKey("虚拟 IP"), value: peer.ipv4)
            CopyableDetailRow(label: LocalizedStringKey("版本"), value: peer.version)
        }
        Section(header: Text(LocalizedStringKey("网络信息"))) {
            CopyableDetailRow(label: LocalizedStringKey("代价"), value: peer.cost)
            CopyableDetailRow(label: LocalizedStringKey("延迟"), value: peer.latency + " ms")
            CopyableDetailRow(label: LocalizedStringKey("丢包率"), value: peer.loss)
            CopyableDetailRow(label: LocalizedStringKey("隧道方式"), value: peer.tunnel)
        }
    }

    private func connectionTitle(for connection: SpotierStatus.PeerConnInfo, index: Int) -> LocalizedStringKey {
        if let tunnelType = connection.tunnel?.tunnelType {
            return LocalizedStringKey("连接 \(index + 1) [\(tunnelType)]")
        }
        return LocalizedStringKey("连接 \(index + 1)")
    }

    private func formatFlags(_ flags: SpotierStatus.PeerFeatureFlag) -> String {
        var parts = [String]()
        if flags.isPublicServer { parts.append("public_server") }
        if flags.avoidRelayData { parts.append("avoid_relay") }
        if flags.kcpInput { parts.append("kcp_input") }
        if flags.noRelayKcp { parts.append("no_relay_kcp") }
        if flags.supportConnListSync { parts.append("conn_list_sync") }
        return parts.joined(separator: ", ")
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kilobytes = Double(bytes) / 1024.0
        if kilobytes < 1024 { return String(format: "%.1f KB", kilobytes) }
        let megabytes = kilobytes / 1024.0
        if megabytes < 1024 { return String(format: "%.1f MB", megabytes) }
        return String(format: "%.2f GB", megabytes / 1024.0)
    }
}

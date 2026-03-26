import Foundation

enum SpotierConfigCodec {
    static func parse(_ content: String) -> SpotierConfigModel {
        var model = SpotierConfigModel()
        let lines = content.components(separatedBy: .newlines)
        var currentSection = ""

        model.manualPeers = []
        model.listeners = []
        model.mappedListeners = []
        model.relayNetworkWhitelist = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("[") {
                if trimmed.hasPrefix("[[") {
                    currentSection = String(trimmed.dropFirst(2).dropLast(2))
                    if currentSection == "proxy_network" { model.proxySubnets.append(SpotierConfigModel.ProxySubnet()) }
                    if currentSection == "port_forward" { model.portForwards.append(PortForwardRule()) }
                } else {
                    currentSection = String(trimmed.dropFirst().dropLast())
                    if currentSection == "vpn_portal_config" { model.enableVpnPortal = true }
                }
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count != 2 { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var val = parts[1].trimmingCharacters(in: .whitespaces)
            if val.hasPrefix("\"") && val.hasSuffix("\"") {
                val = String(val.dropFirst().dropLast())
            }

            if currentSection == "" || currentSection == "network_identity" || currentSection == "flags" {
                switch key {
                case "instance_name":
                    model.instanceName = val
                case "instance_id":
                    model.instanceId = val
                case "ipv4":
                    let components = val.split(separator: "/")
                    if components.count == 2 {
                        model.ipv4 = String(components[0])
                        model.cidr = String(components[1])
                    }
                case "dhcp":
                    model.dhcp = (val == "true")
                case "mtu":
                    model.mtu = Int(val) ?? 1380
                case "network_name":
                    model.networkName = val
                case "network_secret":
                    model.networkSecret = val
                case "listeners":
                    model.listeners = parseStringArray(val)
                case "mapped_listeners":
                    model.mappedListeners = parseStringArray(val)
                case "socks5_proxy":
                    model.enableSocks5 = true
                    if let portStr = val.split(separator: ":").last, let port = Int(portStr) {
                        model.socks5Port = port
                    }
                case "exit_nodes":
                    model.exitNodes = parseStringArray(val)
                case "routes":
                    model.enableManualRoutes = true
                    model.manualRoutes = parseStringArray(val)
                case "latency_first":
                    model.latencyFirst = (val == "true")
                case "disable_ipv6":
                    model.enableIPv6 = (val != "true")
                case "disable_encryption":
                    model.enableEncryption = (val != "true")
                case "use_smoltcp":
                    model.useSmoltcp = (val == "true")
                case "no_tun":
                    model.noTun = (val == "true")
                case "disable_p2p":
                    model.disableP2P = (val == "true")
                case "p2p_only":
                    model.onlyP2P = (val == "true")
                case "disable_udp_hole_punching":
                    model.disableUdpHolePunching = (val == "true")
                case "enable_exit_node":
                    model.enableExitNode = (val == "true")
                case "bind_device":
                    model.bindDevice = (val == "true")
                case "enable_kcp_proxy":
                    model.enableKcpProxy = (val == "true")
                case "disable_kcp_input":
                    model.disableKcpInput = (val == "true")
                case "enable_quic_proxy":
                    model.enableQuicProxy = (val == "true")
                case "disable_quic_input":
                    model.disableQuicInput = (val == "true")
                case "relay_all_peer_rpc":
                    model.relayAllPeerRpc = (val == "true")
                case "multi_thread":
                    model.multiThread = (val == "true")
                case "proxy_forward_by_system":
                    model.proxyForwardBySystem = (val == "true")
                case "disable_sym_hole_punching":
                    model.disableSymHolePunching = (val == "true")
                case "enable_magic_dns":
                    model.enableMagicDns = (val == "true")
                case "enable_private_mode":
                    model.enablePrivateMode = (val == "true")
                case "relay_network_whitelist":
                    model.enableRelayNetworkWhitelist = true
                    model.relayNetworkWhitelist = .init(values: val.replacingOccurrences(of: "\"", with: "").components(separatedBy: " ").filter { !$0.isEmpty })
                default:
                    break
                }
            } else if currentSection == "peer" {
                if key == "uri" {
                    model.manualPeers.append(EditableStringItem(value: val))
                    model.peerMode = .manual
                }
            } else if currentSection == "vpn_portal_config" {
                if key == "client_cidr" { model.vpnPortalClientCidr = val }
                if key == "wireguard_listen",
                   let portStr = val.split(separator: ":").last,
                   let port = Int(portStr) {
                    model.vpnPortalListenPort = port
                }
            } else if currentSection == "proxy_network" {
                if !model.proxySubnets.isEmpty {
                    var last = model.proxySubnets.removeLast()
                    if key == "cidr" { last.cidr = val }
                    model.proxySubnets.append(last)
                }
            } else if currentSection == "port_forward" {
                if !model.portForwards.isEmpty {
                    var last = model.portForwards.removeLast()
                    if key == "proto" { last.protocolType = val.uppercased() }
                    if key == "bind_addr" {
                        let components = val.split(separator: ":")
                        if components.count >= 2 {
                            last.bindPort = String(components.last!)
                            last.bindIp = components.dropLast().joined(separator: ":")
                        }
                    }
                    if key == "dst_addr" {
                        let components = val.split(separator: ":")
                        if components.count >= 2 {
                            last.targetPort = String(components.last!)
                            last.targetIp = components.dropLast().joined(separator: ":")
                        }
                    }
                    model.portForwards.append(last)
                }
            }
        }

        if model.listeners.isEmpty {
            model.listeners = .init(values: SpotierConfigModel.defaultListenerValues)
        }
        return model
    }

    static func generate(from model: SpotierConfigModel, peers: [String]) -> String {
        var toml = """
        instance_name = "\(model.instanceName)"
        instance_id = "\(model.instanceId)"
        dhcp = \(model.dhcp)
        """

        let listeners = model.listeners.values.filter { !$0.isEmpty }
        if !listeners.isEmpty {
            toml += "\nlisteners = [\(quotedList(listeners))]"
        }

        let mappedListeners = model.mappedListeners.values.filter { !$0.isEmpty }
        if !mappedListeners.isEmpty {
            toml += "\nmapped_listeners = [\(quotedList(mappedListeners))]"
        }

        if !model.dhcp && !model.ipv4.isEmpty {
            toml += "\nipv4 = \"\(model.ipv4)/\(model.cidr)\""
        }

        if model.enableSocks5 {
            toml += "\nsocks5_proxy = \"socks5://0.0.0.0:\(model.socks5Port)\""
        }

        let exitNodes = model.exitNodes.values.filter { !$0.isEmpty }
        if !exitNodes.isEmpty {
            toml += "\nexit_nodes = [\(quotedList(exitNodes))]"
        }

        let manualRoutes = model.manualRoutes.values.filter { !$0.isEmpty }
        if model.enableManualRoutes && !manualRoutes.isEmpty {
            toml += "\nroutes = [\(quotedList(manualRoutes))]"
        }

        toml += """

        [network_identity]
        network_name = "\(model.networkName)"
        network_secret = "\(model.networkSecret)"
        """

        for peer in peers where !peer.isEmpty {
            toml += "\n\n[[peer]]\nuri = \"\(peer)\""
        }

        var flags = ""
        flags += "\nmtu = \(model.mtu)"
        if model.latencyFirst { flags += "\nlatency_first = true" }
        if !model.enableIPv6 { flags += "\ndisable_ipv6 = true" }
        if !model.enableEncryption { flags += "\ndisable_encryption = true" }
        if model.useSmoltcp { flags += "\nuse_smoltcp = true" }
        if model.noTun { flags += "\nno_tun = true" }
        if model.disableP2P { flags += "\ndisable_p2p = true" }
        if model.onlyP2P { flags += "\np2p_only = true" }
        if model.disableUdpHolePunching { flags += "\ndisable_udp_hole_punching = true" }
        if model.enableExitNode { flags += "\nenable_exit_node = true" }
        if model.enableKcpProxy { flags += "\nenable_kcp_proxy = true" }
        if model.disableKcpInput { flags += "\ndisable_kcp_input = true" }
        if model.enableQuicProxy { flags += "\nenable_quic_proxy = true" }
        if model.disableQuicInput { flags += "\ndisable_quic_input = true" }
        if model.relayAllPeerRpc { flags += "\nrelay_all_peer_rpc = true" }
        if model.bindDevice { flags += "\nbind_device = true" }
        flags += "\nmulti_thread = \(model.multiThread)"
        if model.proxyForwardBySystem { flags += "\nproxy_forward_by_system = true" }
        if model.disableSymHolePunching { flags += "\ndisable_sym_hole_punching = true" }
        if model.enableMagicDns { flags += "\nenable_magic_dns = true" }
        if model.enablePrivateMode { flags += "\nenable_private_mode = true" }

        let relayWhitelist = model.relayNetworkWhitelist.values.filter { !$0.isEmpty }
        if model.enableRelayNetworkWhitelist && !relayWhitelist.isEmpty {
            flags += "\nrelay_network_whitelist = \"\(relayWhitelist.joined(separator: " "))\""
        }

        if !flags.isEmpty {
            toml += "\n\n[flags]" + flags
        }

        if model.enableVpnPortal {
            toml += """

            [vpn_portal_config]
            client_cidr = "\(model.vpnPortalClientCidr)"
            wireguard_listen = "0.0.0.0:\(model.vpnPortalListenPort)"
            """
        }

        for subnet in model.proxySubnets where !subnet.cidr.isEmpty {
            toml += """

            [[proxy_network]]
            cidr = "\(subnet.cidr)"
            """
        }

        for rule in model.portForwards where !rule.bindPort.isEmpty && !rule.targetPort.isEmpty {
            toml += """

            [[port_forward]]
            proto = "\(rule.protocolType.lowercased())"
            bind_addr = "\(rule.bindIp.isEmpty ? "0.0.0.0" : rule.bindIp):\(rule.bindPort)"
            dst_addr = "\(rule.targetIp):\(rule.targetPort)"
            """
        }

        return toml
    }

    private static func parseStringArray(_ value: String) -> [EditableStringItem] {
        guard value.hasPrefix("[") && value.hasSuffix("]") else { return [] }
        let inner = value.dropFirst().dropLast()
        return .init(values: inner.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        })
    }

    private static func quotedList(_ values: [String]) -> String {
        values.map { "\"\($0)\"" }.joined(separator: ", ")
    }
}

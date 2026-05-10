import Foundation

struct PeerInfo: Identifiable, Equatable {
    // 使用 sessionID 加上业务字段组合成唯一 ID
    // 这样每次启动生成新 sessionID 时，ID 都会变，从而强制触发 SwiftUI 的滑动进入动画
    let sessionID: UUID
    let ipv4: String
    let hostname: String
    let cost: String
    let latency: String
    let loss: String
    let rx: String
    let tx: String
    let tunnel: String
    let nat: String
    let version: String
    
    // 扩展字段：存储完整 JSON 信息中的所有键值对
    var extraInfo: [String: String] = [:]
    
    // 便捷访问器 (基于 Rust 常见命名惯例 snake_case)
    var nodeId: String? { extraInfo["id"] } // JSON key is 'id'
    var instanceId: String? { extraInfo["instance_id"] }
    // Route info (prefixed with route_)
    var nextHopHostname: String? { extraInfo["route_next_hop_hostname"] }
    var nextHopLatency: String? { extraInfo["route_next_hop_lat"] }
    var pathLen: String? { extraInfo["route_path_len"] }
    // Add more as needed based on observation
    
    // 针对远程节点的完整数据信息
    var fullData: SpotierStatus.PeerRoutePair? = nil
    // 针对“本机”节点的完整信息
    var myNodeData: SpotierStatus.NodeInfo? = nil
    
    // 运行中必须保证稳定且唯一的 id：否则 SwiftUI 会把同一节点当成“删除+新增”，或出现跳格/错位
    // 优先使用 route.peerId（数值通常最稳定、且唯一），再降级到 instId / nodeId，最后兜底 hostname+ipv4。
    private var stableKey: String {
        if let pid = fullData?.route.peerId {
            return "peerId:\(pid)"
        }
        if let inst = (fullData?.route.instId ?? instanceId), !inst.isEmpty {
            return "inst:\(inst)"
        }
        if let nid = nodeId, !nid.isEmpty {
            return "id:\(nid)"
        }
        // 兜底也要尽量唯一
        return "host:\(hostname)|ip:\(ipv4)|cost:\(cost)"
    }

    var id: String { stableKey }

    static func == (lhs: PeerInfo, rhs: PeerInfo) -> Bool {
        return lhs.ipv4 == rhs.ipv4 &&
               lhs.hostname == rhs.hostname &&
               lhs.latency == rhs.latency &&
               lhs.rx == rhs.rx &&
               lhs.tx == rhs.tx &&
               lhs.loss == rhs.loss &&
               lhs.cost == rhs.cost &&
               lhs.tunnel == rhs.tunnel &&
               lhs.nat == rhs.nat &&
               lhs.version == rhs.version &&
               lhs.extraInfo == rhs.extraInfo &&
               lhs.fullData == rhs.fullData &&
               lhs.myNodeData == rhs.myNodeData
    }
}

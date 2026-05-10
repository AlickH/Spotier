import SwiftUI

struct PeerCard: View, Equatable {
    let peer: PeerInfo
    
    static func == (lhs: PeerCard, rhs: PeerCard) -> Bool {
        lhs.peer == rhs.peer
    }

    @State private var showDetail = false
    
    private var shortVersion: String {
        String(peer.version.split(separator: "-").first ?? Substring(peer.version))
    }
    
    private func formatSpeed(_ speedStr: String) -> String {
        // If it already has units (from Table output), e.g. "10.5 KB"
        if speedStr.contains(" ") {
            return speedStr
        }
        
        // If it is a raw number (from JSON output), e.g. "10240"
        if let bytes = Double(speedStr) {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB] // Adjust as needed
            formatter.countStyle = .binary // 1024
            formatter.includesUnit = true
            return formatter.string(fromByteCount: Int64(bytes))
        }
        
        return speedStr
    }

    // MARK: - Helpers

    private func clean(_ text: String) -> String {
        // Strip ANSI codes and whitespace
        text.replacingOccurrences(of: "\\x1b\\[[0-9;]*m", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Translation & Color Helpers
    
    private func translateTunnel(_ raw: String) -> String {
        let text = clean(raw)
        let lower = text.lowercased()
        
        if lower == "local" { return "Local" }
        if lower == "p2p" { return "P2P" }
        // Remove forced replacement for p2p to allow "P2P" or "P2P(x)" to show naturally
        
        if lower == "relay" { return "Relay" }
        // Remove forced replacement for relay
        
        // Capitalize first letter for other cases if needed, or return as is
        if lower.starts(with: "relay") { return text.replacingOccurrences(of: "relay", with: "Relay", options: .caseInsensitive) }
        
        return text
    }
    
    private func translateNAT(_ raw: String) -> String {
        let text = clean(raw)
        let lower = text.lowercased()
        if lower == "nopat" { return "No PAT" }
        
        if lower.hasPrefix("openinternet") { return "Open" }
        if lower.hasPrefix("fullcone") { return "Full Cone" }
        if lower.hasPrefix("symmetric") { return "Symmetric" }
        
        if lower.contains("portrestricted") { return "Port Restricted" }
        if lower.contains("restricted") { return "Restricted" }
        
        return text
    }
    
    private func natColor(for text: String) -> Color {
        let t = text.lowercased()
        if t.contains("全锥形") || t.contains("full cone") || t.contains("开放") || t.contains("open") || t.contains("一对一") || t.contains("no pat") { return .blue }
        if t.contains("对称") || t.contains("symmetric") { return .red }
        if t.contains("端口受限") || t.contains("port restricted") { return .orange }
        if t.contains("受限") || t.contains("restricted") { return .yellow }
        return .gray
    }
    
    private func tagColor(for text: String) -> Color {
        let t = text.lowercased()
        // Tunnel Colors
        if t.contains("直连") || t.contains("p2p") { return .blue }
        if t.contains("中转") || t.contains("relay") { return .purple }
        if t.contains("本机") || t.contains("local") { return .gray }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. Title
            HStack(alignment: .center, spacing: 0) {
                ScrollingText(text: peer.hostname.isEmpty ? "未知节点" : peer.hostname)
                    .frame(height: 18)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 8)
                
                Button(action: { showDetail = true }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDetail) {
                    PeerDetailView(peer: peer)
                        .frame(width: 320, height: 450)
                }
            }

            // 2. IP & Latency
            HStack {
                Text(peer.ipv4.isEmpty ? peer.hostname : peer.ipv4)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                if !peer.latency.isEmpty {
                    Text("\(peer.latency) ms")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                }
            }

            // 3. Speed & Loss
            HStack(spacing: 0) {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8))
                    Text(formatSpeed(peer.rx))
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 1) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8))
                    Text(formatSpeed(peer.tx))
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(peer.loss.isEmpty ? "0.0%" : peer.loss)
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .lineLimit(1)

            // 4. Tags
            let tTunnel = translateTunnel(peer.tunnel)
            let tNat = translateNAT(peer.nat)
            let tCost = translateTunnel(peer.cost)

            HStack(spacing: 6) {
                Tag(text: LocalizedStringKey(tCost), color: tagColor(for: tCost))
                Tag(text: LocalizedStringKey(tTunnel), color: tagColor(for: tTunnel))
                if !tNat.isEmpty {
                    Tag(text: LocalizedStringKey(tNat), color: natColor(for: tNat))
                }
                Tag(text: LocalizedStringKey(shortVersion), color: .gray)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6)) // Match SpeedCard background
            .background(borderColor.opacity(0.05)) // Add subtle tint to match SpeedCard's visual weight
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor.opacity(0.6), lineWidth: 1) // Increased opacity for better visibility
            )
            .clipShape(RoundedRectangle(cornerRadius: 12)) // Ensure background tint is clipped
    }
    
    // Logic to determine border color based on Peer Type
    private var borderColor: Color {
        // 1. Local (本机)
        let tunnelLower = peer.tunnel.lowercased()
        if tunnelLower == "local" || peer.ipv4.lowercased().contains("local") {
            return .blue
        }
        
        // 2. Public Peer (Public)
        if peer.ipv4.isEmpty || 
           peer.ipv4.lowercased().contains("public") || 
           peer.hostname.lowercased().contains("public") {
            return .red
        }
        
        // 3. Remote (远端机器) - Changed from .yellow to .green for visibility
        return .green
    }
}

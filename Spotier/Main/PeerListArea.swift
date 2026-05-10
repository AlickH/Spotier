import SwiftUI

struct PeerListArea: View {
    @StateObject private var runner = SpotierRunner.shared

    private let gridRows = [
        GridItem(.fixed(105), spacing: 12),
        GridItem(.fixed(105), spacing: 12)
    ]

    var body: some View {
        let peerIDs = runner.peers.map(\.id)

        return VStack {
            Spacer()

            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: gridRows, spacing: 12) {
                        ForEach(runner.peers) { peer in
                            PeerCard(peer: peer)
                                .equatable()
                                .frame(width: DashboardLayoutMetrics.peerCardWidth)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                        }
                    }
                    .padding(.horizontal, DashboardLayoutMetrics.speedDashboardHorizontalPadding)
                    .contentShape(Rectangle())
                }
                .preventVerticalBounce()
                .frame(height: DashboardLayoutMetrics.peerAreaHeight)

                if runner.isRunning && runner.peers.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.2).controlSize(.large)
                        Text(LocalizedStringKey("节点加载中"))
                            .font(.title3.bold())
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DashboardLayoutMetrics.peerAreaHeight)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: DashboardLayoutMetrics.peerAreaHeight)
            .padding(.bottom, DashboardLayoutMetrics.peerAreaBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: peerIDs)
    }
}

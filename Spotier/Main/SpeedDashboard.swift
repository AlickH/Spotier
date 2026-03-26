import SwiftUI
import NetworkExtension

struct SpeedCard: View, Equatable {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let history: [Double]
    let maxVal: Double
    let isVisible: Bool
    let isPaused: Bool

    static func == (lhs: SpeedCard, rhs: SpeedCard) -> Bool {
        lhs.value == rhs.value &&
        lhs.history == rhs.history &&
        lhs.maxVal == rhs.maxVal &&
        lhs.isVisible == rhs.isVisible &&
        lhs.isPaused == rhs.isPaused
    }

    private var splitValue: (number: String, unit: String) {
        let components = value.components(separatedBy: " ")
        if components.count >= 2 {
            return (components[0], components[1])
        }
        return (value, "")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SmartSparklineView(data: history, color: color, maxScale: maxVal, paused: isPaused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 24)
                .zIndex(0)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 10, weight: .bold))
                    Text(title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(color.opacity(0.8))
                }
                .padding(.top, 10)

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(splitValue.number)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                    Text(splitValue.unit)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 12)
            .zIndex(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 85)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct SpeedDashboard: View {
    let geoSize: CGSize
    let buttonCenterY: CGFloat
    let isPaused: Bool
    let isConnected: Bool
    let status: NEVPNStatus
    let canToggleConnection: Bool
    let onToggleConnection: () -> Void

    @ObservedObject private var runner = SpotierRunner.shared

    var body: some View {
        let maxSpeed = runner.maxHistorySpeed

        HStack(spacing: -6) {
            if runner.isRunning && runner.isWindowVisible {
                SpeedCard(
                    title: "DOWNLOAD",
                    value: runner.downloadSpeed,
                    icon: "arrow.down.square.fill",
                    color: .blue,
                    history: runner.downloadHistory,
                    maxVal: maxSpeed,
                    isVisible: true,
                    isPaused: isPaused
                )
                .equatable()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button(action: onToggleConnection) {
                StartStopButtonCore(
                    isRunning: isConnected,
                    uptimeText: runner.uptimeText,
                    status: status
                )
            }
            .buttonStyle(.plain)
            .disabled(!canToggleConnection)
            .zIndex(20)

            if runner.isRunning && runner.isWindowVisible {
                SpeedCard(
                    title: "UPLOAD",
                    value: runner.uploadSpeed,
                    icon: "arrow.up.square.fill",
                    color: .orange,
                    history: runner.uploadHistory,
                    maxVal: maxSpeed,
                    isVisible: true,
                    isPaused: isPaused
                )
                .equatable()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(width: geoSize.width)
        .position(x: geoSize.width / 2, y: buttonCenterY)
    }
}

struct StartStopButtonCore: View {
    let isRunning: Bool
    let uptimeText: String
    var status: NEVPNStatus = .disconnected

    var body: some View {
        ZStack {
            Circle()
                .fill(buttonColor)
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(isRunning ? 0.12 : 0.25), radius: 10, y: 4)

            if status == .connecting || status == .disconnecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .controlSize(.regular)
            } else {
                Image(systemName: "power")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(isRunning ? Color.black : Color.white)
            }

            if isRunning {
                Text(uptimeText)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 140)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .offset(y: -113)
            }
        }
        .frame(width: 84, height: 84)
        .padding(.vertical, 6)
    }

    private var buttonColor: Color {
        if isRunning { return .white }
        switch status {
        case .connecting, .disconnecting: return .orange
        case .connected: return .white
        case .disconnected, .invalid: return .blue
        case .reasserting: return .yellow
        @unknown default: return .blue
        }
    }
}

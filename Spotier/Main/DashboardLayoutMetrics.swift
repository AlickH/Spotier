import CoreGraphics

enum DashboardLayoutMetrics {
    static let windowWidth: CGFloat = 420
    static let windowHeight: CGFloat = 520
    static let rippleSize: CGFloat = 500
    static let peerCardWidth: CGFloat = 188
    static let peerAreaHeight: CGFloat = 222
    static let peerAreaBottomPadding: CGFloat = 16
    static let headerPadding: CGFloat = 12
    static let speedDashboardHorizontalPadding: CGFloat = 16
    static let runningButtonCenterY: CGFloat = 133

    static func buttonCenterY(isRunning: Bool, contentHeight: CGFloat) -> CGFloat {
        isRunning ? runningButtonCenterY : (contentHeight / 2)
    }
}

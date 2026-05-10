import SwiftUI
import AppKit
import Combine
import NetworkExtension

@main
struct SpotierControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var runner = SpotierRunner.shared
    @StateObject private var iconState = MenuBarIconState.shared

    init() {
        UserDefaults.standard.register(defaults: [
            "connectOnStart": true,
            "breathEffect": true
        ])
    }
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            MenuBarLabelView(iconState: iconState)
        }
        .menuBarExtraStyle(.window)
    }
}

// 优化：将 Label 提取为独立 View 隔离刷新
struct MenuBarLabelView: View {
    @ObservedObject var iconState: MenuBarIconState
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconState.currentIcon)
        }
    }
}

// 菜单栏图标状态管理
@MainActor
class MenuBarIconState: ObservableObject {
    static let shared = MenuBarIconState()
    
    @Published var currentIcon: String = "point.3.connected.trianglepath.dotted"
    
    private let iconOutline = "point.3.connected.trianglepath.dotted"
    private let iconFilled = "point.3.filled.connected.trianglepath.dotted"
    private var isShowingFilled = true
    private var animationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 优化：监听运行状态变化，按需启停 Timer
        SpotierRunner.shared.$isRunning
            .sink { [weak self] isRunning in
                self?.handleRunningStateChange(isRunning: isRunning)
            }
            .store(in: &cancellables)
        
        // 监听 breathEffect 设置变化
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.updateTimerState()
            }
            .store(in: &cancellables)
    }
    
    private func handleRunningStateChange(isRunning: Bool) {
        updateIcon(isRunning: isRunning)
        updateTimerState()
    }
    
    private func updateTimerState() {
        let isRunning = SpotierRunner.shared.isRunning
        let blinkEnabled = UserDefaults.standard.bool(forKey: "breathEffect")
        
        if isRunning && blinkEnabled {
            startTimer()
        } else {
            stopTimer()
        }
    }
    
    private func startTimer() {
        // 优化：避免重复启动
        guard animationTimer == nil else { return }
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickAnimation()
            }
        }
    }
    
    private func stopTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    private func updateIcon(isRunning: Bool) {
        isShowingFilled = true
        currentIcon = isRunning ? iconFilled : iconOutline
    }

    private func tickAnimation() {
        isShowingFilled.toggle()
        currentIcon = isShowingFilled ? iconFilled : iconOutline
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let selectedConfigPathDefaultsKey = "selected_config_path"
    private var cancellables = Set<AnyCancellable>()
    private let configRepository: ConfigFileAccessing = ConfigFileRepository.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // 等待 VPNManager 加载完成后同步状态
        // Connect On Demand 由系统管理自动连接，App 只需同步 UI 状态
        waitForVPNReady()
    }
    
    // MARK: - Lifecycle
    
    func applicationWillTerminate(_ notification: Notification) {
        // NE 由系统通过 Connect On Demand 管理，App 退出不影响 VPN 连接
    }
    
    // MARK: - VPN State Sync
    
    private func waitForVPNReady() {
        VPNManager.shared.$isReady
            .filter { $0 }
            .first()
            .sink { [weak self] _ in
                self?.syncStateOnLaunch()
            }
            .store(in: &cancellables)
    }
    
    private func syncStateOnLaunch() {
        let vpn = VPNManager.shared
        let connectOnStart = UserDefaults.standard.bool(forKey: "connectOnStart")
        print("[Launch] VPN status: \(vpn.status.rawValue), isConnected: \(vpn.isConnected), onDemand: \(vpn.isOnDemandEnabled)")
        
        // 同步 Runner 的 UI 状态
        SpotierRunner.shared.syncWithVPNState()
        
        // 如果 NE 已经在运行，不做任何操作，避免 saveToPreferences 导致隧道重启
        if vpn.isConnected || vpn.status == .connecting {
            print("[Launch] NE already running, skip")
            return
        }
        
        // NE 未运行时，确保 On Demand 规则与用户设置一致
        if vpn.isOnDemandEnabled != connectOnStart {
            vpn.updateOnDemand(enabled: connectOnStart)
        }
        
        // 如果开启了自动连接，手动触发一次（首次安装或 On Demand 尚未生效时）
        if connectOnStart {
            let configs = configRepository.refreshConfigs()
            if let savedPath = UserDefaults.standard.string(forKey: Self.selectedConfigPathDefaultsKey),
               let config = configs.first(where: { $0.path == savedPath }) {
                print("[Launch] Triggering initial connect with: \(config.lastPathComponent)")
                SpotierRunner.shared.toggleService(configPath: config.path)
            }
        }
    }
}

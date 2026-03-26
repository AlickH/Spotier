import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var runner = SpotierRunner.shared
    @ObservedObject private var vpnManager = VPNManager.shared
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var dashboardState = MainDashboardState()
    
    var body: some View {
        ZStack {
            if runner.isWindowVisible {
                VStack(spacing: 0) {
                    MainDashboardHeader(
                        configFiles: configManager.configFiles,
                        selectedConfig: dashboardState.selectedConfig,
                        iCloudDriveEnabled: configManager.iCloudDriveEnabled,
                        hasICloudIdentity: FileManager.default.ubiquityIdentityToken != nil,
                        onSelectConfig: dashboardState.selectConfig,
                        onCreateNetwork: dashboardState.openCreatePrompt,
                        onOpenGenerator: { dashboardState.openOverlay(.generator) },
                        onOpenEditor: dashboardState.openEditor,
                        onDisableICloudDrive: { configManager.disableICloudDrive() },
                        onEnableICloudDrive: { configManager.enableICloudDrive() },
                        onSelectFolder: { configManager.selectCustomFolder() },
                        onOpenFolder: { configManager.openiCloudFolder() },
                        onDeleteSelected: dashboardState.deleteSelectedConfig,
                        onOpenLog: { dashboardState.openOverlay(.log) },
                        onOpenSettings: { dashboardState.openOverlay(.settings) },
                        onQuit: { NSApplication.shared.terminate(nil) }
                    )
                    
                    ZStack {
                        if !dashboardState.isAnyOverlayShown {
                            contentArea
                        } else {
                            // 覆盖层显示时，用透明占位保持几何结构稳固
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: DashboardLayoutMetrics.windowWidth, height: DashboardLayoutMetrics.windowHeight, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.01)) // 确保点击区域
            } else {
                Color.clear
                    .frame(width: DashboardLayoutMetrics.windowWidth, height: DashboardLayoutMetrics.windowHeight)
            }
            overlayView
        }
        .onAppear {
            // 加载 VPN 配置
            VPNManager.shared.loadManager()
            
            
            // 初始启动时刷新一次列表
            dashboardState.handleConfigFilesChanged(configManager.refreshConfigs())
            
            // 设置窗口可见，开始动画
            runner.isWindowVisible = true
        }
        .onChange(of: configManager.configFiles) { dashboardState.handleConfigFilesChanged($0) }
        .onDisappear {
            runner.isWindowVisible = false
        }
        .lockVerticalScroll() // 🔒 Global Lock: Prevents the entire window container from bouncing
    }
    
    private var contentArea: some View {
        GeometryReader { geo in
            ZStack {
                // 1) 水波纹层 (放在最底层) - UIKit 高性能实现
                if runner.isRunning && runner.isWindowVisible {
                    RippleRingsView(isVisible: true, duration: 4.0, maxScale: 5.5)
                        .frame(width: DashboardLayoutMetrics.rippleSize, height: DashboardLayoutMetrics.rippleSize)
                        .position(
                            x: geo.size.width / 2,
                            y: DashboardLayoutMetrics.buttonCenterY(
                                isRunning: runner.isRunning,
                                contentHeight: geo.size.height
                            )
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity) // Fade in
                        .zIndex(0)
                }

                // 2) 节点列表区域 - 使用独立组件隔离刷新
                if runner.isRunning && runner.isWindowVisible && !dashboardState.isAnyOverlayShown {
                    PeerListArea()
                        .id(runner.sessionID)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }

                // 3) 启动按钮与网速仪表盘层 - 使用独立组件隔离刷新
                if runner.isWindowVisible {
                    SpeedDashboard(
                        geoSize: geo.size,
                        buttonCenterY: DashboardLayoutMetrics.buttonCenterY(
                            isRunning: runner.isRunning,
                            contentHeight: geo.size.height
                        ),
                        isPaused: dashboardState.isAnyOverlayShown,
                        isConnected: vpnManager.isConnected,
                        status: vpnManager.status,
                        canToggleConnection: dashboardState.canToggleConnection,
                        onToggleConnection: dashboardState.toggleConnection
                    )
                    .zIndex(10)
                }
            }
            .animation(.spring(response: 1.0, dampingFraction: 0.8), value: runner.isRunning)
            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: dashboardState.overlayRoute)
            .blur(radius: dashboardState.isAnyOverlayShown ? 10 : 0)
            .opacity(dashboardState.isAnyOverlayShown ? 0.3 : 1.0)
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        if let route = dashboardState.overlayRoute {
            switch route {
            case .log:
                LogView(isPresented: overlayBinding(for: .log))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                    .compositingGroup()
                    .zIndex(100)
                    .transition(.move(edge: .bottom))

            case .settings:
                SettingsView(isPresented: overlayBinding(for: .settings))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                    .zIndex(101)
                    .transition(.move(edge: .bottom))

            case let .editor(url):
                ConfigEditorView(
                    isPresented: Binding(
                        get: { dashboardState.editingConfigURL == url },
                        set: { if !$0 { dashboardState.closeOverlay() } }
                    ),
                    fileURL: url
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
                .zIndex(102)
                .transition(.move(edge: .bottom))

            case .generator:
                ConfigGeneratorView(
                    isPresented: overlayBinding(for: .generator),
                    editingFileURL: dashboardState.selectedConfig,
                    onSave: { dashboardState.handleConfigFilesChanged(configManager.refreshConfigs()) }
                )
                .id(dashboardState.selectedConfig)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(103)
                .transition(.move(edge: .bottom))

            case .createPrompt:
                Color.black.opacity(0.3)
                    .zIndex(104)
                    .onTapGesture { dashboardState.closeCreatePrompt() }

                CreateConfigPrompt(
                    newConfigName: $dashboardState.newConfigName,
                    errorMessage: dashboardState.createConfigError,
                    onCancel: dashboardState.closeCreatePrompt,
                    onConfirm: dashboardState.createConfig
                )
                .zIndex(105)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    // MARK: - Helper Functions

    private func overlayBinding(for route: DashboardOverlayRoute) -> Binding<Bool> {
        Binding(
            get: { dashboardState.isPresenting(route) },
            set: { isPresented in
                if isPresented {
                    dashboardState.openOverlay(route)
                } else if dashboardState.isPresenting(route) {
                    dashboardState.closeOverlay()
                }
            }
        )
    }
}

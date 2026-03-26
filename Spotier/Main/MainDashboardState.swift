import Foundation
import Combine
import SwiftUI

@MainActor
final class MainDashboardState: ObservableObject {
    private static let selectedConfigPathDefaultsKey = "selected_config_path"

    @Published private(set) var selectedConfig: URL?
    @Published private(set) var overlayRoute: DashboardOverlayRoute?
    @Published var newConfigName = ""
    @Published private(set) var createConfigError: String?

    private let configRepository: ConfigFileAccessing
    private let connectionUseCase: MainConnectionUseCase

    convenience init() {
        self.init(
            initialConfigFiles: [],
            configRepository: ConfigFileRepository.shared,
            vpnController: VPNManager.shared
        )
    }

    convenience init(configRepository: ConfigFileAccessing) {
        self.init(
            initialConfigFiles: [],
            configRepository: configRepository,
            vpnController: VPNManager.shared
        )
    }

    init(
        initialConfigFiles: [URL],
        configRepository: ConfigFileAccessing,
        vpnController: VPNControlling
    ) {
        self.configRepository = configRepository
        self.connectionUseCase = MainConnectionUseCase(
            configRepository: configRepository,
            vpnController: vpnController
        )
        syncSelection(with: initialConfigFiles)
    }

    var isAnyOverlayShown: Bool {
        overlayRoute != nil
    }

    var editingConfigURL: URL? {
        guard case let .editor(url) = overlayRoute else { return nil }
        return url
    }

    var canToggleConnection: Bool {
        connectionUseCase.canToggleConnection(selectedConfig: selectedConfig)
    }

    func selectConfig(_ url: URL) {
        selectedConfig = url
        UserDefaults.standard.set(url.path, forKey: Self.selectedConfigPathDefaultsKey)
    }

    func handleConfigFilesChanged(_ files: [URL]) {
        syncSelection(with: files)
    }

    func isPresenting(_ route: DashboardOverlayRoute) -> Bool {
        overlayRoute == route
    }

    func openOverlay(_ route: DashboardOverlayRoute) {
        withAnimation {
            overlayRoute = route
        }
    }

    func closeOverlay() {
        withAnimation {
            overlayRoute = nil
        }
    }

    func openEditor() {
        guard let selectedConfig else { return }
        openOverlay(.editor(selectedConfig))
    }

    func openCreatePrompt() {
        newConfigName = ""
        createConfigError = nil
        openOverlay(.createPrompt)
    }

    func closeCreatePrompt() {
        createConfigError = nil
        closeOverlay()
    }

    func createConfig() {
        let filename = ConfigTemplateFactory.filename(from: newConfigName)
        let content = ConfigTemplateFactory.content(for: newConfigName)

        do {
            _ = try configRepository.createConfig(named: filename, content: content)
            let updatedFiles = configRepository.refreshConfigs()

            createConfigError = nil
            if let newURL = updatedFiles.first(where: { $0.lastPathComponent == filename }) {
                selectConfig(newURL)
                openOverlay(.generator)
            } else {
                closeCreatePrompt()
            }
        } catch {
            createConfigError = "创建失败: \(error.localizedDescription)"
            print("Failed to create file: \(error)")
        }
    }

    func deleteSelectedConfig() {
        guard let selectedConfig else { return }
        configRepository.deleteConfig(at: selectedConfig)
    }

    func toggleConnection() {
        connectionUseCase.toggleConnection(selectedConfig: selectedConfig)
    }

    private func syncSelection(with files: [URL]) {
        let nextSelection: URL?
        if let savedPath = UserDefaults.standard.string(forKey: Self.selectedConfigPathDefaultsKey) {
            nextSelection = files.first { $0.path == savedPath }
                ?? currentSelection(in: files)
        } else {
            nextSelection = currentSelection(in: files)
        }
        selectedConfig = nextSelection
        if let nextSelection {
            UserDefaults.standard.set(nextSelection.path, forKey: Self.selectedConfigPathDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedConfigPathDefaultsKey)
        }
    }

    private func currentSelection(in files: [URL]) -> URL? {
        guard !files.isEmpty else { return nil }
        if let selectedConfig, files.contains(selectedConfig) {
            return selectedConfig
        }
        return files.first
    }
}

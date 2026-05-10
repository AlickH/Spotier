import Foundation

protocol VPNControlling: AnyObject {
    var isConnected: Bool { get }
    var statusText: String { get set }

    func startVPN(configContent: String)
    func disableOnDemandAndStop()
}

struct MainConnectionUseCase {
    let configRepository: ConfigFileAccessing
    let vpnController: VPNControlling

    func canToggleConnection(selectedConfig: URL?) -> Bool {
        vpnController.isConnected || selectedConfig != nil
    }

    func toggleConnection(selectedConfig: URL?) {
        if vpnController.isConnected {
            vpnController.disableOnDemandAndStop()
            return
        }

        guard let selectedConfig else {
            vpnController.statusText = "未选择配置文件"
            return
        }

        do {
            let content = try configRepository.readContent(at: selectedConfig)
            vpnController.startVPN(configContent: content)
        } catch {
            vpnController.statusText = "读取配置失败: \(selectedConfig.lastPathComponent)"
            print("无法读取配置文件: \(selectedConfig.path)")
        }
    }
}

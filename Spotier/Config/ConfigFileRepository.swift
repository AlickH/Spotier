import Foundation

protocol ConfigFileAccessing {
    func refreshConfigs() -> [URL]
    func readContent(at fileURL: URL) throws -> String
    func createConfig(named filename: String, content: String) throws -> URL
    func updateContent(at fileURL: URL, content: String) throws
    func deleteConfig(at fileURL: URL)
}

struct ConfigFileRepository: ConfigFileAccessing {
    static let shared = ConfigFileRepository()

    private let manager: ConfigManager

    init(manager: ConfigManager = .shared) {
        self.manager = manager
    }

    @discardableResult
    func refreshConfigs() -> [URL] {
        manager.refreshConfigs()
    }

    func readContent(at fileURL: URL) throws -> String {
        try manager.readConfigContent(fileURL)
    }

    func createConfig(named filename: String, content: String) throws -> URL {
        try manager.createConfig(named: filename, content: content)
    }

    func updateContent(at fileURL: URL, content: String) throws {
        try manager.updateConfig(fileURL, content: content)
    }

    func deleteConfig(at fileURL: URL) {
        manager.deleteConfig(fileURL)
    }
}

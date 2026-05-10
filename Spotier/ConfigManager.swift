import Foundation
import Combine
import SwiftUI
import AppKit

enum ConfigAccessError: LocalizedError {
    case missingDirectory
    case fileAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .missingDirectory:
            return "请先选择配置目录"
        case let .fileAlreadyExists(name):
            return "文件已存在: \(name)"
        }
    }
}

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var configFiles: [URL] = []
    @AppStorage("custom_config_path") var customPathString: String = ""
    @AppStorage("custom_config_bookmark") var customPathBookmark: Data?
    @AppStorage("icloud_drive_enabled") var iCloudDriveEnabled: Bool = false
    private let directoryAccess = ConfigDirectoryAccess()
    private var localDirectory: URL? {
        directoryAccess.defaultLocalDirectory()
    }
    private var iCloudDriveDirectory: URL? {
        directoryAccess.iCloudDriveDirectory()
    }
    private var legacyICloudDriveDirectory: URL? {
        directoryAccess.legacyICloudDriveDirectory()
    }

    var currentDirectory: URL? {
        iCloudDriveEnabled ? iCloudDriveDirectory : directoryFromUserPreference()
    }

    private init() {
        migrateLegacyICloudDriveDirectoryIfNeeded()

        let bookmarkPath = resolvedBookmarkPathForInitialization()
        var resolvedPath = customPathString
        var resolvedBookmark = customPathBookmark

        if let bookmarkPath, !resolvedPath.isEmpty, bookmarkPath != resolvedPath {
            resolvedBookmark = nil
            print("[ConfigManager] 清除残留书签: \(bookmarkPath) != \(customPathString)")
        }

        if iCloudDriveEnabled, let iCloudDriveDirectory {
            resolvedPath = iCloudDriveDirectory.path
            resolvedBookmark = nil
        } else if resolvedPath.isEmpty, let localDirectory {
            resolvedPath = localDirectory.path
        }

        customPathString = resolvedPath
        customPathBookmark = resolvedBookmark
        refreshConfigs()
    }

    func selectCustomFolder() {
        if iCloudDriveEnabled {
            print("iCloud Drive 存储已启用，已锁定配置目录。")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        customPathString = url.path

        do {
            customPathBookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            customPathBookmark = nil
            print("创建目录书签失败: \(error)")
        }

        refreshConfigs()
    }

    func openiCloudFolder() {
        guard let url = currentDirectory else { return }
        // 使用 selectFile 在 Finder 中显示目录，避免沙盒权限问题
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    private var isICloudEnabled: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func enableICloudDrive() {
        guard !iCloudDriveEnabled else { return }

        guard isICloudEnabled else {
            print("未检测到 iCloud 账户，无法启用 iCloud Drive。")
            return
        }

        enableICloudDriveStorage()
    }

    func disableICloudDrive() {
        guard iCloudDriveEnabled else { return }

        iCloudDriveEnabled = false

        if customPathString.isEmpty, let targetDir = localDirectory {
            customPathString = targetDir.path
        }

        _ = refreshConfigs()
    }

    @discardableResult
    func refreshConfigs() -> [URL] {
        guard let directory = currentDirectory else {
            configFiles = []
            return []
        }

        do {
            let tomlFiles = try directoryAccess.withScopedAccess(to: directory) { directoryURL in
                if !FileManager.default.fileExists(atPath: directoryURL.path) {
                    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                }

                return try FileManager.default
                    .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "toml" }
                    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            }

            configFiles = tomlFiles
            return tomlFiles
        } catch {
            print("读取配置文件列表失败: \(error) 路径: \(directory.path)")
            configFiles = []
            return []
        }
    }

    func readConfigContent(_ fileURL: URL) throws -> String {
        try directoryAccess.withScopedAccess(to: currentDirectory) { _ in
            return try String(contentsOf: fileURL, encoding: .utf8)
        }
    }

    func createConfig(named filename: String, content: String) throws -> URL {
        try directoryAccess.withScopedAccess(to: currentDirectory) { directoryURL in
            let fileURL = directoryURL.appendingPathComponent(filename)
            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ConfigAccessError.fileAlreadyExists(filename)
            }

            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }
    }

    func updateConfig(_ fileURL: URL, content: String) throws {
        try directoryAccess.withScopedAccess(to: currentDirectory) { _ in
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func deleteConfig(_ fileURL: URL) {
        do {
            try directoryAccess.withScopedAccess(to: currentDirectory) { _ in
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("删除配置失败: \(error)")
        }

        refreshConfigs()
    }

    private func directoryFromUserPreference() -> URL? {
        // 1. 优先尝试从书签恢复（支持沙盒访问）
        if let bookmark = customPathBookmark {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    customPathBookmark = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
                return url
            } catch {
                print("解析书签失败: \(error)")
                customPathBookmark = nil
            }
        }

        if !customPathString.isEmpty {
            return URL(fileURLWithPath: customPathString)
        }

        return localDirectory
    }

    private func enableICloudDriveStorage() {
        guard let targetDir = iCloudDriveDirectory else { return }

        migrateLegacyICloudDriveDirectoryIfNeeded()

        let sourceDir = directoryFromUserPreference()
        do {
            try migrateConfigsToDefaultDirectory(from: sourceDir, to: targetDir)
        } catch {
            print("迁移配置到 iCloud Drive 失败: \(error)")
            return
        }

        customPathBookmark = nil
        customPathString = targetDir.path
        iCloudDriveEnabled = true
        _ = refreshConfigs()
    }

    private func migrateLegacyICloudDriveDirectoryIfNeeded() {
        guard
            let legacyDir = legacyICloudDriveDirectory,
            let targetDir = iCloudDriveDirectory,
            FileManager.default.fileExists(atPath: legacyDir.path),
            legacyDir.standardizedFileURL != targetDir.standardizedFileURL
        else {
            return
        }

        do {
            try migrateConfigsToDefaultDirectory(from: legacyDir, to: targetDir)
            try FileManager.default.removeItem(at: legacyDir)
        } catch {
            print("迁移旧 iCloud Drive Configs 目录失败: \(error)")
        }
    }

    private func migrateConfigsToDefaultDirectory(from sourceDir: URL?, to targetDir: URL) throws {
        guard let sourceDir else { return }
        if sourceDir.standardizedFileURL == targetDir.standardizedFileURL { return }

        if !FileManager.default.fileExists(atPath: targetDir.path) {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        let isScoped = sourceDir.startAccessingSecurityScopedResource()
        defer { if isScoped { sourceDir.stopAccessingSecurityScopedResource() } }

        let items = try FileManager.default.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for sourceFile in items where sourceFile.pathExtension.lowercased() == "toml" {
            let targetFile = targetDir.appendingPathComponent(sourceFile.lastPathComponent)

            if !FileManager.default.fileExists(atPath: targetFile.path) {
                try FileManager.default.copyItem(at: sourceFile, to: targetFile)
                continue
            }

            let sourceDate = try sourceFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let targetDate = try targetFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

            if let sourceDate, let targetDate, sourceDate <= targetDate {
                continue
            }

            try FileManager.default.removeItem(at: targetFile)
            try FileManager.default.copyItem(at: sourceFile, to: targetFile)
        }
    }

    private func resolvedBookmarkPathForInitialization() -> String? {
        guard let bookmark = customPathBookmark, !customPathString.isEmpty else { return nil }

        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).path
        } catch {
            return nil
        }
    }
}

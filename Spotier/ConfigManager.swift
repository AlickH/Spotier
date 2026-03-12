import Foundation
import Combine
import SwiftUI
import AppKit

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var configFiles: [URL] = []
    @AppStorage("custom_config_path") var customPathString: String = ""
    @AppStorage("custom_config_bookmark") var customPathBookmark: Data?
    @AppStorage("cloudkit_sync_enabled") var cloudKitSyncEnabled: Bool = false
    private var isCloudSyncInProgress = false

    var currentDirectory: URL? {
        // 开启 CloudKit 后，强制只使用默认目录作为同步源
        if cloudKitSyncEnabled {
            return defaultLocalDirectory()
        }

        return directoryFromUserPreference()
    }

    private init() {
        // 修正：如果 customPathString 已指向 iCloud 容器，清除可能残留的旧书签
        // （旧书签可能指向桌面等非 iCloud 路径，导致 currentDirectory 返回错误位置）
        if let bookmark = customPathBookmark, !customPathString.isEmpty {
            var isStale = false
            if let bookmarkURL = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                let bookmarkPath = bookmarkURL.path
                // 书签路径与当前设置路径不一致，说明书签是残留的旧数据
                if bookmarkPath != customPathString {
                    print("[ConfigManager] 清除残留书签: \(bookmarkPath) != \(customPathString)")
                    self.customPathBookmark = nil
                }
            }
        }
        
        // 首次运行或未设置路径时，使用本地 Application Support 默认目录
        if customPathString.isEmpty {
            if let targetDir = defaultLocalDirectory() {
                self.customPathString = targetDir.path
            }
        }

        // 开启 CloudKit 后，强制回到默认目录
        if cloudKitSyncEnabled, let targetDir = defaultLocalDirectory() {
            self.customPathBookmark = nil
            self.customPathString = targetDir.path
        }
        refreshConfigs()
    }

    func selectCustomFolder() {
        if cloudKitSyncEnabled {
            print("CloudKit 同步已启用，已锁定默认目录。")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.customPathString = url.path
                
                // 沙盒适配：保存安全域书签 (Security Scoped Bookmark)
                if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    self.customPathBookmark = bookmark
                }
                
                self.refreshConfigs()
            }
        }
    }

    func openiCloudFolder() {
        guard let url = currentDirectory else { return }
        // 使用 selectFile 在 Finder 中显示目录，避免沙盒权限问题
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    func editConfigFile(url: URL) {
        NSWorkspace.shared.open(url)
    }

    private var isICloudEnabled: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func migrateToiCloud() {
        guard isICloudEnabled else {
            print("未检测到 iCloud 账户，无法启用 CloudKit 同步。")
            return
        }

        enableCloudKitSync()
    }

    @discardableResult
    func refreshConfigs() -> [URL] {
        refreshConfigs(skipCloudSync: false)
    }

    @discardableResult
    private func refreshConfigs(skipCloudSync: Bool) -> [URL] {
        guard let url = currentDirectory else {
            DispatchQueue.main.async { self.configFiles = [] }
            return []
        }
        
        // 关键修复：必须在访问前请求权限
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        
        do {
            // 再次确保目录存在（防止被外部删除）
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            
            let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let tomlFiles = items.filter { $0.pathExtension == "toml" }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            
            DispatchQueue.main.async {
                self.configFiles = tomlFiles
            }

            if !skipCloudSync {
                triggerCloudSyncIfNeeded(force: false)
            }

            return tomlFiles
        } catch {
            print("读取配置文件列表失败: \(error) 路径: \(url.path)")
            // 如果读取失败，尝试清空列表
            DispatchQueue.main.async {
                self.configFiles = []
            }
            return []
        }
    }

    func readConfigContent(_ fileURL: URL) throws -> String {
        // 如果有书签，说明是用户选定的安全域目录
        if let _ = customPathBookmark, let dirURL = currentDirectory {
            let isScoped = dirURL.startAccessingSecurityScopedResource()
            defer { if isScoped { dirURL.stopAccessingSecurityScopedResource() } }
            
            return try String(contentsOf: fileURL, encoding: .utf8)
        }
        
        // 普通路径直接读取
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func deleteConfig(_ fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            print("删除配置失败: \(error)")
        }

        if cloudKitSyncEnabled && isICloudEnabled {
            let fileName = fileURL.lastPathComponent
            Task.detached {
                do {
                    try await CloudKitConfigSync.shared.deleteConfig(named: fileName)
                } catch {
                    print("CloudKit 删除配置失败: \(error)")
                }
            }
        }

        refreshConfigs()
    }

    private func defaultLocalDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let targetDir = appSupport
            .appendingPathComponent("Spotier", isDirectory: true)
            .appendingPathComponent("Configs", isDirectory: true)

        if !FileManager.default.fileExists(atPath: targetDir.path) {
            try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        return targetDir
    }

    private func triggerCloudSyncIfNeeded(force: Bool) {
        guard cloudKitSyncEnabled else { return }
        guard isICloudEnabled else { return }
        guard !isCloudSyncInProgress || force else { return }
        guard let localDir = currentDirectory else { return }

        isCloudSyncInProgress = true

        Task.detached { [weak self] in
            guard let self else { return }

            do {
                let localChanged = try await CloudKitConfigSync.shared.sync(localDirectory: localDir)
                DispatchQueue.main.async {
                    self.isCloudSyncInProgress = false
                    if localChanged {
                        _ = self.refreshConfigs(skipCloudSync: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isCloudSyncInProgress = false
                    print("CloudKit 同步失败: \(error)")
                }
            }
        }
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
                    if let newBookmark = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        DispatchQueue.main.async { self.customPathBookmark = newBookmark }
                    }
                }
                return url
            } catch {
                print("解析书签失败: \(error)")
                DispatchQueue.main.async { self.customPathBookmark = nil }
            }
        }

        // 2. 尝试使用路径字符串（非沙盒或已授权路径）
        if !customPathString.isEmpty {
            return URL(fileURLWithPath: customPathString)
        }

        // 3. 默认使用 Application Support（更符合应用配置文件惯例）
        return defaultLocalDirectory()
    }

    private func enableCloudKitSync() {
        guard let targetDir = defaultLocalDirectory() else { return }

        // 在切换前先拿到用户当前目录，自动迁移配置，避免用户手动搬文件
        let sourceDir = directoryFromUserPreference()
        do {
            try migrateConfigsToDefaultDirectory(from: sourceDir, to: targetDir)
        } catch {
            print("迁移配置到默认目录失败: \(error)")
            return
        }

        customPathBookmark = nil
        customPathString = targetDir.path
        cloudKitSyncEnabled = true

        _ = refreshConfigs(skipCloudSync: true)
        triggerCloudSyncIfNeeded(force: true)
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

            let sourceDate = (try? sourceFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let targetDate = (try? targetFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast

            if sourceDate.timeIntervalSince(targetDate) > 1.0 {
                try FileManager.default.removeItem(at: targetFile)
                try FileManager.default.copyItem(at: sourceFile, to: targetFile)
            }
        }
    }
}

import Foundation

struct ConfigDirectoryAccess {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func defaultLocalDirectory() -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let targetDirectory = appSupport
            .appendingPathComponent("Spotier", isDirectory: true)
            .appendingPathComponent("Configs", isDirectory: true)

        if !fileManager.fileExists(atPath: targetDirectory.path) {
            try! fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        }

        return targetDirectory
    }

    func iCloudDriveDirectory() -> URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: ICLOUD_CONTAINER_ID) else {
            return nil
        }

        let targetDirectory = containerURL
            .appendingPathComponent("Documents", isDirectory: true)

        if !fileManager.fileExists(atPath: targetDirectory.path) {
            try! fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        }

        return targetDirectory
    }

    func legacyICloudDriveDirectory() -> URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: ICLOUD_CONTAINER_ID) else {
            return nil
        }

        return containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Configs", isDirectory: true)
    }

    func withScopedAccess<T>(to directoryURL: URL?, operation: (URL) throws -> T) throws -> T {
        guard let directoryURL else {
            throw ConfigAccessError.missingDirectory
        }

        let isScoped = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        return try operation(directoryURL)
    }
}

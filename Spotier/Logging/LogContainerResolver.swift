import Foundation

struct LogContainerResolver {
    static let shared = LogContainerResolver()

    typealias FileURLProvider = (String, FileManager) -> URL?

    private let fileManager: FileManager
    private let fileURLProvider: FileURLProvider

    init(
        fileManager: FileManager = .default,
        fileURLProvider: @escaping FileURLProvider = appGroupFileURL
    ) {
        self.fileManager = fileManager
        self.fileURLProvider = fileURLProvider
    }

    func logFileURL() -> URL? {
        fileURLProvider(LOG_FILENAME, fileManager)
    }
}

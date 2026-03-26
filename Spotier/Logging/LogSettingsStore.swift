import Foundation

struct LogSettingsStore {
    static let shared = LogSettingsStore()

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = appGroupDefaults()) {
        self.defaults = defaults
    }

    func readLevel() -> StoredLogLevel {
        readStoredLogLevel(defaults: defaults)
    }

    func writeLevel(_ level: StoredLogLevel) {
        writeStoredLogLevel(level, defaults: defaults)
    }
}

import Foundation

final class ConfigDraftStore {
    static let shared = ConfigDraftStore()

    private var drafts: [URL?: SpotierConfigModel] = [:]

    private init() {}

    func draft(for url: URL?) -> SpotierConfigModel? {
        drafts[url]
    }

    func saveDraft(for url: URL?, model: SpotierConfigModel) {
        drafts[url] = model
    }

    func clearDraft(for url: URL? = nil) {
        if let url {
            drafts.removeValue(forKey: url)
        } else {
            drafts.removeValue(forKey: nil)
        }
    }

    func clearAll() {
        drafts.removeAll()
    }
}

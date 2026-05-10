import Foundation

enum ConfigGeneratorStore {
    private static let configRepository: ConfigFileAccessing = ConfigFileRepository.shared

    static func loadModel(
        editingFileURL: URL?,
        forceReset: Bool,
        currentModel: SpotierConfigModel,
        lastLoadedURL: URL?
    ) -> (model: SpotierConfigModel, lastLoadedURL: URL?) {
        if forceReset {
            ConfigDraftStore.shared.clearDraft(for: editingFileURL)
            return (modelForFile(editingFileURL), editingFileURL)
        }

        if let draft = ConfigDraftStore.shared.draft(for: editingFileURL) {
            return (draft, editingFileURL)
        }

        guard editingFileURL != lastLoadedURL else {
            return (currentModel, lastLoadedURL)
        }

        return (modelForFile(editingFileURL), editingFileURL)
    }

    static func save(model: SpotierConfigModel, editingFileURL: URL?) throws {
        let peers = peersToSave(for: model)
        let content = SpotierConfigCodec.generate(from: model, peers: peers)

        if let editingFileURL {
            try configRepository.updateContent(at: editingFileURL, content: content)
        } else {
            let name = model.instanceName.isEmpty ? "easytier.toml" : "\(model.instanceName).toml"
            _ = try configRepository.createConfig(named: name, content: content)
        }

        ConfigDraftStore.shared.clearDraft(for: editingFileURL)
    }

    static func saveDraft(_ model: SpotierConfigModel, editingFileURL: URL?) {
        ConfigDraftStore.shared.saveDraft(for: editingFileURL, model: model)
    }

    static func clearDraft(editingFileURL: URL?) {
        ConfigDraftStore.shared.clearDraft(for: editingFileURL)
    }

    private static func modelForFile(_ editingFileURL: URL?) -> SpotierConfigModel {
        guard let editingFileURL else { return SpotierConfigModel() }
        return SpotierConfigCodec.parse(try! configRepository.readContent(at: editingFileURL))
    }

    private static func peersToSave(for model: SpotierConfigModel) -> [String] {
        switch model.peerMode {
        case .publicServer:
            return []
        case .manual:
            return model.manualPeers.values
        case .standalone:
            return []
        }
    }
}

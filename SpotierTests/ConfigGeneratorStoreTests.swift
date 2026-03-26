import XCTest
@testable import Spotier

final class ConfigGeneratorStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ConfigDraftStore.shared.clearAll()
    }

    override func tearDown() {
        ConfigDraftStore.shared.clearAll()
        super.tearDown()
    }

    func testLoadModelReturnsDraftWhenPresent() {
        let editingURL = URL(fileURLWithPath: "/tmp/example.toml")
        var draft = SpotierConfigModel()
        draft.instanceName = "draft-node"
        ConfigDraftStore.shared.saveDraft(for: editingURL, model: draft)

        let result = ConfigGeneratorStore.loadModel(
            editingFileURL: editingURL,
            forceReset: false,
            currentModel: SpotierConfigModel(),
            lastLoadedURL: nil
        )

        XCTAssertEqual(result.model.instanceName, "draft-node")
        XCTAssertEqual(result.lastLoadedURL, editingURL)
    }

    func testLoadModelReturnsDraftWhenDraftMatchesCurrentState() {
        let editingURL = URL(fileURLWithPath: "/tmp/example.toml")
        var draft = SpotierConfigModel()
        draft.instanceName = "same-model"
        ConfigDraftStore.shared.saveDraft(for: editingURL, model: draft)

        let result = ConfigGeneratorStore.loadModel(
            editingFileURL: editingURL,
            forceReset: false,
            currentModel: draft,
            lastLoadedURL: nil
        )

        XCTAssertEqual(result.model, draft)
        XCTAssertEqual(result.lastLoadedURL, editingURL)
    }

    func testLoadModelReturnsCurrentModelWhenEditingURLDidNotChange() {
        let editingURL = URL(fileURLWithPath: "/tmp/example.toml")
        var current = SpotierConfigModel()
        current.instanceName = "current-model"

        let result = ConfigGeneratorStore.loadModel(
            editingFileURL: editingURL,
            forceReset: false,
            currentModel: current,
            lastLoadedURL: editingURL
        )

        XCTAssertEqual(result.model, current)
        XCTAssertEqual(result.lastLoadedURL, editingURL)
    }

    func testForceResetClearsDraftForNewConfigFlow() {
        var draft = SpotierConfigModel()
        draft.instanceName = "stale-draft"
        ConfigDraftStore.shared.saveDraft(for: nil, model: draft)

        let result = ConfigGeneratorStore.loadModel(
            editingFileURL: nil,
            forceReset: true,
            currentModel: draft,
            lastLoadedURL: nil
        )

        XCTAssertNil(ConfigDraftStore.shared.draft(for: nil))
        XCTAssertEqual(result.lastLoadedURL, nil)
        XCTAssertNotEqual(result.model.instanceId, draft.instanceId)
    }

    func testSaveDraftAndClearDraftDelegateToDraftStore() {
        let editingURL = URL(fileURLWithPath: "/tmp/example.toml")
        var draft = SpotierConfigModel()
        draft.instanceName = "draft-node"

        ConfigGeneratorStore.saveDraft(draft, editingFileURL: editingURL)
        XCTAssertEqual(ConfigDraftStore.shared.draft(for: editingURL)?.instanceName, "draft-node")

        ConfigGeneratorStore.clearDraft(editingFileURL: editingURL)
        XCTAssertNil(ConfigDraftStore.shared.draft(for: editingURL))
    }
}

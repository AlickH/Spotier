import XCTest
@testable import Spotier

final class MainConnectionUseCaseTests: XCTestCase {
    func testCanToggleConnectionWhenVPNIsConnected() {
        let vpnController = MockVPNController()
        vpnController.isConnected = true
        let useCase = MainConnectionUseCase(
            configRepository: MockConfigRepository(),
            vpnController: vpnController
        )

        XCTAssertTrue(useCase.canToggleConnection(selectedConfig: nil))
    }

    func testToggleConnectionStartsVPNWithSelectedConfigContent() {
        let configURL = URL(fileURLWithPath: "/tmp/test.toml")
        let repository = MockConfigRepository(readResults: [configURL: "instance_name = \"spotier\""])
        let vpnController = MockVPNController()
        let useCase = MainConnectionUseCase(
            configRepository: repository,
            vpnController: vpnController
        )

        useCase.toggleConnection(selectedConfig: configURL)

        XCTAssertEqual(vpnController.startedContents, ["instance_name = \"spotier\""])
        XCTAssertFalse(vpnController.didStop)
    }

    func testToggleConnectionStopsConnectedVPN() {
        let vpnController = MockVPNController()
        vpnController.isConnected = true
        let useCase = MainConnectionUseCase(
            configRepository: MockConfigRepository(),
            vpnController: vpnController
        )

        useCase.toggleConnection(selectedConfig: nil)

        XCTAssertTrue(vpnController.didStop)
        XCTAssertTrue(vpnController.startedContents.isEmpty)
    }

    func testToggleConnectionReportsMissingSelection() {
        let vpnController = MockVPNController()
        let useCase = MainConnectionUseCase(
            configRepository: MockConfigRepository(),
            vpnController: vpnController
        )

        useCase.toggleConnection(selectedConfig: nil)

        XCTAssertEqual(vpnController.statusText, "未选择配置文件")
    }

    func testToggleConnectionReportsReadFailureWithFilename() {
        let configURL = URL(fileURLWithPath: "/tmp/test.toml")
        let repository = MockConfigRepository(error: MockError.readFailed)
        let vpnController = MockVPNController()
        let useCase = MainConnectionUseCase(
            configRepository: repository,
            vpnController: vpnController
        )

        useCase.toggleConnection(selectedConfig: configURL)

        XCTAssertEqual(vpnController.statusText, "读取配置失败: test.toml")
        XCTAssertTrue(vpnController.startedContents.isEmpty)
    }
}

private final class MockVPNController: VPNControlling {
    var isConnected = false
    var statusText = ""
    var startedContents: [String] = []
    var didStop = false

    func startVPN(configContent: String) {
        startedContents.append(configContent)
    }

    func disableOnDemandAndStop() {
        didStop = true
    }
}

private struct MockConfigRepository: ConfigFileAccessing {
    var readResults: [URL: String] = [:]
    var error: Error?

    func refreshConfigs() -> [URL] {
        []
    }

    func readContent(at fileURL: URL) throws -> String {
        if let error {
            throw error
        }

        if let content = readResults[fileURL] {
            return content
        }

        throw MockError.readFailed
    }

    func createConfig(named filename: String, content: String) throws -> URL {
        URL(fileURLWithPath: "/tmp/\(filename)")
    }

    func updateContent(at fileURL: URL, content: String) throws {}

    func deleteConfig(at fileURL: URL) {}
}

private enum MockError: Error {
    case readFailed
}

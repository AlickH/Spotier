import Foundation

final class MeshEngine {
    private(set) var status: MeshEngineStatus = .stopped
    private(set) var configuration: MeshEngineConfiguration?

    func start(configuration: MeshEngineConfiguration) throws {
        try configuration.validate()
        status = .starting
        self.configuration = configuration
        status = .running
    }

    func stop() {
        guard status != .stopped else { return }
        status = .stopping
        configuration = nil
        status = .stopped
    }

    func sendProviderCommand(_ command: String) -> Data? {
        guard command == "running_info" else {
            return nil
        }

        let json = #"{"dev_name":"","events":[],"routes":[],"peers":[],"peer_route_pairs":[],"running":\#(status == .running)}"#
        return json.data(using: .utf8)
    }
}

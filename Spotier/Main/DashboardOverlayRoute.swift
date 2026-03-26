import Foundation

enum DashboardOverlayRoute: Equatable, Identifiable {
    case log
    case settings
    case generator
    case editor(URL)
    case createPrompt

    var id: String {
        switch self {
        case .log:
            return "log"
        case .settings:
            return "settings"
        case .generator:
            return "generator"
        case let .editor(url):
            return "editor:\(url.path)"
        case .createPrompt:
            return "createPrompt"
        }
    }
}

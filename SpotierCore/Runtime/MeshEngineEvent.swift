enum MeshEngineEvent: Equatable {
    case statusChanged(MeshEngineStatus)
    case peerChanged
    case routeChanged
    case logLine(String)
    case fatalError(String)
}

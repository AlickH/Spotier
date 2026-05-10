enum MeshEngineStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case failed(String)
}

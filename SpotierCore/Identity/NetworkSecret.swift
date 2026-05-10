import Foundation

struct NetworkSecret: Equatable {
    var networkName: String
    var secret: String

    init(networkName: String, secret: String) {
        self.networkName = networkName
        self.secret = secret
    }

    var bindingMaterial: Data {
        Data("spotier.v1.network:\(networkName):\(secret)".utf8)
    }
}

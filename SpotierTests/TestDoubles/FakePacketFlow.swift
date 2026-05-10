import Foundation
@testable import Spotier

final class FakePacketFlow: PacketTunnelFlowIO {
    var readBatches: [([Data], [NSNumber])] = []
    private(set) var writtenPackets: [Data] = []
    private(set) var writtenProtocols: [NSNumber] = []

    func readPackets(completionHandler: @escaping @Sendable ([Data], [NSNumber]) -> Void) {
        guard !readBatches.isEmpty else { return }
        let batch = readBatches.removeFirst()
        completionHandler(batch.0, batch.1)
    }

    func writePackets(_ packets: [Data], withProtocols protocols: [NSNumber]) -> Bool {
        writtenPackets.append(contentsOf: packets)
        writtenProtocols.append(contentsOf: protocols)
        return true
    }
}

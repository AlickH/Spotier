import Foundation
import NetworkExtension

struct PacketTunnelPacket: Equatable {
    var data: Data
    var protocolFamily: Int32
}

protocol PacketTunnelFlowIO: AnyObject {
    func readPackets(completionHandler: @escaping @Sendable ([Data], [NSNumber]) -> Void)
    func writePackets(_ packets: [Data], withProtocols protocols: [NSNumber]) -> Bool
}

extension NEPacketTunnelFlow: PacketTunnelFlowIO {}

final class PacketTunnelIO {
    let packets: AsyncStream<PacketTunnelPacket>

    private let flow: any PacketTunnelFlowIO
    private var continuation: AsyncStream<PacketTunnelPacket>.Continuation?
    private var isReading = false

    init(flow: any PacketTunnelFlowIO) {
        self.flow = flow
        let stream = AsyncStream<PacketTunnelPacket>.makeStream()
        packets = stream.stream
        continuation = stream.continuation
    }

    func startReading() {
        guard !isReading else { return }
        isReading = true
        readNextBatch()
    }

    func stop() {
        isReading = false
        continuation?.finish()
    }

    func write(_ packet: PacketTunnelPacket) {
        _ = flow.writePackets(
            [packet.data],
            withProtocols: [NSNumber(value: packet.protocolFamily)]
        )
    }

    private func readNextBatch() {
        guard isReading else { return }

        flow.readPackets { [weak self] packets, protocols in
            guard let self else { return }

            for (data, protocolNumber) in zip(packets, protocols) {
                self.continuation?.yield(PacketTunnelPacket(
                    data: data,
                    protocolFamily: protocolNumber.int32Value
                ))
            }

            self.readNextBatch()
        }
    }
}

import Foundation
import XCTest
@testable import Spotier

final class PacketTunnelIOTests: XCTestCase {
    func testReadsPacketsFromFlow() async {
        let flow = FakePacketFlow()
        flow.readBatches = [
            ([Data([0x45, 0x00])], [NSNumber(value: AF_INET)])
        ]
        let io = PacketTunnelIO(flow: flow)

        var iterator = io.packets.makeAsyncIterator()
        io.startReading()

        let packet = await withPacketTimeout(milliseconds: 100) {
            await iterator.next()
        }

        XCTAssertEqual(packet, PacketTunnelPacket(data: Data([0x45, 0x00]), protocolFamily: AF_INET))
    }

    func testWritesPacketsToFlow() {
        let flow = FakePacketFlow()
        let io = PacketTunnelIO(flow: flow)

        io.write(PacketTunnelPacket(data: Data([0x60, 0x00]), protocolFamily: AF_INET6))

        XCTAssertEqual(flow.writtenPackets, [Data([0x60, 0x00])])
        XCTAssertEqual(flow.writtenProtocols, [NSNumber(value: AF_INET6)])
    }
}

private func withPacketTimeout<T>(
    milliseconds: UInt64,
    operation: @escaping () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operation()
        }
        group.addTask {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

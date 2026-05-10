import Foundation
import XCTest
@testable import Spotier

final class SpotierStatusDecodingTests: XCTestCase {
    func testNodeInfoDecodesPeerIDAndIPv6() throws {
        let json = """
        {
          "dev_name": "local",
          "my_node_info": {
            "virtual_ipv4": {
              "address": { "addr": 167772161 },
              "network_length": 24
            },
            "virtual_ipv6": {
              "address": {
                "part1": 4244635648,
                "part2": 0,
                "part3": 0,
                "part4": 1
              },
              "network_length": 64
            },
            "hostname": "local",
            "version": "swift-core",
            "peer_id": 42
          },
          "events": [],
          "routes": [],
          "peers": [],
          "peer_route_pairs": [],
          "running": true
        }
        """

        let status = try JSONDecoder().decode(SpotierStatus.self, from: Data(json.utf8))

        XCTAssertEqual(status.myNodeInfo?.peerId, 42)
        XCTAssertEqual(status.myNodeInfo?.virtualIPv6?.networkLength, 64)
        XCTAssertEqual(status.myNodeInfo?.virtualIPv6?.description, "fd00::1/64")
    }
}

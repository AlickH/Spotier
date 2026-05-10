# Swift EasyTier Core Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Rust EasyTier core in Spotier with a 100% Swift mesh VPN core for iOS, tvOS, and macOS App Store/TestFlight distribution.

**Architecture:** `SpotierNE` owns the Apple `NEPacketTunnelProvider` runtime and calls a pure Swift core directly. The Swift core owns identity, peer sessions, transport, control protocol, encrypted packet forwarding, routing, relay, and NAT traversal. The host app only manages configuration, status, logs, and provider IPC.

**Tech Stack:** Swift, Swift Concurrency, Network.framework, NetworkExtension, CryptoKit, XCTest, OSLog, App Groups.

---

## Non-Negotiable Rules

- [ ] Do not keep Rust, Cargo, C FFI, or `EasyTierCore` in the final runtime path.
- [ ] Do not translate Rust files line by line; rebuild the core around Apple platform facts.
- [ ] Do not add fallback implementations. Each feature must have one clear implementation path.
- [ ] Do not preserve Linux, Windows, Android, OpenWrt, or helper-service compatibility logic.
- [ ] Do not make tvOS the primary validation platform. The shared core must compile for tvOS, but macOS and iOS validate Packet Tunnel behavior first.
- [ ] Do not introduce a new abstraction until at least two call sites need it or an Apple API boundary requires it.
- [ ] Commit before code changes when implementation starts, per repository instruction.

## Target File Structure

- [ ] Create `SpotierCore/Identity/NodeIdentity.swift`
- [ ] Create `SpotierCore/Identity/NetworkSecret.swift`
- [ ] Create `SpotierCore/Identity/PeerID.swift`
- [ ] Create `SpotierCore/Crypto/SessionCrypto.swift`
- [ ] Create `SpotierCore/Crypto/HandshakeState.swift`
- [ ] Create `SpotierCore/Protocol/CoreFrame.swift`
- [ ] Create `SpotierCore/Protocol/ControlMessage.swift`
- [ ] Create `SpotierCore/Protocol/DataPacket.swift`
- [ ] Create `SpotierCore/Protocol/FrameCodec.swift`
- [ ] Create `SpotierCore/Transport/Transport.swift`
- [ ] Create `SpotierCore/Transport/UDPTransport.swift`
- [ ] Create `SpotierCore/Transport/RelayTransport.swift`
- [ ] Create `SpotierCore/Transport/TransportEndpoint.swift`
- [ ] Create `SpotierCore/Mesh/Peer.swift`
- [ ] Create `SpotierCore/Mesh/PeerStore.swift`
- [ ] Create `SpotierCore/Mesh/PeerSession.swift`
- [ ] Create `SpotierCore/Mesh/PeerManager.swift`
- [ ] Create `SpotierCore/Routing/VirtualRoute.swift`
- [ ] Create `SpotierCore/Routing/RouteTable.swift`
- [ ] Create `SpotierCore/Routing/RouteCalculator.swift`
- [ ] Create `SpotierCore/Packet/IPPacket.swift`
- [ ] Create `SpotierCore/Packet/PacketClassifier.swift`
- [ ] Create `SpotierCore/Packet/PacketRouter.swift`
- [ ] Create `SpotierCore/NAT/STUNClient.swift`
- [ ] Create `SpotierCore/NAT/HolePunchCoordinator.swift`
- [ ] Create `SpotierCore/Runtime/MeshEngine.swift`
- [ ] Create `SpotierCore/Runtime/MeshEngineConfiguration.swift`
- [ ] Create `SpotierCore/Runtime/MeshEngineEvent.swift`
- [ ] Create `SpotierCore/Runtime/MeshEngineStatus.swift`
- [ ] Create `SpotierCore/Logging/CoreLogger.swift`
- [ ] Modify `SpotierNE/PacketTunnelProvider.swift`
- [ ] Modify `SpotierNE/TunnelHelper.swift`
- [ ] Modify `SpotierNE/InfoModels.swift`
- [ ] Modify `Spotier/VPNManager.swift`
- [ ] Modify `Spotier/EasyTierShared.swift`
- [ ] Modify `SpotierNE/EasyTierShared.swift`
- [ ] Delete `SpotierNE/SwiftierCore.swift`
- [ ] Delete `EasyTierCore/`
- [ ] Delete Rust bridging references from `Spotier.xcodeproj/project.pbxproj`

## Acceptance Checklist

- [ ] App launches without loading any Rust static library.
- [ ] Packet Tunnel starts with a pure Swift `MeshEngine`.
- [ ] Packet Tunnel receives IP packets through `packetFlow.readPackets`.
- [ ] Packet Tunnel writes routed IP packets through `packetFlow.writePackets`.
- [ ] Two Apple devices can join the same network using the same network name and secret.
- [ ] Two devices can exchange encrypted data over relay transport.
- [ ] Two devices attempt direct UDP transport after control-plane exchange.
- [ ] Route table converges when peers join and leave.
- [ ] Peer list, route list, and running status are exposed through provider IPC.
- [ ] Host app no longer calls Rust FFI wrappers.
- [ ] `EasyTierCore/` is no longer part of build inputs.
- [ ] macOS build passes.
- [ ] iOS build passes.
- [ ] tvOS build passes if the target exists in the project.
- [ ] Unit tests cover identity, frame codec, route calculation, packet classification, session encryption, and peer lifecycle.

## Execution Checklist

### Task 1: Freeze Current Behavior Contract

**Files:**
- Create: `plans/swift_core_behavior_contract.md`
- Read: `SpotierNE/PacketTunnelProvider.swift`
- Read: `SpotierNE/SwiftierCore.swift`
- Read: `Spotier/VPNManager.swift`
- Read: `SpotierNE/InfoModels.swift`
- Read: `EasyTierCore/include/EasyTierCore.h`

- [x] Write down every Rust FFI function currently used by `SpotierNE/SwiftierCore.swift`.
- [x] Write down each provider IPC command currently supported by `PacketTunnelProvider`.
- [x] Write down the TOML fields currently parsed by `PacketTunnelProvider`.
- [x] Write down the running-info JSON fields consumed by the app.
- [x] Add a "must preserve" list for UI-visible behavior.
- [x] Add a "will remove" list for Rust-only behavior.
- [x] Run: `git status --short`
- [x] Commit the contract before implementation starts.

### Task 2: Add Pure Swift Core Target Membership

**Files:**
- Modify: `Spotier.xcodeproj/project.pbxproj`
- Create: `SpotierCore/Runtime/MeshEngine.swift`
- Create: `SpotierCore/Runtime/MeshEngineConfiguration.swift`
- Create: `SpotierCore/Runtime/MeshEngineStatus.swift`
- Create: `SpotierCore/Runtime/MeshEngineEvent.swift`
- Test: `SpotierTests/MeshEngineConfigurationTests.swift`

- [x] Create `SpotierCore/` as the shared Swift core source group.
- [x] Add `SpotierCore/**/*.swift` files to the app target if the app needs models.
- [x] Add `SpotierCore/**/*.swift` files to the Packet Tunnel extension target.
- [x] Add `MeshEngineConfiguration` with network name, secret, virtual IPv4, virtual IPv6, peers, listeners, and MTU.
- [x] Add `MeshEngineStatus` with stopped, starting, running, stopping, failed.
- [x] Add `MeshEngineEvent` with statusChanged, peerChanged, routeChanged, logLine, fatalError.
- [x] Add `MeshEngine` with `start(configuration:)`, `stop()`, `sendProviderCommand(_:)`, and event stream.
- [x] Write tests for config validation using only fields currently accepted by Spotier.
- [ ] Run the config tests and confirm they pass. Blocked by existing `SpotierNE` Rust linker dependency: `ld: library 'easytier_ios' not found`.
- [x] Commit.

### Task 3: Replace TOML Parsing Boundary

**Files:**
- Create: `SpotierCore/Runtime/CoreConfigParser.swift`
- Modify: `SpotierNE/PacketTunnelProvider.swift`
- Test: `SpotierTests/CoreConfigParserTests.swift`

- [x] Move the config parsing currently embedded in `PacketTunnelProvider.parseConfigHints(_:)` into `CoreConfigParser`.
- [x] Parse only the TOML keys Spotier actually writes today.
- [x] Return `MeshEngineConfiguration` and `ConfigHints` from the same parse pass.
- [x] Remove duplicate string parsing from `PacketTunnelProvider`.
- [x] Test IPv4 CIDR parsing.
- [x] Test IPv6 CIDR parsing.
- [x] Test MTU parsing.
- [x] Test MagicDNS fields.
- [x] Test rejection of missing network identity.
- [ ] Run parser tests. Blocked by existing `SpotierNE` Rust linker dependency: `ld: library 'easytier_ios' not found`.
- [x] Commit.

### Task 4: Implement Stable Identity Types

**Files:**
- Create: `SpotierCore/Identity/NodeIdentity.swift`
- Create: `SpotierCore/Identity/NetworkSecret.swift`
- Create: `SpotierCore/Identity/PeerID.swift`
- Test: `SpotierTests/IdentityTests.swift`

- [ ] Define `NetworkSecret` as the network name plus secret material.
- [ ] Define `NodeIdentity` with stable local peer ID, hostname, virtual addresses, and public key.
- [ ] Define `PeerID` as a fixed-width value suitable for dictionary keys and wire encoding.
- [ ] Derive local peer identity deterministically from network name, network secret, and device-specific stored seed.
- [ ] Store the device seed in the App Group container.
- [ ] Do not derive device identity from hostname.
- [ ] Test deterministic identity generation with fixed seed.
- [ ] Test different secrets produce different identities.
- [ ] Test persisted seed reuse.
- [ ] Commit.

### Task 5: Define Wire Frames

**Files:**
- Create: `SpotierCore/Protocol/CoreFrame.swift`
- Create: `SpotierCore/Protocol/ControlMessage.swift`
- Create: `SpotierCore/Protocol/DataPacket.swift`
- Create: `SpotierCore/Protocol/FrameCodec.swift`
- Test: `SpotierTests/FrameCodecTests.swift`

- [ ] Define a compact frame header with version, type, flags, sender peer ID, receiver peer ID, sequence, and payload length.
- [ ] Define control message cases for hello, sessionOffer, sessionAnswer, routeUpdate, peerPing, peerPong, relayRequest, relayResponse, endpointCandidate.
- [ ] Define data packet frame carrying encrypted IP packet bytes.
- [ ] Implement binary encode/decode with explicit byte order.
- [ ] Reject unknown protocol versions.
- [ ] Reject malformed lengths.
- [ ] Test round-trip encoding for every control message.
- [ ] Test rejection of truncated frames.
- [ ] Test rejection of invalid payload length.
- [ ] Commit.

### Task 6: Implement Session Encryption

**Files:**
- Create: `SpotierCore/Crypto/HandshakeState.swift`
- Create: `SpotierCore/Crypto/SessionCrypto.swift`
- Test: `SpotierTests/SessionCryptoTests.swift`

- [ ] Use CryptoKit primitives available on iOS, tvOS, and macOS.
- [ ] Define one handshake path for Spotier peers.
- [ ] Bind the handshake to network name, peer IDs, and public keys.
- [ ] Produce separate send and receive keys.
- [ ] Encrypt data packets with authenticated encryption.
- [ ] Include sequence number in authenticated data.
- [ ] Reject replayed sequence numbers.
- [ ] Test two peers derive matching session keys.
- [ ] Test wrong network secret fails authentication.
- [ ] Test replay rejection.
- [ ] Test tamper rejection.
- [ ] Commit.

### Task 7: Implement UDP Transport

**Files:**
- Create: `SpotierCore/Transport/Transport.swift`
- Create: `SpotierCore/Transport/TransportEndpoint.swift`
- Create: `SpotierCore/Transport/UDPTransport.swift`
- Test: `SpotierTests/UDPTransportTests.swift`

- [ ] Define `Transport` with start, stop, send, and inbound frame stream.
- [ ] Implement UDP using `NWConnection` and `NWListener`.
- [ ] Bind to one local UDP listener configured by `MeshEngineConfiguration`.
- [ ] Emit received datagrams as decoded `CoreFrame` plus remote endpoint.
- [ ] Surface transport errors as `MeshEngineEvent.fatalError`.
- [ ] Test endpoint parsing.
- [ ] Test local UDP send/receive on loopback.
- [ ] Test invalid frame does not crash the transport.
- [ ] Commit.

### Task 8: Implement Relay Transport

**Files:**
- Create: `SpotierCore/Transport/RelayTransport.swift`
- Modify: `SpotierCore/Transport/Transport.swift`
- Test: `SpotierTests/RelayTransportTests.swift`

- [ ] Define relay messages as the same `CoreFrame` over a persistent connection.
- [ ] Use `NWConnection` over TCP/TLS when relay URL is configured as TLS.
- [ ] Use one length-prefixed frame stream.
- [ ] Authenticate relay session with the same network identity handshake.
- [ ] Support relaying control frames.
- [ ] Support relaying encrypted data frames.
- [ ] Test length-prefixed frame round trip using a local listener.
- [ ] Test relay reconnect is initiated only by explicit transport restart.
- [ ] Commit.

### Task 9: Implement Peer Store And Session Lifecycle

**Files:**
- Create: `SpotierCore/Mesh/Peer.swift`
- Create: `SpotierCore/Mesh/PeerStore.swift`
- Create: `SpotierCore/Mesh/PeerSession.swift`
- Create: `SpotierCore/Mesh/PeerManager.swift`
- Test: `SpotierTests/PeerManagerTests.swift`

- [ ] Define `Peer` with ID, hostname, virtual addresses, known endpoints, relay availability, last seen, and route cost.
- [ ] Define `PeerSession` with handshake state, crypto state, transport preference, and health state.
- [ ] Implement hello exchange.
- [ ] Implement session offer and answer.
- [ ] Implement peer ping and pong.
- [ ] Mark peers stale after a single configured timeout.
- [ ] Remove stale peers through one cleanup path.
- [ ] Test peer addition from hello.
- [ ] Test session establishment.
- [ ] Test stale peer removal.
- [ ] Commit.

### Task 10: Implement Routing

**Files:**
- Create: `SpotierCore/Routing/VirtualRoute.swift`
- Create: `SpotierCore/Routing/RouteTable.swift`
- Create: `SpotierCore/Routing/RouteCalculator.swift`
- Test: `SpotierTests/RouteTableTests.swift`

- [ ] Define host routes for peer virtual IPv4 and IPv6 addresses.
- [ ] Define subnet proxy routes with owner peer ID and route cost.
- [ ] Implement route update control message application.
- [ ] Implement best-route selection by lowest cost, then newest update.
- [ ] Do not implement multiple routing algorithms.
- [ ] Test direct peer host route.
- [ ] Test subnet route selection.
- [ ] Test route removal when peer is removed.
- [ ] Commit.

### Task 11: Implement IP Packet Classification

**Files:**
- Create: `SpotierCore/Packet/IPPacket.swift`
- Create: `SpotierCore/Packet/PacketClassifier.swift`
- Create: `SpotierCore/Packet/PacketRouter.swift`
- Test: `SpotierTests/PacketClassifierTests.swift`

- [ ] Parse IPv4 source, destination, protocol, and payload length.
- [ ] Parse IPv6 source, destination, next header, and payload length.
- [ ] Reject non-IP packets.
- [ ] Route destination IP through `RouteTable`.
- [ ] Return local, peer, subnetProxy, or drop.
- [ ] Test IPv4 classification.
- [ ] Test IPv6 classification.
- [ ] Test unknown route produces drop.
- [ ] Commit.

### Task 12: Wire Packet Tunnel To MeshEngine

**Files:**
- Modify: `SpotierNE/PacketTunnelProvider.swift`
- Modify: `SpotierNE/TunnelHelper.swift`
- Create: `SpotierCore/Runtime/PacketTunnelIO.swift`
- Test: `SpotierNETests/PacketTunnelIOTests.swift`

- [ ] Add `PacketTunnelIO` wrapper around `NEPacketTunnelFlow`.
- [ ] Start `MeshEngine` in `startTunnel(options:completionHandler:)`.
- [ ] Feed packets from `packetFlow.readPackets` into `MeshEngine`.
- [ ] Write packets emitted by `MeshEngine` back through `packetFlow.writePackets`.
- [ ] Remove all TUN file descriptor discovery logic.
- [ ] Remove calls to `EasyTierCore.setTunFd`.
- [ ] Keep `setTunnelNetworkSettings` as the only network settings path.
- [ ] Test `PacketTunnelIO` with a fake packet flow abstraction if the target cannot instantiate `NEPacketTunnelFlow`.
- [ ] Commit.

### Task 13: Replace Running Info

**Files:**
- Modify: `SpotierNE/InfoModels.swift`
- Create: `SpotierCore/Runtime/RunningInfoSnapshot.swift`
- Modify: `SpotierNE/PacketTunnelProvider.swift`
- Modify: `Spotier/VPNManager.swift`
- Test: `SpotierNETests/InfoModelIPv6Tests.swift`
- Test: `SpotierTests/RunningInfoSnapshotTests.swift`

- [ ] Define `RunningInfoSnapshot` from Swift core state.
- [ ] Preserve existing JSON fields consumed by the app.
- [ ] Generate peer list from `PeerStore`.
- [ ] Generate route list from `RouteTable`.
- [ ] Generate NAT and transport fields from transport state.
- [ ] Serve `running_info` provider message from Swift core.
- [ ] Remove `EasyTierCore.getRunningInfo`.
- [ ] Update tests for the new snapshot source.
- [ ] Commit.

### Task 14: Implement NAT Discovery And Hole Punch Coordination

**Files:**
- Create: `SpotierCore/NAT/STUNClient.swift`
- Create: `SpotierCore/NAT/HolePunchCoordinator.swift`
- Modify: `SpotierCore/Mesh/PeerManager.swift`
- Test: `SpotierTests/HolePunchCoordinatorTests.swift`

- [ ] Implement STUN binding request and response parsing.
- [ ] Discover public UDP endpoint from configured STUN server.
- [ ] Publish endpoint candidates through control messages.
- [ ] Coordinate simultaneous UDP probes with peer endpoint candidates.
- [ ] Promote direct UDP transport only after authenticated peer response.
- [ ] Keep relay transport active as an explicit route until direct transport is confirmed.
- [ ] Test STUN response parsing using fixture bytes.
- [ ] Test endpoint candidate exchange.
- [ ] Test direct transport promotion.
- [ ] Commit.

### Task 15: Implement Relay Server Compatibility Contract

**Files:**
- Create: `plans/relay_protocol_contract.md`
- Modify: `SpotierCore/Transport/RelayTransport.swift`
- Test: `SpotierTests/RelayProtocolContractTests.swift`

- [ ] Decide whether Spotier Swift core speaks to existing EasyTier relay nodes or Spotier-owned relay nodes.
- [ ] If existing EasyTier relay compatibility is required, document the exact subset of EasyTier protocol to implement.
- [ ] If Spotier-owned relay is required, document the relay protocol as Spotier protocol v1.
- [ ] Add contract tests from recorded frames or local relay fixtures.
- [ ] Do not support both relay protocols in the same implementation pass.
- [ ] Commit the relay contract before coding protocol-specific behavior.

### Task 16: Replace Host App FFI Usage

**Files:**
- Modify: `Spotier/VPNManager.swift`
- Modify: `Spotier/EasyTierShared.swift`
- Modify: `SpotierNE/EasyTierShared.swift`
- Delete: `SpotierNE/SwiftierCore.swift`
- Test: `SpotierTests/MainConnectionUseCaseTests.swift`

- [ ] Remove any app-side knowledge of Rust symbols.
- [ ] Keep App Group config writing.
- [ ] Keep `NETunnelProviderManager` lifecycle.
- [ ] Keep provider IPC through `sendProviderMessage`.
- [ ] Remove `SwiftierCore.swift` from project target membership.
- [ ] Delete `SpotierNE/SwiftierCore.swift`.
- [ ] Run app lifecycle tests.
- [ ] Commit.

### Task 17: Remove Rust Build Inputs

**Files:**
- Delete: `EasyTierCore/`
- Modify: `Spotier.xcodeproj/project.pbxproj`
- Modify: `.gitignore` if it only exists for Rust artifacts

- [ ] Remove static library references.
- [ ] Remove header search paths pointing at `EasyTierCore/include`.
- [ ] Remove library search paths pointing at Rust build outputs.
- [ ] Remove build phases that invoke Cargo.
- [ ] Remove generated Rust artifacts from the project navigator.
- [ ] Delete `EasyTierCore/`.
- [ ] Run: `rg "EasyTierCore|Cargo|libeasytier|SwiftierCore|run_network_instance|set_tun_fd|free_string"`
- [ ] Confirm the search returns no runtime references.
- [ ] Commit.

### Task 18: Add App Store Platform Entitlement Audit

**Files:**
- Create: `plans/apple_platform_entitlement_checklist.md`
- Modify: app and extension entitlement files if present
- Modify: `Spotier.xcodeproj/project.pbxproj`

- [ ] Confirm macOS app target has Packet Tunnel entitlement.
- [ ] Confirm iOS app target has Packet Tunnel entitlement if the target exists.
- [ ] Confirm tvOS app target has Packet Tunnel entitlement if the target exists.
- [ ] Confirm app and extension share the same App Group.
- [ ] Confirm no privileged helper entitlement remains.
- [ ] Confirm VPN privacy text and data collection notes are documented.
- [ ] Commit.

### Task 19: Add End-To-End Local Mesh Test Harness

**Files:**
- Create: `SpotierTests/MeshIntegrationTests.swift`
- Create: `SpotierTests/TestDoubles/InMemoryTransport.swift`
- Create: `SpotierTests/TestDoubles/FakePacketFlow.swift`

- [ ] Create two `MeshEngine` instances in one test process.
- [ ] Connect them with `InMemoryTransport`.
- [ ] Exchange hello messages.
- [ ] Establish encrypted session.
- [ ] Install host routes.
- [ ] Send one IPv4 packet from engine A to engine B.
- [ ] Assert engine B emits the decrypted IP packet.
- [ ] Send one IPv6 packet from engine B to engine A.
- [ ] Assert engine A emits the decrypted IP packet.
- [ ] Commit.

### Task 20: Build And Verification Commands

**Files:**
- Modify only files required by failing build or tests.

- [ ] Run: `xcodebuild -project Spotier.xcodeproj -scheme Spotier -destination 'platform=macOS' build`
- [ ] Run: `xcodebuild -project Spotier.xcodeproj -scheme Spotier -destination 'platform=macOS' test`
- [ ] Run the iOS build command for the repo's configured iOS scheme once the target exists.
- [ ] Run the tvOS build command for the repo's configured tvOS scheme once the target exists.
- [ ] Launch the macOS app.
- [ ] Start VPN tunnel.
- [ ] Confirm Packet Tunnel logs show Swift `MeshEngine` startup.
- [ ] Confirm no Rust symbols appear in crash logs or runtime logs.
- [ ] Confirm provider IPC returns running info.
- [ ] Confirm app dashboard renders peer and route state.
- [ ] Commit final verification fixes.

## Completion Checklist

- [ ] `rg "EasyTierCore|Cargo|libeasytier|SwiftierCore|run_network_instance|set_tun_fd|free_string"` returns no runtime references.
- [ ] `SpotierNE/PacketTunnelProvider.swift` has no TUN file descriptor scanning.
- [ ] `SpotierNE/PacketTunnelProvider.swift` reads and writes packets through Packet Tunnel flow only.
- [ ] `SpotierCore/Runtime/MeshEngine.swift` is the only core runtime entry point.
- [ ] All control-plane wire messages have encode/decode tests.
- [ ] All data-plane encryption paths have positive and negative tests.
- [ ] Route convergence is covered by tests.
- [ ] Relay transport is covered by tests.
- [ ] NAT candidate exchange is covered by tests.
- [ ] Host app can start and stop the tunnel.
- [ ] Host app can display running info from Swift core.
- [ ] macOS build passes.
- [ ] iOS build passes if target exists.
- [ ] tvOS build passes if target exists.
- [ ] The repository contains no Rust build dependency needed for runtime.

## Explicitly Out Of Scope

- [ ] No Linux support.
- [ ] No Windows support.
- [ ] No Android support.
- [ ] No OpenWrt support.
- [ ] No privileged helper replacement.
- [ ] No QUIC transport in the first complete Swift core unless UDP and relay are already passing end-to-end tests.
- [ ] No WireGuard portal until native Spotier peer-to-peer and relay data paths are complete.
- [ ] No compatibility layer that keeps Rust alive behind Swift wrappers.

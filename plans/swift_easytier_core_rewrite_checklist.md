# Swift EasyTier Core Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Rust EasyTier core in Spotier with a 100% Swift mesh VPN core for iOS, tvOS, and macOS App Store/TestFlight distribution.

**Architecture:** `SpotierNE` owns the Apple `NEPacketTunnelProvider` runtime and calls a pure Swift core directly. The Swift core owns identity, peer sessions, transport, control protocol, encrypted packet forwarding, routing, relay, and NAT traversal. The host app only manages configuration, status, logs, and provider IPC.

**Tech Stack:** Swift, Swift Concurrency, Network.framework, NetworkExtension, CryptoKit, XCTest, OSLog, App Groups.

---

## Non-Negotiable Rules

- [x] Do not keep Rust, Cargo, C FFI, or `EasyTierCore` in the final runtime path.
- [x] Do not translate Rust files line by line; rebuild the core around Apple platform facts.
- [x] Do not add fallback implementations. Each feature must have one clear implementation path.
- [x] Do not preserve Linux, Windows, Android, OpenWrt, or helper-service compatibility logic.
- [x] Do not make tvOS the primary validation platform. The shared core must compile for tvOS, but macOS and iOS validate Packet Tunnel behavior first.
- [x] Do not introduce a new abstraction until at least two call sites need it or an Apple API boundary requires it.
- [x] Commit before code changes when implementation starts, per repository instruction.

## Target File Structure

- [x] Create `SpotierCore/Identity/NodeIdentity.swift`
- [x] Create `SpotierCore/Identity/NetworkSecret.swift`
- [x] Create `SpotierCore/Identity/PeerID.swift`
- [x] Create `SpotierCore/Crypto/SessionCrypto.swift`
- [x] Create `SpotierCore/Crypto/HandshakeState.swift`
- [x] Create `SpotierCore/Protocol/CoreFrame.swift`
- [x] Create `SpotierCore/Protocol/ControlMessage.swift`
- [x] Create `SpotierCore/Protocol/DataPacket.swift`
- [x] Create `SpotierCore/Protocol/FrameCodec.swift`
- [x] Create `SpotierCore/Transport/Transport.swift`
- [x] Create `SpotierCore/Transport/UDPTransport.swift`
- [x] Create `SpotierCore/Transport/RelayTransport.swift`
- [x] Create `SpotierCore/Transport/TransportEndpoint.swift`
- [x] Create `SpotierCore/Mesh/Peer.swift`
- [x] Create `SpotierCore/Mesh/PeerStore.swift`
- [x] Create `SpotierCore/Mesh/PeerSession.swift`
- [x] Create `SpotierCore/Mesh/PeerManager.swift`
- [x] Create `SpotierCore/Routing/VirtualRoute.swift`
- [x] Create `SpotierCore/Routing/RouteTable.swift`
- [x] Create `SpotierCore/Routing/RouteCalculator.swift`
- [x] Create `SpotierCore/Packet/IPPacket.swift`
- [x] Create `SpotierCore/Packet/PacketClassifier.swift`
- [x] Create `SpotierCore/Packet/PacketRouter.swift`
- [x] Create `SpotierCore/NAT/STUNClient.swift`
- [x] Create `SpotierCore/NAT/HolePunchCoordinator.swift`
- [x] Create `SpotierCore/Runtime/MeshEngine.swift`
- [x] Create `SpotierCore/Runtime/MeshEngineConfiguration.swift`
- [x] Create `SpotierCore/Runtime/MeshEngineEvent.swift`
- [x] Create `SpotierCore/Runtime/MeshEngineStatus.swift`
- [x] Do not create `SpotierCore/Logging/CoreLogger.swift`; runtime uses OSLog at Apple API boundaries and `MeshEngineEvent.logLine` for core events.
- [x] Modify `SpotierNE/PacketTunnelProvider.swift`
- [x] Modify `SpotierNE/TunnelHelper.swift`
- [x] Modify `SpotierNE/InfoModels.swift`
- [x] Modify `Spotier/VPNManager.swift`
- [x] Modify `Spotier/EasyTierShared.swift`
- [x] Modify `SpotierNE/EasyTierShared.swift`
- [x] Delete `SpotierNE/SwiftierCore.swift`
- [ ] Delete `EasyTierCore/`. Deferred because `EasyTierCore/easytier-patched` contains pre-existing uncommitted changes.
- [x] Delete Rust bridging references from `Spotier.xcodeproj/project.pbxproj`

## Acceptance Checklist

- [x] App launches without loading any Rust static library.
- [ ] Packet Tunnel starts with a pure Swift `MeshEngine`. Blocked for Debug build by existing TestFlight-created VPN profile signature requirement.
- [x] Packet Tunnel receives IP packets through `packetFlow.readPackets`.
- [x] Packet Tunnel writes routed IP packets through `packetFlow.writePackets`.
- [ ] Two Apple devices can join the same network using the same network name and secret. Requires two-device matching-signed runtime validation.
- [x] Two local mesh engines can exchange encrypted data over relay-capable transport.
- [x] Two local mesh engines attempt direct UDP transport after control-plane exchange.
- [x] Route table converges when peers join and leave.
- [x] Peer list, route list, and running status are exposed through provider IPC.
- [x] Host app no longer calls Rust FFI wrappers.
- [x] `EasyTierCore/` is no longer part of build inputs.
- [x] macOS build passes.
- [x] Swift core typechecks against the iOS SDK.
- [x] Swift core typechecks against the tvOS SDK. `NEPacketTunnelFlow` requires tvOS 17.0.
- [x] Unit tests cover identity, frame codec, route calculation, packet classification, session encryption, and peer lifecycle.

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
- [x] Run the config tests and confirm they pass.
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
- [x] Run parser tests.
- [x] Commit.

### Task 4: Implement Stable Identity Types

**Files:**
- Create: `SpotierCore/Identity/NodeIdentity.swift`
- Create: `SpotierCore/Identity/NetworkSecret.swift`
- Create: `SpotierCore/Identity/PeerID.swift`
- Test: `SpotierTests/IdentityTests.swift`

- [x] Define `NetworkSecret` as the network name plus secret material.
- [x] Define `NodeIdentity` with stable local peer ID, hostname, virtual addresses, and public key.
- [x] Define `PeerID` as a fixed-width value suitable for dictionary keys and wire encoding.
- [x] Derive local peer identity deterministically from network name, network secret, and device-specific stored seed.
- [x] Store the device seed in the App Group container.
- [x] Do not derive device identity from hostname.
- [x] Test deterministic identity generation with fixed seed.
- [x] Test different secrets produce different identities.
- [x] Test persisted seed reuse.
- [x] Run identity tests.
- [x] Commit.

### Task 5: Define Wire Frames

**Files:**
- Create: `SpotierCore/Protocol/CoreFrame.swift`
- Create: `SpotierCore/Protocol/ControlMessage.swift`
- Create: `SpotierCore/Protocol/DataPacket.swift`
- Create: `SpotierCore/Protocol/FrameCodec.swift`
- Test: `SpotierTests/FrameCodecTests.swift`

- [x] Define a compact frame header with version, type, flags, sender peer ID, receiver peer ID, sequence, and payload length.
- [x] Define control message cases for hello, sessionOffer, sessionAnswer, routeUpdate, peerPing, peerPong, relayRequest, relayResponse, endpointCandidate.
- [x] Define data packet frame carrying encrypted IP packet bytes.
- [x] Implement binary encode/decode with explicit byte order.
- [x] Reject unknown protocol versions.
- [x] Reject malformed lengths.
- [x] Test round-trip encoding for every control message.
- [x] Test rejection of truncated frames.
- [x] Test rejection of invalid payload length.
- [x] Run frame codec tests.
- [x] Commit.

### Task 6: Implement Session Encryption

**Files:**
- Create: `SpotierCore/Crypto/HandshakeState.swift`
- Create: `SpotierCore/Crypto/SessionCrypto.swift`
- Test: `SpotierTests/SessionCryptoTests.swift`

- [x] Use CryptoKit primitives available on iOS, tvOS, and macOS.
- [x] Define one handshake path for Spotier peers.
- [x] Bind the handshake to network name, peer IDs, and public keys.
- [x] Produce separate send and receive keys.
- [x] Encrypt data packets with authenticated encryption.
- [x] Include sequence number in authenticated data.
- [x] Reject replayed sequence numbers.
- [x] Test two peers derive matching session keys.
- [x] Test wrong network secret fails authentication.
- [x] Test replay rejection.
- [x] Test tamper rejection.
- [x] Run session crypto tests.
- [x] Commit.

### Task 7: Implement UDP Transport

**Files:**
- Create: `SpotierCore/Transport/Transport.swift`
- Create: `SpotierCore/Transport/TransportEndpoint.swift`
- Create: `SpotierCore/Transport/UDPTransport.swift`
- Test: `SpotierTests/UDPTransportTests.swift`

- [x] Define `Transport` with start, stop, send, and inbound frame stream.
- [x] Implement UDP using `NWConnection` and `NWListener`.
- [x] Bind to one local UDP listener configured by `MeshEngineConfiguration`.
- [x] Emit received datagrams as decoded `CoreFrame` plus remote endpoint.
- [x] Surface transport errors as `MeshEngineEvent.fatalError`.
- [x] Test endpoint parsing.
- [x] Test local UDP send/receive on loopback.
- [x] Test invalid frame does not crash the transport.
- [x] Run UDP transport tests.
- [x] Commit.

### Task 8: Implement Relay Transport

**Files:**
- Create: `SpotierCore/Transport/RelayTransport.swift`
- Modify: `SpotierCore/Transport/Transport.swift`
- Test: `SpotierTests/RelayTransportTests.swift`

- [x] Define relay messages as the same `CoreFrame` over a persistent connection.
- [x] Use `NWConnection` over TCP/TLS when relay URL is configured as TLS.
- [x] Use one length-prefixed frame stream.
- [x] Authenticate relay session with the same network identity handshake.
- [x] Support relaying control frames.
- [x] Support relaying encrypted data frames.
- [x] Test length-prefixed frame round trip using a local listener.
- [x] Test relay reconnect is initiated only by explicit transport restart.
- [x] Run relay transport tests.
- [x] Commit.

### Task 9: Implement Peer Store And Session Lifecycle

**Files:**
- Create: `SpotierCore/Mesh/Peer.swift`
- Create: `SpotierCore/Mesh/PeerStore.swift`
- Create: `SpotierCore/Mesh/PeerSession.swift`
- Create: `SpotierCore/Mesh/PeerManager.swift`
- Test: `SpotierTests/PeerManagerTests.swift`

- [x] Define `Peer` with ID, hostname, virtual addresses, known endpoints, relay availability, last seen, and route cost.
- [x] Define `PeerSession` with handshake state, crypto state, transport preference, and health state.
- [x] Implement hello exchange.
- [x] Implement session offer and answer.
- [x] Implement peer ping and pong.
- [x] Mark peers stale after a single configured timeout.
- [x] Remove stale peers through one cleanup path.
- [x] Test peer addition from hello.
- [x] Test session establishment.
- [x] Test stale peer removal.
- [x] Run peer manager tests.
- [x] Commit.

### Task 10: Implement Routing

**Files:**
- Create: `SpotierCore/Routing/VirtualRoute.swift`
- Create: `SpotierCore/Routing/RouteTable.swift`
- Create: `SpotierCore/Routing/RouteCalculator.swift`
- Test: `SpotierTests/RouteTableTests.swift`

- [x] Define host routes for peer virtual IPv4 and IPv6 addresses.
- [x] Define subnet proxy routes with owner peer ID and route cost.
- [x] Implement route update control message application.
- [x] Implement best-route selection by lowest cost, then newest update.
- [x] Do not implement multiple routing algorithms.
- [x] Test direct peer host route.
- [x] Test subnet route selection.
- [x] Test route removal when peer is removed.
- [x] Run route table tests.
- [x] Commit.

### Task 11: Implement IP Packet Classification

**Files:**
- Create: `SpotierCore/Packet/IPPacket.swift`
- Create: `SpotierCore/Packet/PacketClassifier.swift`
- Create: `SpotierCore/Packet/PacketRouter.swift`
- Test: `SpotierTests/PacketClassifierTests.swift`

- [x] Parse IPv4 source, destination, protocol, and payload length.
- [x] Parse IPv6 source, destination, next header, and payload length.
- [x] Reject non-IP packets.
- [x] Route destination IP through `RouteTable`.
- [x] Return local, peer, subnetProxy, or drop.
- [x] Test IPv4 classification.
- [x] Test IPv6 classification.
- [x] Test unknown route produces drop.
- [x] Run packet classifier tests.
- [x] Commit.

### Task 12: Wire Packet Tunnel To MeshEngine

**Files:**
- Modify: `SpotierNE/PacketTunnelProvider.swift`
- Modify: `SpotierNE/TunnelHelper.swift`
- Create: `SpotierCore/Runtime/PacketTunnelIO.swift`
- Test: `SpotierNETests/PacketTunnelIOTests.swift`

- [x] Add `PacketTunnelIO` wrapper around `NEPacketTunnelFlow`.
- [x] Start `MeshEngine` in `startTunnel(options:completionHandler:)`.
- [x] Feed packets from `packetFlow.readPackets` into `MeshEngine`.
- [x] Write packets emitted by `MeshEngine` back through `packetFlow.writePackets`.
- [x] Remove all TUN file descriptor discovery logic.
- [x] Remove calls to `EasyTierCore.setTunFd`.
- [x] Keep `setTunnelNetworkSettings` as the only network settings path.
- [x] Test `PacketTunnelIO` with a fake packet flow abstraction if the target cannot instantiate `NEPacketTunnelFlow`.
- [x] Run packet tunnel IO tests.
- [x] Commit.

### Task 13: Replace Running Info

**Files:**
- Modify: `SpotierNE/InfoModels.swift`
- Create: `SpotierCore/Runtime/RunningInfoSnapshot.swift`
- Modify: `SpotierNE/PacketTunnelProvider.swift`
- Modify: `Spotier/VPNManager.swift`
- Test: `SpotierNETests/InfoModelIPv6Tests.swift`
- Test: `SpotierTests/RunningInfoSnapshotTests.swift`

- [x] Define `RunningInfoSnapshot` from Swift core state.
- [x] Preserve existing JSON fields consumed by the app.
- [x] Generate peer list from `PeerStore`.
- [x] Generate route list from `RouteTable`.
- [x] Generate NAT and transport fields from transport state.
- [x] Serve `running_info` provider message from Swift core.
- [x] Remove `EasyTierCore.getRunningInfo`.
- [x] Update tests for the new snapshot source.
- [x] Run running info snapshot tests.
- [x] Commit.

### Task 14: Implement NAT Discovery And Hole Punch Coordination

**Files:**
- Create: `SpotierCore/NAT/STUNClient.swift`
- Create: `SpotierCore/NAT/HolePunchCoordinator.swift`
- Modify: `SpotierCore/Mesh/PeerManager.swift`
- Test: `SpotierTests/HolePunchCoordinatorTests.swift`

- [x] Implement STUN binding request and response parsing.
- [x] Discover public UDP endpoint from configured STUN server.
- [x] Publish endpoint candidates through control messages.
- [x] Coordinate simultaneous UDP probes with peer endpoint candidates.
- [x] Promote direct UDP transport only after authenticated peer response.
- [x] Keep relay transport active as an explicit route until direct transport is confirmed.
- [x] Test STUN response parsing using fixture bytes.
- [x] Test endpoint candidate exchange.
- [x] Test direct transport promotion.
- [x] Run hole punch coordinator tests.
- [x] Commit.

### Task 15: Implement Relay Server Compatibility Contract

**Files:**
- Create: `plans/relay_protocol_contract.md`
- Modify: `SpotierCore/Transport/RelayTransport.swift`
- Test: `SpotierTests/RelayProtocolContractTests.swift`

- [x] Decide whether Spotier Swift core speaks to existing EasyTier relay nodes or Spotier-owned relay nodes.
- [x] Existing EasyTier relay compatibility is not required for this implementation pass.
- [x] Document Spotier-owned relay protocol as Spotier protocol v1.
- [x] Add contract tests from local relay fixtures.
- [x] Do not support both relay protocols in the same implementation pass.
- [x] Run relay protocol contract tests.
- [x] Commit the relay contract before coding protocol-specific behavior.

### Task 16: Replace Host App FFI Usage

**Files:**
- Modify: `Spotier/VPNManager.swift`
- Modify: `Spotier/EasyTierShared.swift`
- Modify: `SpotierNE/EasyTierShared.swift`
- Delete: `SpotierNE/SwiftierCore.swift`
- Test: `SpotierTests/MainConnectionUseCaseTests.swift`

- [x] Remove any app-side knowledge of Rust symbols.
- [x] Keep App Group config writing.
- [x] Keep `NETunnelProviderManager` lifecycle.
- [x] Keep provider IPC through `sendProviderMessage`.
- [x] Remove `SwiftierCore.swift` from project target membership.
- [x] Delete `SpotierNE/SwiftierCore.swift`.
- [x] Run app lifecycle tests.
- [x] Commit.

### Task 17: Remove Rust Build Inputs

**Files:**
- Delete: `EasyTierCore/`
- Modify: `Spotier.xcodeproj/project.pbxproj`
- Modify: `.gitignore` if it only exists for Rust artifacts

- [x] Remove static library references.
- [x] Remove header search paths pointing at `EasyTierCore/include`.
- [x] Remove library search paths pointing at Rust build outputs.
- [x] Remove build phases that invoke Cargo.
- [x] Remove generated Rust artifacts from the project navigator.
- [ ] Delete `EasyTierCore/`. Deferred because `EasyTierCore/easytier-patched` contains pre-existing uncommitted changes.
- [x] Run: `rg "EasyTierCore|Cargo|libeasytier|SwiftierCore|run_network_instance|set_tun_fd|free_string"`
- [x] Confirm the search returns no runtime references.
- [x] Build `Spotier` scheme for macOS without Rust linker inputs.
- [x] Commit.

### Task 18: Add App Store Platform Entitlement Audit

**Files:**
- Create: `plans/apple_platform_entitlement_checklist.md`
- Modify: app and extension entitlement files if present
- Modify: `Spotier.xcodeproj/project.pbxproj`

- [x] Confirm macOS app target has Packet Tunnel entitlement.
- [x] Confirm iOS app target has Packet Tunnel entitlement if the target exists.
- [x] Confirm tvOS app target has Packet Tunnel entitlement if the target exists.
- [x] Confirm app and extension share the same App Group.
- [x] Confirm no privileged helper entitlement remains.
- [x] Confirm VPN privacy text and data collection notes are documented.
- [x] Build `Spotier` scheme for macOS.
- [x] Commit.

### Task 19: Add End-To-End Local Mesh Test Harness

**Files:**
- Create: `SpotierTests/MeshIntegrationTests.swift`
- Create: `SpotierTests/TestDoubles/InMemoryTransport.swift`
- Create: `SpotierTests/TestDoubles/FakePacketFlow.swift`

- [x] Create two `MeshEngine` instances in one test process.
- [x] Connect them with `InMemoryTransport`.
- [x] Exchange hello messages.
- [x] Establish encrypted session.
- [x] Install host routes.
- [x] Send one IPv4 packet from engine A to engine B.
- [x] Assert engine B emits the decrypted IP packet.
- [x] Send one IPv6 packet from engine B to engine A.
- [x] Assert engine A emits the decrypted IP packet.
- [x] Commit.

### Task 20: Build And Verification Commands

**Files:**
- Modify only files required by failing build or tests.

- [x] Run: `xcodebuild -project Spotier.xcodeproj -scheme Spotier -destination 'platform=macOS' build`
- [x] Run: `xcodebuild -project Spotier.xcodeproj -scheme Spotier -destination 'platform=macOS' test`
- [x] Run Swift core iOS SDK typecheck: `xcrun swiftc -typecheck $(find SpotierCore -name '*.swift' -print | sort) -sdk $(xcrun --sdk iphoneos --show-sdk-path) -target arm64-apple-ios15.0 -module-name SpotierCore`.
- [x] Run Swift core tvOS SDK typecheck: `xcrun swiftc -typecheck $(find SpotierCore -name '*.swift' -print | sort) -sdk $(xcrun --sdk appletvos --show-sdk-path) -target arm64-apple-tvos17.0 -module-name SpotierCore`.
- [x] Launch the macOS app.
- [ ] Start VPN tunnel. Blocked for Debug build by existing TestFlight-created `Spotier VPN` profile signature requirement; `nesessionmanager` rejects the Development-signed Debug provider.
- [ ] Confirm Packet Tunnel logs show Swift `MeshEngine` startup. Blocked until the VPN profile is recreated by the Debug app or verified from a matching-signed install.
- [ ] Confirm no Rust symbols appear in crash logs or runtime logs. Current connected TestFlight provider logs still contain Rust; Debug provider does not pass NetworkExtension signature validation yet.
- [ ] Confirm provider IPC returns running info. Blocked until the Debug provider can stay connected.
- [ ] Confirm app dashboard renders peer and route state. Blocked until the Debug provider can stay connected.
- [x] Commit final verification fixes.

## Completion Checklist

- [x] Runtime scan returns no references in `Spotier`, `SpotierNE`, `SpotierCore`, tests, or `Spotier.xcodeproj`: `EasyTierCore|Cargo|libeasytier|SwiftierCore|run_network_instance|set_tun_fd|free_string`.
- [x] `SpotierNE/PacketTunnelProvider.swift` has no TUN file descriptor scanning.
- [x] `SpotierNE/PacketTunnelProvider.swift` reads and writes packets through Packet Tunnel flow only.
- [x] `SpotierCore/Runtime/MeshEngine.swift` is the only core runtime entry point.
- [x] All control-plane wire messages have encode/decode tests.
- [x] All data-plane encryption paths have positive and negative tests.
- [x] Route convergence is covered by tests.
- [x] Relay transport is covered by tests.
- [x] NAT candidate exchange is covered by tests.
- [ ] Host app can start and stop the tunnel. Blocked for Debug build by existing TestFlight-created VPN profile signature requirement.
- [ ] Host app can display running info from Swift core. Blocked until the Debug provider can stay connected.
- [x] macOS build passes.
- [x] Swift core typechecks against the iOS SDK.
- [x] Swift core typechecks against the tvOS SDK. `NEPacketTunnelFlow` requires tvOS 17.0, so the Swift Package declares tvOS 17 as the core package floor.
- [x] The app and extension contain no Rust build dependency needed for runtime. `EasyTierCore/` source still exists because `EasyTierCore/easytier-patched` has pre-existing uncommitted changes.

## Post-Plan EasyTier Parity Hardening

- [x] Reject data frames addressed to broadcast; only broadcast `hello` control frames are accepted.
- [x] Prefer the longest matching subnet route before route cost, matching Rust LPM route lookup behavior.
- [x] Ignore `peerPing` from unknown peers instead of creating a control-plane response outside an existing peer connection.
- [x] Keep `routeUpdate` from refreshing peer liveness before authenticated session checks.
- [x] Sort running-info route rows by IPv4 address for deterministic Rust-compatible output.
- [x] Skip invalid MagicDNS hostnames while preserving Unicode hostname records.
- [x] Drop IPv6 packets from foreign link-local sources unless the source is the configured local IPv6 address.
- [x] Forward IPv4 broadcast/multicast and IPv6 multicast packets to all known peers using the encrypted data path.
- [x] Drop IPv6 link-local destination packets instead of routing them through exit nodes.
- [x] Treat IPv4/IPv6 network last-address destinations as mesh fan-out using the configured prefix length.
- [x] Respond to ICMP echo requests sent to the MagicDNS resolver address.
- [x] Compute IPv4 UDP checksums for MagicDNS DNS responses.
- [x] Preserve IPv4 header length/options when MagicDNS rewrites DNS and ICMP responses.
- [x] Skip non-UDP bootstrap peers in the UDP-only Swift transport path instead of silently sending UDP to TCP URLs.
- [x] Generate new default configs in standalone Swift-core mode without EasyTier public server peers.
- [x] Hide unsupported EasyTier public server mode from the Swift-core config generator.
- [x] Align core config parser fixtures with Swift-core UDP bootstrap examples instead of EasyTier public server examples.
- [x] Omit unsupported Rust-only config fields from newly generated Swift-core TOML while preserving old-config parsing.
- [x] Fail Swift core startup when configured listeners exist but none are UDP-backed Swift transports.
- [x] Fail Swift core startup when configured peers exist but none use the UDP-backed Swift bootstrap path.
- [x] Add a Swift Package entry point for `SpotierCore` covering iOS, tvOS, and macOS source-level builds.
- [x] Align config generator listener examples with the UDP-only Swift transport path.
- [x] Remove the new-config port forwarding UI entry because Swift core no longer generates `[[port_forward]]`.
- [x] Hide unsupported Rust-only advanced config controls while keeping old-config parsing intact.
- [x] Delete dead SwiftUI form code for unsupported Rust-only advanced controls.
- [x] Allow `MeshEngine` bootstrap over explicitly injected Spotier relay transports without weakening UDP-only default startup validation.
- [x] Preserve remote endpoint schemes in Swift-core running-info tunnel output instead of reporting relay/TCP peers as UDP.
- [x] Remove stale localized strings for hidden Rust-only config generator controls and EasyTier public-server TCP examples.
- [x] Delete unreachable EasyTier public-server UI branch from the Swift-core config generator form.

## Explicitly Out Of Scope

- [x] No Linux support.
- [x] No Windows support.
- [x] No Android support.
- [x] No OpenWrt support.
- [x] No privileged helper replacement.
- [x] No QUIC transport in the first complete Swift core unless UDP and relay are already passing end-to-end tests.
- [x] No WireGuard portal until native Spotier peer-to-peer and relay data paths are complete.
- [x] No compatibility layer that keeps Rust alive behind Swift wrappers.

//
//  SpotierRunner.swift
//  Swiftier
//
//  Created by Alick on 2024.
//

import Foundation
import Combine
import SwiftUI
import NetworkExtension

@MainActor
final class SpotierRunner: ObservableObject {
    static let shared = SpotierRunner()
    private let configRepository: ConfigFileAccessing = ConfigFileRepository.shared

    @Published var isRunning = false
    @Published var peers: [PeerInfo] = []
    @Published var peerCount: String = "0"
    @Published var downloadSpeed: String = "0 KB/s"
    @Published var uploadSpeed: String = "0 KB/s"
    @Published var maxHistorySpeed: Double = 1_048_576.0 // 缓存最大网速计算结果
    @Published var isWindowVisible = true
    @Published var uptimeText: String = "00:00:00"
    
    // 公开最后一次数据更新的时间戳，供 UI 层做动画相位对齐
    @Published private(set) var lastDataTime: Date?
    
    private var startedAt: Date?
    @Published private(set) var sessionID = UUID()
    private var currentSessionID = UUID()
    
    // Speed calculation
    private var lastTotalRx: Int = 0
    private var lastTotalTx: Int = 0
    private var lastPollTime: Date?
    private var lastProcessingTime: Date?
    
    private let jsonDecoder = JSONDecoder()
    
    @Published var virtualIP: String = ""
    
    // Speed history for graphs
    @Published var downloadHistory: [Double] = Array(repeating: 0.0, count: 20)
    @Published var uploadHistory: [Double] = Array(repeating: 0.0, count: 20)
    
    // Subscriber & Polling Control
    private var subscriberCount = 0
    private var pollingTimer: AnyCancellable?
    private let activeInterval: TimeInterval = 1.0
    private let lowPowerInterval: TimeInterval = 5.0
    
    @Published var isProcessing = false
    
    private var statusObserver: AnyCancellable?

    private init() {
        // Listen to VPNManager status changes
        statusObserver = VPNManager.shared.$status.sink { [weak self] status in
            Task { @MainActor [weak self] in
                self?.handleVPNStatusChange(status)
            }
        }
        
        // Check initial state
        syncWithVPNState()
    }
    
    func addSubscriber() {
        subscriberCount += 1
        updatePollingMode()
    }
    
    func removeSubscriber() {
        subscriberCount = max(0, subscriberCount - 1)
        updatePollingMode()
    }
    
    private func updatePollingMode() {
        guard isRunning else {
            pollingTimer?.cancel()
            return
        }
        
        let interval: TimeInterval
        if subscriberCount > 0 {
            interval = activeInterval
        } else {
            interval = lowPowerInterval
        }
        
        pollingTimer?.cancel()
        pollingTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshPeersOnce()
            }
    }
    
    private func handleVPNStatusChange(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            if !isRunning {
                beginSession(connectedDate: VPNManager.shared.connectedDate ?? Date())
            }
            isProcessing = false
        case .disconnected, .invalid:
            if isRunning {
                endSession()
            }
            isProcessing = false
        case .connecting, .disconnecting, .reasserting:
            isProcessing = true
        @unknown default:
            break
        }
    }

    func syncWithVPNState() {
        let status = VPNManager.shared.status
        print("[Runner] syncWithVPNState: status = \(status.rawValue)")
        handleVPNStatusChange(status)
    }
    
    // MARK: - Control Actions

    func toggleService(configPath: String) {
        if isProcessing { return }
        
        if isRunning {
            // 手动关闭时先禁用 On Demand，否则系统会立刻重连
            VPNManager.shared.disableOnDemandAndStop()
        } else {
            // Start
            // 手动启动时恢复 On Demand（之前手动关闭时会禁用）
            if UserDefaults.standard.bool(forKey: "connectOnStart") {
                VPNManager.shared.updateOnDemand(enabled: true)
            }
            
            // 使用 ConfigManager 读取（处理安全域）
            do {
                let configURL = URL(fileURLWithPath: configPath)
                let configContent = try configRepository.readContent(at: configURL)
                VPNManager.shared.startVPN(configContent: configContent)
            } catch {
                print("Failed to read config for VPN: \(error)")
            }
        }
    }
    
    private func startMonitoring() {
        resetSpeedCounters()
        updatePollingMode()
        refreshPeersOnce()
    }
    
    private func resetSpeedCounters() {
        lastTotalRx = 0
        lastTotalTx = 0
        lastPollTime = nil
        lastProcessingTime = nil
        lastDataTime = nil
        downloadHistory = Array(repeating: 0.0, count: 20)
        uploadHistory = Array(repeating: 0.0, count: 20)
    }

    private func refreshPeersOnce() {
        guard isRunning else { return }
        
        // Request running info directly from NE via IPC
        VPNManager.shared.requestRunningInfo { [weak self] json in
            guard let self = self, let json = json else { return }
            Task { @MainActor in
                self.processRunningInfo(json)
            }
        }
    }
    
    // ... processRunningInfo, formatSpeed, formatBytes, Uptime Timer logic remains mostly the same ...
    // Copying the rest of the logic to ensure it works.

    private var throttleInterval: TimeInterval = 0.8

    private func processRunningInfo(_ jsonStr: String) {
        let now = Date()
        if let lastProcessingTime, now.timeIntervalSince(lastProcessingTime) < throttleInterval {
            return
        }
        guard let data = jsonStr.data(using: .utf8) else { return }
        let status: SpotierStatus
        do {
            status = try jsonDecoder.decode(SpotierStatus.self, from: data)
        } catch {
            return
        }

        lastProcessingTime = now
        LogParser.shared.updateEventsFromRunningInfo(status.events)

        var totalRx = 0
        var totalTx = 0
        var fetchedPeers: [PeerInfo] = []

        for pair in status.peerRoutePairs {
            guard let peer = pair.peer else { continue }
            for conn in peer.conns {
                guard let stats = conn.stats else { continue }
                totalRx += stats.rxBytes
                totalTx += stats.txBytes
            }
        }

        if let myNode = status.myNodeInfo {
            fetchedPeers.append(PeerInfo(
                sessionID: currentSessionID,
                ipv4: myNode.virtualIPv4?.description ?? "",
                hostname: myNode.hostname,
                cost: "本机",
                latency: "0",
                loss: "0.0%",
                rx: formatBytes(totalRx),
                tx: formatBytes(totalTx),
                tunnel: "LOCAL",
                nat: myNode.stunInfo?.udpNATType.description ?? "",
                version: myNode.version,
                myNodeData: myNode
            ))
        }

        for pair in status.peerRoutePairs {
            var rxText = "0 B"
            var txText = "0 B"
            var latencyText = ""
            var lossText = ""
            var tunnelText = ""

            if let peer = pair.peer {
                var rxBytes = 0
                var txBytes = 0
                var latencySum = 0
                var latencyCount = 0
                var lossSum = 0.0
                var lossCount = 0
                var tunnels = Set<String>()

                for conn in peer.conns {
                    if let stats = conn.stats {
                        latencySum += stats.latencyUs
                        latencyCount += 1
                        rxBytes += stats.rxBytes
                        txBytes += stats.txBytes
                    }

                    lossSum += conn.lossRate
                    lossCount += 1

                    if let tunnelType = conn.tunnel?.tunnelType {
                        tunnels.insert(tunnelType.uppercased())
                    }
                }

                rxText = formatBytes(rxBytes)
                txText = formatBytes(txBytes)
                if latencyCount > 0 {
                    latencyText = String(format: "%.1f", Double(latencySum) / Double(latencyCount) / 1000.0)
                }
                if lossCount > 0 {
                    lossText = String(format: "%.1f%%", (lossSum / Double(lossCount)) * 100.0)
                }
                tunnelText = tunnels.sorted().joined(separator: "&")
            } else if pair.route.pathLatency > 0 {
                latencyText = String(format: "%.1f", Double(pair.route.pathLatency) / 1000.0)
            }

            fetchedPeers.append(PeerInfo(
                sessionID: currentSessionID,
                ipv4: pair.route.ipv4Addr?.description ?? "",
                hostname: pair.route.hostname,
                cost: pair.route.cost == 1 ? "P2P" : "Relay(\(pair.route.cost))",
                latency: latencyText,
                loss: lossText,
                rx: rxText,
                tx: txText,
                tunnel: tunnelText,
                nat: pair.route.stunInfo?.udpNATType.description ?? "",
                version: pair.route.version,
                fullData: pair
            ))
        }

        let sortedPeers = fetchedPeers.sorted { p1, p2 in
            let is1Local = p1.cost == "本机"
            let is2Local = p2.cost == "本机"
            if is1Local != is2Local { return is1Local }

            let is1Empty = p1.ipv4.isEmpty
            let is2Empty = p2.ipv4.isEmpty
            if is1Empty != is2Empty { return !is1Empty }

            return p1.ipv4.localizedStandardCompare(p2.ipv4) == .orderedAscending
        }

        let receiveSpeed: Double
        let transmitSpeed: Double
        if let lastPollTime, now.timeIntervalSince(lastPollTime) > 0.1 {
            let elapsed = now.timeIntervalSince(lastPollTime)
            receiveSpeed = max(0, Double(totalRx - lastTotalRx) / elapsed)
            transmitSpeed = max(0, Double(totalTx - lastTotalTx) / elapsed)
        } else {
            receiveSpeed = 0
            transmitSpeed = 0
        }

        self.lastTotalRx = totalRx
        self.lastTotalTx = totalTx
        self.lastPollTime = now

        lastDataTime = now
        virtualIP = status.myNodeInfo?.virtualIPv4?.description ?? ""
        downloadSpeed = formatSpeed(receiveSpeed)
        uploadSpeed = formatSpeed(transmitSpeed)
        downloadHistory.removeFirst()
        downloadHistory.append(receiveSpeed)
        uploadHistory.removeFirst()
        uploadHistory.append(transmitSpeed)
        maxHistorySpeed = max(
            downloadHistory.max() ?? 0.0,
            uploadHistory.max() ?? 0.0,
            1_048_576.0
        )

        let oldIDs = peers.map(\.id)
        let newIDs = sortedPeers.map(\.id)

        if oldIDs != newIDs {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                peers = sortedPeers
            }
        } else {
            peers = sortedPeers
        }
        peerCount = "\(sortedPeers.count)"
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        let kb = bytesPerSec / 1024.0
        if kb < 1024 { return String(format: "%.1f KB/s", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB/s", mb)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024.0)
    }

    private var uptimeTimer: Timer?

    private func beginSession(connectedDate: Date) {
        guard !isRunning else { return }

        let nextSessionID = UUID()
        isRunning = true
        startedAt = connectedDate
        currentSessionID = nextSessionID
        sessionID = nextSessionID
        startUptimeTimer()
        startMonitoring()
    }

    private func endSession() {
        isRunning = false
        startedAt = nil
        stopUptimeTimer()
        peers = []
        peerCount = "0"
        uptimeText = "00:00:00"
        downloadSpeed = "0 KB/s"
        uploadSpeed = "0 KB/s"
        virtualIP = ""
        resetSpeedCounters()
    }

    private func startUptimeTimer() {
        guard uptimeTimer == nil else { return }
        updateUptimeText()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateUptimeText()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        uptimeTimer = t
    }
    
    private func stopUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }
    
    private func updateUptimeText() {
        guard let sAt = startedAt else { return }
        let interval = Int(Date().timeIntervalSince(sAt))
        let h = interval / 3600; let m = (interval % 3600) / 60; let s = interval % 60
        let newText = String(format: "%02d:%02d:%02d", h, m, s)
        if uptimeText != newText { uptimeText = newText }
    }
}

import SwiftUI
import Combine

@MainActor
class LogParser: ObservableObject {
    static let shared = LogParser()
    
    @Published var logs: [LogEntry] = []
    @Published var events: [EventEntry] = []
    
    var isPaused = false
    private var pendingLogs: [LogEntry] = []
    private let logResolver: LogContainerResolver
    private let logSettingsStore: LogSettingsStore
    private init() {
        self.logResolver = .shared
        self.logSettingsStore = .shared
        self.events = []
    }

    private var xpcEventTimer: Timer?
    private var isReading = false
    private var lastReadOffset: UInt64 = 0
    private var trailingRemainder = ""
    
    private let maxLogItems = 1000
    private let maxEventItems = 200
    
    private var seenEventHashes: Set<Int> = []
    
    func startMonitoring() {
        // Source 1: XPC Events (Structured, Real-time)
        // In Sandbox mode, we cannot read /var/log/ directly.
        // We rely entirely on XPC to get logs from the Helper.
        if #available(macOS 13.0, *) {
            startXPCEventPolling()
        }
    }
    
    @available(macOS 13.0, *)
    private func startXPCEventPolling() {
        xpcEventTimer?.invalidate()
        xpcEventTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollXPCEvents()
            }
        }
        pollXPCEvents()
    }
    
    @available(macOS 13.0, *)
    private func pollXPCEvents() {
        readNewRawLines()
    }
    
    // MARK: - Pre-compiled Regex Cache (Optimized for performance)
    private enum Regex {
        static let ansi = try! NSRegularExpression(pattern: "(\\x1B\\[[0-9;]*[a-zA-Z])|(\\[[0-9;]+m)", options: [])
        static let timestamp = try! NSRegularExpression(pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?", options: [])
        static let levelPrefix = try! NSRegularExpression(pattern: "^(INFO|WARN|ERROR|DEBUG|TRACE)\\b", options: [.caseInsensitive])
        static let helperPrefix = try! NSRegularExpression(pattern: "^(\\[.*?\\] )?\\[Helper\\]( Core output:)?", options: [])
    }

    private func removeAnsiCodes(_ text: String) -> String {
        let range = NSRange(location: 0, length: text.utf16.count)
        return Regex.ansi.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private func quickParseLogs(_ content: String) -> [LogEntry] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var result: [LogEntry] = []
        let now = ISO8601DateFormatter().string(from: Date())
        
        let currentLogLevel = logSettingsStore.readLevel()
        
        for line in lines {
            let raw = removeAnsiCodes(line).replacingOccurrences(of: "\0", with: "")
            if raw.isEmpty { continue }
            
            var content = raw
            let fullRange = NSRange(location: 0, length: content.utf16.count)
            if let match = Regex.helperPrefix.firstMatch(in: content, range: fullRange) {
                content = (content as NSString).replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespaces)
            }
            if content.isEmpty { continue }
            
            var timestamp = ""
            var level: LogLevel = .info
            let contentRange = NSRange(location: 0, length: content.utf16.count)
            if let match = Regex.timestamp.firstMatch(in: content, range: contentRange) {
                timestamp = (content as NSString).substring(with: match.range)
                content = (content as NSString).replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespaces)
            } else {
                timestamp = now
            }
            
            let levelSearchArea = content.prefix(20).uppercased()
            if levelSearchArea.contains("ERROR") { level = .error }
            else if levelSearchArea.contains("WARN") { level = .warn }
            else if levelSearchArea.contains("DEBUG") { level = .debug }
            else if levelSearchArea.contains("TRACE") { level = .trace }

            if !currentLogLevel.allows(level) { continue }
            
            if let match = Regex.levelPrefix.firstMatch(in: content, range: NSRange(location: 0, length: content.utf16.count)) {
                content = (content as NSString).replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespaces)
            }
            
            result.append(LogEntry(
                timestamp: timestamp,
                cleanContent: content,
                fullText: raw,
                level: level
            ))
        }
        return result
    }
    
    private func readNewRawLines() {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }

        guard let logURL = logResolver.logFileURL() else { return }
        guard FileManager.default.fileExists(atPath: logURL.path) else { return }

        guard let handle = FileHandle(forReadingAtPath: logURL.path) else { return }
        defer { handle.closeFile() }

        // Get file size; reset offset if file was truncated (log rotation)
        let fileSize = handle.seekToEndOfFile()
        if lastReadOffset > fileSize {
            lastReadOffset = 0
            trailingRemainder = ""
        }

        guard fileSize > lastReadOffset else { return }

        handle.seek(toFileOffset: lastReadOffset)
        let newData = handle.readDataToEndOfFile()
        lastReadOffset = handle.offsetInFile

        guard let newText = String(data: newData, encoding: .utf8), !newText.isEmpty else { return }

        let fullText = trailingRemainder + newText
        var lines = fullText.components(separatedBy: "\n")

        // Keep incomplete last line for next read
        if !newText.hasSuffix("\n") {
            trailingRemainder = lines.removeLast()
        } else {
            trailingRemainder = ""
            if lines.last?.isEmpty == true { lines.removeLast() }
        }

        let content = lines.joined(separator: "\n")
        guard !content.isEmpty else { return }

        let parsed = quickParseLogs(content)
        guard !parsed.isEmpty else { return }

        if isPaused {
            pendingLogs.append(contentsOf: parsed)
        } else {
            logs.append(contentsOf: parsed)
            if logs.count > maxLogItems {
                logs.removeFirst(logs.count - maxLogItems)
            }
        }
    }
    
    func stopMonitoring() {
        xpcEventTimer?.invalidate()
        xpcEventTimer = nil
        isReading = false
    }
    
    func resetForNewCoreSession() {
        stopMonitoring()
        events.removeAll()
        logs.removeAll()
        pendingLogs.removeAll()
        isReading = false
        lastReadOffset = 0
        trailingRemainder = ""
        seenEventHashes.removeAll()
    }

    /// Update events from get_running_info response
    func updateEventsFromRunningInfo(_ eventsAnyArray: [String]) {
        var newEvents: [EventEntry] = []
        
        for item in eventsAnyArray {
            guard let event = LogEventFormatter.parseEventEntry(from: item) else { continue }
            let dedupKey = "\(event.name)|\(event.timestamp)|\(event.details)"
            let eventHash = dedupKey.hashValue
            if seenEventHashes.contains(eventHash) { continue }
            seenEventHashes.insert(eventHash)
            
            newEvents.append(event)
        }
        
        guard !newEvents.isEmpty else { return }
        
        events.append(contentsOf: newEvents)
        events.sort { $0.timestamp < $1.timestamp }
        if events.count > maxEventItems {
            events = Array(events.suffix(maxEventItems))
        }
    }
    
    func flushPending() {
        guard !pendingLogs.isEmpty else {
            return
        }
        logs.append(contentsOf: pendingLogs)
        pendingLogs.removeAll()
        if logs.count > maxLogItems {
            logs.removeFirst(logs.count - maxLogItems)
        }
    }
}

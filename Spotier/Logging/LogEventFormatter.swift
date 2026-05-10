import Foundation

enum LogEventFormatter {
    private static let stringRegex = try! NSRegularExpression(pattern: #""([^"\\]|\\.)*""#)
    private static let keyRegex = try! NSRegularExpression(pattern: #"("[^"]+"|\b[a-zA-Z_][a-zA-Z0-9_]*\b)\s*:"#)
    private static let numberRegex = try! NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#)
    private static let keywordRegex = try! NSRegularExpression(pattern: #"\b(true|false|null|None|Some|Ok|Err)\b"#)
    private static let arrayRegex = try! NSRegularExpression(pattern: #"(?s)\[\s*([^\[\]{}]*?)\s*\]"#)

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parseEventEntry(from input: Any) -> EventEntry? {
        guard let json = jsonObject(from: input) else { return nil }
        guard let timeString = json["time"] as? String else { return nil }
        guard let eventData = json["event"] else { return nil }

        let eventName: String
        let eventPayload: Any
        if let eventDict = eventData as? [String: Any],
           eventDict.count == 1,
           let firstKey = eventDict.keys.first {
            eventName = firstKey
            eventPayload = eventDict[firstKey]!
        } else {
            guard let rawEventName = eventData as? String else { return nil }
            eventName = rawEventName
            eventPayload = eventData
        }

        let eventDate = iso8601Formatter.date(from: timeString)
        let displayTimestamp = timeString
            .replacingOccurrences(of: "Z", with: "")
            .replacingOccurrences(of: "T", with: " ")
        let type = mapEventType(eventName)
        let cleanedPayload = recursiveJsonClean(eventPayload, depth: 0)
        let details = formatAsJson(cleanedPayload)

        return EventEntry(
            name: eventName,
            timestamp: displayTimestamp,
            date: eventDate,
            type: type,
            details: details,
            highlights: calculateHighlights(for: details)
        )
    }

    static func calculateHighlights(for json: String) -> [HighlightRange] {
        let nsString = json as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        var ranges: [HighlightRange] = []

        appendHighlights(
            in: json,
            regex: stringRegex,
            fullRange: fullRange,
            color: "green",
            bold: false,
            into: &ranges
        )
        appendHighlights(
            in: json,
            regex: keyRegex,
            fullRange: fullRange,
            color: "blue",
            bold: true,
            into: &ranges
        )
        appendHighlights(
            in: json,
            regex: numberRegex,
            fullRange: fullRange,
            color: "orange",
            bold: false,
            into: &ranges
        )
        appendHighlights(
            in: json,
            regex: keywordRegex,
            fullRange: fullRange,
            color: "purple",
            bold: true,
            into: &ranges
        )

        return ranges
    }

    private static func appendHighlights(
        in text: String,
        regex: NSRegularExpression,
        fullRange: NSRange,
        color: String,
        bold: Bool,
        into ranges: inout [HighlightRange]
    ) {
        for match in regex.matches(in: text, range: fullRange) {
            ranges.append(
                HighlightRange(
                    start: match.range.location,
                    length: match.range.length,
                    color: color,
                    bold: bold
                )
            )
        }
    }

    private static func recursiveJsonClean(_ value: Any?, depth: Int) -> Any? {
        guard let value, depth < 5 else {
            return value
        }

        if let dict = value as? [String: Any] {
            var cleaned = [String: Any]()
            for (key, nestedValue) in dict {
                cleaned[key] = recursiveJsonClean(nestedValue, depth: depth + 1)
            }
            return cleaned
        }

        if let array = value as? [Any] {
            return array.map { recursiveJsonClean($0, depth: depth + 1) }
        }

        return value
    }

    private static func jsonObject(from input: Any) -> [String: Any]? {
        if let dict = input as? [String: Any] {
            return dict
        }

        guard let str = input as? String, let data = str.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func mapEventType(_ name: String) -> EventEntry.EventType {
        switch name {
        case "Connecting", "ConnectingTo":
            return .connecting
        case "Connected", "ConnectionAccepted":
            return .connected
        case "ConnectError", "ConnectionError":
            return .connectError
        case "PeerConnAdded":
            return .peerConnAdded
        case "PeerAdded", "NewPeer":
            return .peerAdded
        case "PeerRemoved", "PeerLost":
            return .peerRemoved
        case "RouteChanged", "RouteUpdate":
            return .routeChanged
        case "TunDeviceReady":
            return .tunDeviceReady
        case "ListenerAdded":
            return .listenerAdded
        case "Handshake":
            return .handshake
        default:
            return .unknown
        }
    }

    private static func collapsePrettyPrintedArrays(_ input: String) -> String {
        var result = input
        let matches = arrayRegex.matches(
            in: result,
            options: [],
            range: NSRange(location: 0, length: (result as NSString).length)
        )

        for match in matches.reversed() {
            let content = (result as NSString).substring(with: match.range(at: 1))
            let collapsedContent = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let collapsed = "[\(collapsedContent)]"
            result = (result as NSString).replacingCharacters(in: match.range, with: collapsed)
        }

        return result
    }

    private static func formatAsJson(_ value: Any?) -> String {
        guard let value else {
            return "null"
        }

        if !(value is [String: Any]) && !(value is [Any]) {
            return "\(value)"
        }

        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if #available(macOS 10.13, *) {
            options.insert(.prettyPrinted)
        }
        if #available(macOS 10.15, *) {
            options.insert(.withoutEscapingSlashes)
        }

        let data = try! JSONSerialization.data(withJSONObject: value, options: options)
        return collapsePrettyPrintedArrays(String(decoding: data, as: UTF8.self))
    }
}

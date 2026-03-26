import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var mode: Mode = .toml
    var isEditable: Bool = true

    private static let tomlPatterns: [(NSRegularExpression, NSColor, Bool)] = [
        (try! NSRegularExpression(pattern: "^\\s*\\[.+\\]", options: [.anchorsMatchLines]), .systemOrange, true),
        (try! NSRegularExpression(pattern: "^\\s*[a-zA-Z0-9_-]+\\s*(?==)", options: [.anchorsMatchLines]), .systemBlue, false),
        (try! NSRegularExpression(pattern: "#.*$", options: [.anchorsMatchLines]), .secondaryLabelColor, false)
    ]

    private static let logPatterns: [(NSRegularExpression, NSColor, Bool)] = [
        (try! NSRegularExpression(pattern: "^\\[[^\\]]+\\]", options: [.anchorsMatchLines]), .secondaryLabelColor, false),
        (try! NSRegularExpression(pattern: "\\[easytier_core::[^\\]]+\\]", options: []), .secondaryLabelColor, false),
        (try! NSRegularExpression(pattern: "(?i)ERROR|FATAL", options: []), .systemRed, true),
        (try! NSRegularExpression(pattern: "(?i)WARN|WARNING", options: []), .systemOrange, true),
        (try! NSRegularExpression(pattern: "(?i)INFO", options: []), .systemGreen, true),
        (try! NSRegularExpression(pattern: "(?i)DEBUG", options: []), .systemCyan, true),
        (try! NSRegularExpression(pattern: "(?i)TRACE", options: []), .systemBlue, true),
        (try! NSRegularExpression(pattern: "Spotier", options: []), .labelColor, true)
    ]

    private static let jsonPatterns: [(NSRegularExpression, NSColor, Bool)] = [
        (try! NSRegularExpression(pattern: "\"[^\"]+\"\\s*:", options: []), .systemBlue, true),
        (try! NSRegularExpression(pattern: ":\\s*\"[^\"]*\"", options: []), .systemGreen, false),
        (try! NSRegularExpression(pattern: ":\\s*[0-9]+\\.?[0-9]*", options: []), .systemOrange, false),
        (try! NSRegularExpression(pattern: "\\b(true|false|null)\\b", options: []), .systemPurple, true),
        (try! NSRegularExpression(pattern: "[\\[\\]\\{\\}]", options: []), .secondaryLabelColor, false)
    ]
    
    enum Mode {
        case toml
        case log
        case json
    }
    
    // 高亮逻辑
    func highlight(_ storage: NSTextStorage) {
        let string = storage.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)
        
        func applyStyle(_ regex: NSRegularExpression, color: NSColor, bold: Bool = false) {
            regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
                if let range = match?.range {
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                    if bold {
                        storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: range)
                    }
                }
            }
        }
        
        if mode == .toml {
            // 1. 重置基础样式 (TOML)
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.removeAttribute(.font, range: fullRange)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: fullRange)
            for (regex, color, bold) in Self.tomlPatterns {
                applyStyle(regex, color: color, bold: bold)
            }
        } else if mode == .log {
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.removeAttribute(.font, range: fullRange)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
            let font = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            storage.addAttribute(.font, value: font, range: fullRange)
            for (regex, color, bold) in Self.logPatterns {
                applyStyle(regex, color: color, bold: bold)
            }
        } else if mode == .json {
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.removeAttribute(.font, range: fullRange)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
            let font = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            storage.addAttribute(.font, value: font, range: fullRange)
            for (regex, color, bold) in Self.jsonPatterns {
                applyStyle(regex, color: color, bold: bold)
            }
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        let textView = NSTextView()
        textView.autoresizingMask = [.width, .height]
        textView.allowsUndo = true
        textView.drawsBackground = false // 透明背景
        textView.textColor = .labelColor // 自适应文字颜色
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isEditable = isEditable
        textView.textContainerInset = NSSize(width: 12, height: 12)
        
        // Disable all automatic text systems to prevent 'autofill' and other background processes
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        
        // 关键设置：容器自动调整
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        
        // 设置 Delegate
        textView.delegate = context.coordinator
        
        scrollView.documentView = textView
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // 只在内容不同时更新，避免死循环
        if textView.string != text {
            textView.string = text
            highlight(textView.textStorage!)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        
        init(_ parent: CodeEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // 实时更新高亮
            parent.highlight(textView.textStorage!)
            
            // 更新绑定
            parent.text = textView.string
        }
    }
}

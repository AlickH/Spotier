import SwiftUI
import AppKit

struct ConfigGeneratorView: View {
    @Binding var isPresented: Bool
    var editingFileURL: URL? = nil // 支持传入文件进行编辑
    var onSave: () -> Void
    
    @State private var model = SpotierConfigModel()
    @State private var lastLoadedURL: URL? = nil

    // Navigation
    @State private var path: [ConfigScreen] = [.main]
    
    var body: some View {
        ZStack {
            mainView
                .zIndex(0)
                .allowsHitTesting(path.last == .main)
            
            if let screen = path.last, screen != .main {
                
                Group {
                    switch screen {
                    case .advanced: advancedView
                    case .portForwarding: portForwardingView
                    default: EmptyView()
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .zIndex(1)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.default, value: path.last)
        .onAppear {
            if isPresented {
                loadContent(forceReset: true)
            }
        }
        .onChange(of: editingFileURL) { _ in
            loadContent(forceReset: true)
        }
        .onChange(of: isPresented) { presented in
            if presented {
                loadContent(forceReset: true)
            }
        }
        // Save draft on every change
        .onChange(of: model) { newModel in
            if isPresented {
                ConfigGeneratorStore.saveDraft(newModel, editingFileURL: editingFileURL)
            }
        }
    }
    
    private func loadContent(forceReset: Bool = false) {
        let result = ConfigGeneratorStore.loadModel(
            editingFileURL: editingFileURL,
            forceReset: forceReset,
            currentModel: model,
            lastLoadedURL: lastLoadedURL
        )
        model = result.model
        lastLoadedURL = result.lastLoadedURL
    }
    
    // MARK: - Advanced View
    var advancedView: some View {
        VStack(spacing: 0) {
            header(title: LocalizedStringKey("高级设置"), leftBtn: LocalizedStringKey("返回"), leftRole: .cancel) { pop() }

            ConfigGeneratorAdvancedForm(model: $model)
        }
    }
    
    // MARK: - Main View
    var mainView: some View {
        VStack(spacing: 0) {
            header(title: LocalizedStringKey("配置生成器"), leftBtn: LocalizedStringKey("取消"), leftRole: .destructive, rightBtn: LocalizedStringKey("生成")) {
                // Clear draft on cancel so next open reads from disk
                ConfigGeneratorStore.clearDraft(editingFileURL: editingFileURL)
                withAnimation { isPresented = false }
            } rightAction: {
                generateAndSave()
            }

            ConfigGeneratorMainForm(
                model: $model,
                onOpenAdvanced: { push(.advanced) },
                onOpenPortForwarding: { push(.portForwarding) }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Port Forwarding (Image 1)
    var portForwardingView: some View {
        VStack(spacing: 0) {
            header(title: LocalizedStringKey("端口转发"), leftBtn: LocalizedStringKey("返回"), leftRole: .cancel) { pop() }

            ConfigGeneratorPortForwardingForm(model: $model)
        }
    }
    
    
    
    // MARK: - Components
    
    private func header(title: LocalizedStringKey, leftBtn: LocalizedStringKey, leftRole: ButtonRole? = .cancel, rightBtn: LocalizedStringKey? = nil, leftAction: @escaping () -> Void, rightAction: (() -> Void)? = nil) -> some View {
        UnifiedHeader(title: title) {
            Button(leftBtn, role: leftRole, action: leftAction)
                .buttonStyle(.bordered)
        } right: {
            if let rightBtn = rightBtn, let rightAction = rightAction {
                Button(rightBtn, action: rightAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.networkName.isEmpty)
            } else {
                Button(leftBtn) {}.buttonStyle(.bordered).hidden()
            }
        }
    }
    
    // MARK: - Logic
    
    private func push(_ screen: ConfigScreen) {
        // No animation block here, the state change triggers body animation
        path.append(screen)
    }
    
    private func pop() {
        _ = path.popLast()
    }
    
    private func generateAndSave() {
        try! ConfigGeneratorStore.save(model: model, editingFileURL: editingFileURL)
        onSave()
        isPresented = false
    }
    
    
    // MARK: - Native IPv4 + CIDR Input (NSViewRepresentable)
    
    struct IPv4CidrField: NSViewRepresentable {
        @Binding var ip: String
        @Binding var cidr: String
        
        func makeNSView(context: Context) -> NSStackView {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 1
            stack.alignment = .centerY
            stack.distribution = .fill // 改回默认 fill，因为我们希望它尽量紧凑
            
            // 关键：让 StackView 尽可能收缩宽度，不要被拉伸，这样 Spacer 才能把它推到右边
            stack.setHuggingPriority(.required, for: .horizontal)
            
            // --- 4 Octets ---
            for i in 0..<4 {
                let tf = MacOctetTextField()
                tf.tag = i // 0, 1, 2, 3
                tf.placeholderString = "0"
                tf.isBordered = false
                tf.drawsBackground = false
                tf.focusRingType = .none
                tf.alignment = .center
                tf.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
                tf.delegate = context.coordinator
                tf.backspaceDelegate = context.coordinator
                
                // 增加宽度以容纳 3 位数字。固定宽度 36pt 比较稳妥且整齐。
                tf.widthAnchor.constraint(equalToConstant: 36).isActive = true
                
                stack.addArrangedSubview(tf)
                
                // Dot separator
                if i < 3 {
                    let dot = NSTextField(labelWithString: ".")
                    dot.textColor = .secondaryLabelColor
                    dot.font = NSFont.systemFont(ofSize: 13)
                    stack.addArrangedSubview(dot)
                }
            }
            
            // --- Divider ---
            let slash = NSTextField(labelWithString: " / ")
            slash.textColor = .secondaryLabelColor
            slash.font = NSFont.systemFont(ofSize: 13)
            stack.addArrangedSubview(slash)
            
            // --- CIDR Menu ---
            let popup = NSPopUpButton()
            popup.bezelStyle = .inline
            popup.isBordered = false
            popup.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            popup.addItems(withTitles: ["0", "8", "16", "24", "32"])
            popup.target = context.coordinator
            popup.action = #selector(Coordinator.cidrChanged(_:))
            
            stack.addArrangedSubview(popup)
            
            context.coordinator.stackView = stack
            return stack
        }
        
        func updateNSView(_ nsView: NSStackView, context: Context) {
            context.coordinator.updateFields(from: ip, cidr: cidr)
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }
        
        class Coordinator: OctetFieldCoordinator {
            var parent: IPv4CidrField
            
            init(parent: IPv4CidrField) {
                self.parent = parent
            }
            
            override func syncToModel() {
                parent.ip = currentIP()
            }

            func updateFields(from ip: String, cidr: String) {
                updateFields(from: ip)
                guard !isInternalUpdate, let stack = stackView else { return }
                for view in stack.arrangedSubviews {
                    if let popup = view as? NSPopUpButton {
                        let title = cidr.isEmpty ? "24" : cidr
                        if popup.titleOfSelectedItem != title {
                            popup.selectItem(withTitle: title)
                        }
                    } else if let popup = view as? NSPopUpButton {
                        popup.selectItem(withTitle: cidr)
                    }
                }
            }
            
            @objc func cidrChanged(_ sender: NSPopUpButton) {
                parent.cidr = sender.titleOfSelectedItem!
            }
        }
    }
    
    // MARK: - Native IPv4 Input (No CIDR)
    struct IPv4Field: NSViewRepresentable {
        @Binding var ip: String
        
        func makeNSView(context: Context) -> NSStackView {
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 1
            stack.alignment = .centerY
            stack.distribution = .fill
            stack.setHuggingPriority(.required, for: .horizontal)
            
            for i in 0..<4 {
                let tf = MacOctetTextField()
                tf.tag = i
                tf.placeholderString = "0"
                tf.isBordered = false
                tf.drawsBackground = false
                tf.focusRingType = .none
                tf.alignment = .center
                tf.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
                tf.delegate = context.coordinator
                tf.backspaceDelegate = context.coordinator
                tf.widthAnchor.constraint(equalToConstant: 36).isActive = true
                stack.addArrangedSubview(tf)
                
                if i < 3 {
                    let dot = NSTextField(labelWithString: ".")
                    dot.textColor = .secondaryLabelColor
                    dot.font = NSFont.systemFont(ofSize: 13)
                    stack.addArrangedSubview(dot)
                }
            }
            
            context.coordinator.stackView = stack
            return stack
        }
        
        func updateNSView(_ nsView: NSStackView, context: Context) {
            context.coordinator.updateFields(from: ip)
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }
        
        class Coordinator: OctetFieldCoordinator {
            var parent: IPv4Field
            
            init(parent: IPv4Field) {
                self.parent = parent
            }
            
            override func syncToModel() {
                parent.ip = currentIP()
            }
        }
    }

    class OctetFieldCoordinator: NSObject, NSTextFieldDelegate, OctetTextFieldDelegate {
        weak var stackView: NSStackView?
        var isInternalUpdate = false

        func updateFields(from ip: String) {
            guard !isInternalUpdate, let stack = stackView else { return }

            let parts = ip.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            var tfIndex = 0
            for view in stack.arrangedSubviews {
                guard let tf = view as? NSTextField, view is MacOctetTextField else { continue }
                let val = tfIndex < parts.count ? parts[tfIndex] : ""
                if tf.stringValue != val {
                    tf.stringValue = val
                }
                tfIndex += 1
            }
        }

        func currentIP() -> String {
            guard let stack = stackView else { return "" }
            var parts = [String]()
            for view in stack.arrangedSubviews {
                if let tf = view as? MacOctetTextField {
                    parts.append(tf.stringValue)
                }
            }
            while parts.count < 4 { parts.append("") }
            return parts.joined(separator: ".")
        }

        func syncToModel() {}

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? MacOctetTextField else { return }

            let filtered = tf.stringValue.filter { "0123456789".contains($0) }
            if filtered != tf.stringValue {
                tf.stringValue = filtered
            }
            if tf.stringValue.count > 3 {
                tf.stringValue = String(tf.stringValue.prefix(3))
            }
            if let num = Int(tf.stringValue), num > 255 {
                tf.stringValue = "255"
            }

            isInternalUpdate = true
            syncToModel()
            isInternalUpdate = false

            if tf.stringValue.count == 3 {
                focusField(at: tf.tag + 1)
            }
        }

        func didPressBackspaceOnEmpty(in textField: MacOctetTextField) {
            let prevIndex = textField.tag - 1
            if prevIndex >= 0 {
                focusField(at: prevIndex, deleteLastChar: true)
            }
        }

        func focusField(at index: Int, deleteLastChar: Bool = false) {
            guard let stack = stackView, index >= 0 && index < 4 else { return }
            let targetView = stack.arrangedSubviews.compactMap { $0 as? MacOctetTextField }.first { $0.tag == index }
            guard let tf = targetView else { return }

            tf.window?.makeFirstResponder(tf)
            if deleteLastChar && !tf.stringValue.isEmpty {
                tf.stringValue = String(tf.stringValue.dropLast())
                isInternalUpdate = true
                syncToModel()
                isInternalUpdate = false
            }
            if let editor = tf.currentEditor() {
                let length = tf.stringValue.count
                editor.selectedRange = NSRange(location: length, length: 0)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSStandardKeyBindingResponding.deleteBackward(_:)),
               let tf = control as? MacOctetTextField,
               tf.stringValue.isEmpty {
                didPressBackspaceOnEmpty(in: tf)
                return true
            }
            return false
        }
    }
    
    // 代理协议：用于传递 Backspace 事件
    protocol OctetTextFieldDelegate: AnyObject {
        func didPressBackspaceOnEmpty(in textField: MacOctetTextField)
    }
    
    // 自定义 NSTextField 捕获 Backspace
    class MacOctetTextField: NSTextField {
        weak var backspaceDelegate: OctetTextFieldDelegate?
        // Delegate handles doCommandBy for backspace
    }
    
}

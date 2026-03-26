import SwiftUI
import AppKit

struct CopyableDetailRow: View {
    let label: LocalizedStringKey
    let value: String
    var isMonospaced: Bool = false

    @State private var isCopied = false

    var body: some View {
        Button(action: copyValue) {
            HStack(alignment: .center, spacing: 0) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                Text(LocalizedStringKey(value))
                    .font(
                        isMonospaced
                        ? .system(size: 13, weight: .regular, design: .monospaced)
                        : .system(size: 13)
                    )
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
                    .opacity(isCopied ? 0.5 : 1.0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(value)
    }

    private func copyValue() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        withAnimation(.easeInOut(duration: 0.1)) {
            isCopied = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation {
                isCopied = false
            }
        }
    }
}

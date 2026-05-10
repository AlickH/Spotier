import SwiftUI
import AppKit

/// A robust utility to find the underlying NSScrollView of a SwiftUI ScrollView and apply specific configurations.
/// This bypasses SwiftUI's limitations by interacting directly with the AppKit layer.
struct ScrollFixer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let scrollView = findScrollView(for: nsView) else { return }
        scrollView.verticalScrollElasticity = .none
        scrollView.hasVerticalScroller = false
        scrollView.usesPredominantAxisScrolling = false
    }
    
    private func findScrollView(for view: NSView) -> NSScrollView? {
        var current: NSView? = view.superview
        while let s = current {
            if let sv = s as? NSScrollView {
                return sv
            }
            current = s.superview
        }
        return nil
    }
}

extension View {
    func lockVerticalScroll() -> some View {
        self.background(ScrollFixer())
    }
    
    /// 阻止垂直滚动传播，同时保留transition动画
    /// 适用于横向ScrollView，防止竖向滑动时的回弹效果
    func preventVerticalBounce() -> some View {
        self.background(
            GeometryReader { _ in
                Color.clear.background(
                    ScrollFixer()
                )
            }
        )
    }
}

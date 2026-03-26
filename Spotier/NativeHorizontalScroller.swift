import SwiftUI
import AppKit

class HorizontalOnlyScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            return
        }

        super.scrollWheel(with: event)
    }
}

struct NativeHorizontalScroller<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroller = HorizontalOnlyScrollView()
        scroller.hasHorizontalScroller = false
        scroller.hasVerticalScroller = false
        scroller.drawsBackground = false
        scroller.autohidesScrollers = true
        scroller.horizontalScrollElasticity = .allowed
        scroller.verticalScrollElasticity = .none

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scroller.documentView = hostingView

        if let doc = scroller.documentView {
            doc.topAnchor.constraint(equalTo: scroller.contentView.topAnchor).isActive = true
            doc.leadingAnchor.constraint(equalTo: scroller.contentView.leadingAnchor).isActive = true
        }

        return scroller
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let host = nsView.documentView as? NSHostingView<Content> {
            host.rootView = content

            let fittingSize = host.fittingSize
            if host.frame.size != fittingSize {
                host.frame.size = fittingSize
            }
        }
    }
}

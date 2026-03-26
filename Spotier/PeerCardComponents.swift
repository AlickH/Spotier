import SwiftUI

struct ScrollingText: View {
    let text: String

    @State private var offset: CGFloat = 0
    @State private var isHovering = false
    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear.onAppear { textWidth = textGeometry.size.width }
                        }
                    )
                    .opacity(0)

                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
                    .animation(
                        shouldAnimate
                        ? .linear(duration: Double(textWidth / 60)).repeatForever(autoreverses: true)
                        : .default,
                        value: offset
                    )
            }
            .onAppear { containerWidth = geometry.size.width }
            .onChange(of: isHovering) { hovering in
                if hovering && textWidth > containerWidth {
                    offset = -(textWidth - containerWidth + 8)
                } else {
                    offset = 0
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .clipped()
    }

    private var shouldAnimate: Bool {
        isHovering && textWidth > containerWidth
    }
}

struct Tag: View {
    let text: LocalizedStringKey
    var color: Color = .gray

    var body: some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

import SwiftUI

struct FloatingScrollTopButton: View {
    let action: () -> Void
    var size: CGFloat = 20

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    Circle()
                        .fill(Color.blue)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

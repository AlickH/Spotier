import SwiftUI

// MARK: - Unified Header Component

/// 统一风格的页面 Header 布局容器
/// 仅负责布局结构，样式完全由内部按钮的系统 Style 决定
struct UnifiedHeader<LeftBtn: View, RightBtn: View>: View {
    let leftButton: LeftBtn
    let centerContent: AnyView
    let rightButton: RightBtn

    init(
        title: LocalizedStringKey,
        @ViewBuilder left: @escaping () -> LeftBtn,
        @ViewBuilder right: @escaping () -> RightBtn
    ) {
        self.leftButton = left()
        self.centerContent = AnyView(
            Text(title)
                .font(.headline)
                .lineLimit(1)
        )
        self.rightButton = right()
    }

    init(
        @ViewBuilder left: @escaping () -> LeftBtn,
        @ViewBuilder center: @escaping () -> some View,
        @ViewBuilder right: @escaping () -> RightBtn
    ) {
        self.leftButton = left()
        self.centerContent = AnyView(center())
        self.rightButton = right()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                leftButton
                
                Spacer()
                
                centerContent
                
                Spacer()
                
                rightButton
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor)) // 保持背景一致
            
            Divider()
        }
    }
}

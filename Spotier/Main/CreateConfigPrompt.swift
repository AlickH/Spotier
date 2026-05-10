import SwiftUI

struct CreateConfigPrompt: View {
    @Binding var newConfigName: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(LocalizedStringKey("创建新网络"))
                .font(.headline)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey("配置文件名:"))
                TextField(LocalizedStringKey("例如: my-network"), text: $newConfigName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.none)
                    .disableAutocorrection(true)
                    .onSubmit(onConfirm)
                Text(LocalizedStringKey("将自动添加 .toml 后缀"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            HStack {
                Button(LocalizedStringKey("取消"), action: onCancel)
                Button(LocalizedStringKey("创建"), action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        .shadow(radius: 20)
    }
}

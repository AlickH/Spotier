import SwiftUI

struct MainDashboardHeader: View {
    let configFiles: [URL]
    let selectedConfig: URL?
    let iCloudDriveEnabled: Bool
    let hasICloudIdentity: Bool
    let onSelectConfig: (URL) -> Void
    let onCreateNetwork: () -> Void
    let onOpenGenerator: () -> Void
    let onOpenEditor: () -> Void
    let onDisableICloudDrive: () -> Void
    let onEnableICloudDrive: () -> Void
    let onSelectFolder: () -> Void
    let onOpenFolder: () -> Void
    let onDeleteSelected: () -> Void
    let onOpenLog: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack {
            configMenu

            Spacer()

            actionButtons
        }
        .padding(DashboardLayoutMetrics.headerPadding)
        .zIndex(200)
    }

    private var configMenu: some View {
        Menu {
            Section("配置文件") {
                storageLabel

                if configFiles.isEmpty {
                    Button("未发现配置") { }
                        .disabled(true)
                } else {
                    ForEach(configFiles, id: \.self) { url in
                        Button(action: { onSelectConfig(url) }) {
                            HStack {
                                Text(url.deletingPathExtension().lastPathComponent)
                                if selectedConfig == url {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            Button("创建新网络", action: onCreateNetwork)
            Button("编辑配置", action: onOpenGenerator)
                .disabled(selectedConfig == nil)
            Button("编辑配置为文件", action: onOpenEditor)
                .disabled(selectedConfig == nil)

            Divider()

            if iCloudDriveEnabled {
                Button("关闭 iCloud Drive", action: onDisableICloudDrive)
            } else {
                Button("存储到 iCloud Drive", action: onEnableICloudDrive)
            }
            Button("选择文件夹", action: onSelectFolder)
                .disabled(iCloudDriveEnabled)
            Button("在 Finder 中打开", action: onOpenFolder)

            Divider()

            Button(role: .destructive, action: onDeleteSelected) {
                Text(LocalizedStringKey("删除选中的配置"))
                    .foregroundColor(.red)
            }
            .disabled(selectedConfig == nil)
        } label: {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text(selectedConfig?.deletingPathExtension().lastPathComponent ?? NSLocalizedString("请选择配置", comment: ""))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var storageLabel: some View {
        if iCloudDriveEnabled {
            Label("存储位置: iCloud Drive", systemImage: "icloud")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if hasICloudIdentity {
            Label("存储位置: 本地（可切换到 iCloud Drive）", systemImage: "internaldrive")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Label("存储位置: 本地 (iCloud 未启用)", systemImage: "internaldrive")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button(action: onOpenLog) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

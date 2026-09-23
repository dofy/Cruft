import AppKit
import Darwin
import SwiftUI

@MainActor
final class FolderAccessManager: ObservableObject {
    static let shared = FolderAccessManager()

    @Published private(set) var hasFullDiskAccess = false
    @Published private(set) var isChecking = false

    private init() {}

    func check() {
        guard !isChecking else { return }
        isChecking = true
        Task.detached(priority: .userInitiated) {
            let allowed = Self.checkFullDiskAccess()
            await MainActor.run {
                self.hasFullDiskAccess = allowed
                self.isChecking = false
            }
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// FDA has no public authorization-status API. Checking read permission on
    /// protected app-data directories avoids enumerating their contents and does
    /// not trigger the per-folder consent dialogs used by Desktop/Downloads.
    nonisolated static func checkFullDiskAccess() -> Bool {
        let probes = [
            "~/Library/Containers/com.apple.stocks",
            "~/Library/Safari",
            "~/Library/Mail",
        ]

        return probes.contains { rawPath in
            let path = (rawPath as NSString).expandingTildeInPath
            return path.withCString { access($0, R_OK) == 0 }
        }
    }
}

struct FolderAccessBanner: View {
    let isChecking: Bool
    let showDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isChecking ? "hourglass" : "folder.badge.questionmark")
                .foregroundStyle(CruftTheme.accentGradient)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(isChecking ? "正在检查文件访问权限" : "文件访问尚未开启")
                    .font(.callout.weight(.semibold))
                Text(isChecking
                     ? "检查完成前不会读取任何清理目录。"
                     : "Cruft 尚未扫描缓存、日志、项目、下载或废纸篓。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if !isChecking {
                Button("开启访问", action: showDetails)
                    .buttonStyle(.borderedProminent)
                    .tint(CruftTheme.coral)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial)
    }
}

struct FolderAccessSheet: View {
    @ObservedObject var manager: FolderAccessManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(CruftTheme.accentGradient)
                        .opacity(0.16)
                    Image(systemName: manager.hasFullDiskAccess ? "checkmark.shield.fill" : "folder.badge.gearshape")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(manager.hasFullDiskAccess ? AnyShapeStyle(Color.green) : AnyShapeStyle(CruftTheme.accentGradient))
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(manager.hasFullDiskAccess ? "文件访问已开启" : "开启完全磁盘访问")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("由 macOS 管理，可随时在系统设置中关闭")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Cruft 需要读取用户目录中的开发缓存、日志、项目产物、下载文件和废纸篓，才能估算空间并执行你确认的清理。文件内容只在本机处理，不会上传。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("授权步骤")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Label("打开“隐私与安全性 → 完全磁盘访问”", systemImage: "1.circle.fill")
                    Label("添加或开启 /Applications/Cruft.app", systemImage: "2.circle.fill")
                    Label("返回 Cruft；应用会自动重新检查", systemImage: "3.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Label("未授权时，Cruft 不会扫描清理目录。", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    manager.check()
                } label: {
                    Label(manager.isChecking ? "正在检查…" : "重新检查", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isChecking)

                if !manager.hasFullDiskAccess {
                    Button("打开系统设置") {
                        manager.openSystemSettings()
                    }
                    .buttonStyle(AccentButtonStyle())
                }
            }
        }
        .padding(22)
        .frame(width: 500)
        .onChange(of: manager.hasFullDiskAccess) { _, allowed in
            if allowed { dismiss() }
        }
    }
}

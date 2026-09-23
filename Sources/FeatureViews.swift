import AppKit
import SwiftUI

struct CleanPane: View {
    @ObservedObject var vm: CleanerViewModel
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConfirm = false
    @State private var showLog = false

    private var logAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "清理",
                subtitle: "把可重建的开发缓存送进废纸篓",
                icon: "sparkles",
                metric: "可用 \(byteString(vm.freeSpace))"
            )
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(CleanupCategory.allCases) { category in
                        let rows = vm.items(in: category)
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(category.rawValue)
                                        .font(.system(.headline, design: .rounded, weight: .semibold))
                                    Spacer()
                                    Text("\(rows.filter { $0.isEnabled }.count) / \(rows.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                SurfaceCard {
                                    VStack(spacing: 0) {
                                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                            TaskRowView(
                                                item: item,
                                                isEnabled: vm.binding(for: item),
                                                locked: vm.isRunning,
                                                sizeState: vm.sizeState(for: item)
                                            )
                                            if index < rows.count - 1 { Divider().padding(.leading, 42) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            logConsole
            Divider()
            footer
        }
        .onChange(of: vm.isRunning) { _, running in
            if running { withAnimation(logAnimation) { showLog = true } }
        }
        .confirmationDialog("开始本次维护？", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("开始清理（\(vm.selectedCount) 项）", role: .destructive) {
                Task { await vm.run() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("文件型任务会移到废纸篓并写入恢复历史；命令型任务、清空废纸篓和 Docker prune 无法恢复。")
        }
    }

    private var logConsole: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(logAnimation) { showLog.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showLog ? 90 : 0))
                    Text("运行日志")
                    if !showLog && !vm.log.isEmpty {
                        Circle().fill(CruftTheme.coral).frame(width: 6, height: 6)
                    }
                    Spacer()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        Text(vm.log.isEmpty ? "任务输出会显示在这里。" : vm.log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(vm.log.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(14)
                            .id("log-tail")
                    }
                    .background(Color.black.opacity(0.035))
                    .opacity(showLog ? 1 : 0)
                    .offset(y: showLog ? 0 : 16)
                    .onChange(of: vm.log) { _, _ in
                        proxy.scrollTo("log-tail", anchor: .bottom)
                    }
                }
                .frame(height: showLog ? 140 : 0, alignment: .bottom)
                .clipped()
                .allowsHitTesting(showLog)
                .accessibilityHidden(!showLog)
            }
        }
        .animation(logAnimation, value: showLog)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if vm.isRunning {
                ProgressView(value: vm.progress)
                    .frame(width: 170)
                Text(vm.currentTask)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if vm.finished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("移到废纸篓 \(byteString(vm.movedToTrashBytes)) · 实际释放 \(byteString(vm.freedBytes))")
                    .font(.callout.weight(.medium))
            } else {
                Text("已选择 \(vm.selectedCount) 项")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                guard hasFolderAccess else {
                    requestFolderAccess()
                    return
                }
                showConfirm = true
            } label: {
                Label("开始维护", systemImage: "play.fill")
            }
            .buttonStyle(AccentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(vm.isRunning || vm.selectedCount == 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

struct ScanPane: View {
    @ObservedObject var vm: ScanViewModel
    let title: String
    let subtitle: String
    let icon: String
    let emptyHint: String
    let roots: [String]
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: title,
                subtitle: subtitle,
                icon: icon,
                metric: vm.hasScanned ? byteString(vm.totalBytes) : nil
            )
            Divider()

            Group {
                if vm.isScanning {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在扫描…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !vm.hasScanned {
                    EmptyStateView(
                        icon: icon,
                        title: "从一次安全扫描开始",
                        message: vm.mode == .projects
                            ? "扫描 Works、Projects、Developer；最近 7 天使用过的项目默认不勾选。"
                            : "扫描下载目录和桌面。安装包始终由你逐个选择。"
                    )
                } else if vm.items.isEmpty {
                    EmptyStateView(icon: "checkmark.seal", title: "这里很干净", message: emptyHint)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(vm.items) { item in
                                ScanRowView(item: item) { vm.toggle(item.id) }
                            }
                        }
                        .padding(24)
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                if vm.hasScanned {
                    Text("选中 \(vm.selectedCount) 项 · \(byteString(vm.selectedBytes))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚未扫描").font(.callout).foregroundStyle(.secondary)
                }
                if vm.lastFailedCount > 0 {
                    Text("· \(vm.lastFailedCount) 项移动失败")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    if hasFolderAccess {
                        vm.scan(roots: roots)
                    } else {
                        requestFolderAccess()
                    }
                } label: {
                    Label(vm.hasScanned ? "重新扫描" : "扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.isScanning || vm.isDeleting)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(vm.selectedCount == 0 || vm.isScanning || vm.isDeleting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .confirmationDialog("移到废纸篓？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("移动 \(vm.selectedCount) 项", role: .destructive) {
                Task { _ = await vm.deleteSelected() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将保存路径映射，可从“恢复历史”移回原位置；清空废纸篓后将无法恢复。")
        }
    }
}

struct ApplicationsPane: View {
    @ObservedObject var vm: AppCleanerViewModel
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "应用清理",
                subtitle: "卸载应用，并审阅它留在用户目录中的关联文件",
                icon: "app.badge.checkmark",
                metric: vm.hasScannedApps ? "\(vm.apps.count) 个应用" : nil
            )
            Divider()

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索应用或 Bundle ID", text: $vm.query)
                    .textFieldStyle(.plain)
                Spacer()
                if !vm.statusMessage.isEmpty {
                    Text(vm.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    if hasFolderAccess {
                        vm.scanApps()
                    } else {
                        requestFolderAccess()
                    }
                } label: {
                    Label(vm.hasScannedApps ? "重新扫描" : "扫描应用", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(vm.isScanningApps)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(Color.primary.opacity(0.025))
            Divider()

            Group {
                if vm.isScanningApps {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取应用与占用空间…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !vm.hasScannedApps {
                    EmptyStateView(
                        icon: "square.grid.2x2",
                        title: "先建立应用清单",
                        message: "读取 /Applications 和 ~/Applications。只有 Bundle ID 精确匹配的关联文件会默认选中。"
                    )
                } else if vm.filteredApps.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "没有匹配的应用", message: "换一个名称或 Bundle ID 试试。")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(vm.filteredApps) { app in
                                ApplicationRow(app: app) { vm.inspect(app) }
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .sheet(item: $vm.selectedApp) { app in
            AppCleanupSheet(vm: vm, app: app)
        }
    }
}

struct AppCleanupSheet: View {
    @ObservedObject var vm: AppCleanerViewModel
    let app: InstalledApplication
    @Environment(\.dismiss) private var dismiss
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AppIconView(path: app.path, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("清理 \(app.name)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(app.bundleIdentifier.isEmpty ? "未读取到 Bundle ID，仅展示应用本体" : app.bundleIdentifier)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(app.bundleIdentifier.isEmpty ? Color.orange : Color.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                }
                Button("关闭") { dismiss() }
            }
            .padding(20)
            Divider()

            if vm.isScanningRelated {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在匹配关联文件…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("精确匹配默认选中", systemImage: "checkmark.shield")
                            Spacer()
                            Label("名称匹配需手动确认", systemImage: "exclamationmark.triangle")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(vm.candidates) { item in
                            AppCleanupRow(item: item) { vm.toggle(item.id) }
                        }
                    }
                    .padding(20)
                }
            }

            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("选中 \(vm.selectedCount) 项 · \(byteString(vm.selectedBytes))")
                        .font(.callout.weight(.medium))
                    if !vm.statusMessage.isEmpty {
                        Text(vm.statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    showConfirm = true
                } label: {
                    Label(vm.isDeleting ? "正在移动…" : "移到废纸篓", systemImage: "trash")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(vm.selectedCount == 0 || vm.isScanningRelated || vm.isDeleting)
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 540)
        .confirmationDialog("卸载并清理？", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("移动 \(vm.selectedCount) 项", role: .destructive) {
                Task { await vm.moveSelectedToTrash() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选中项将进入废纸篓并写入恢复历史。Cruft 不会强行获取管理员权限，受保护的应用可能移动失败。")
        }
    }
}

struct BackgroundPane: View {
    @ObservedObject var vm: BTMViewModel
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "背景 App",
                subtitle: "只读查看登录项、代理、守护进程和失效记录",
                icon: "bolt.badge.clock",
                metric: vm.hasLoaded ? "\(vm.items.count) 项" : nil
            )
            Divider()

            if vm.hasLoaded {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索名称、开发者、Bundle ID", text: $vm.query)
                        .textFieldStyle(.plain)
                    if vm.orphanCount > 0 {
                        Toggle("只看失效（\(vm.orphanCount)）", isOn: $vm.orphanOnly)
                            .toggleStyle(.checkbox)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Color.primary.opacity(0.025))
                Divider()
            }

            Group {
                if vm.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取系统背景活动…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !vm.hasLoaded {
                    EmptyStateView(
                        icon: "bolt.badge.clock",
                        title: "查看谁在后台运行",
                        message: "数据来自 sfltool dumpbtm；此页面只做观察，不直接修改系统记录。"
                    )
                } else if vm.filtered.isEmpty {
                    EmptyStateView(icon: "checkmark.seal", title: "没有匹配项", message: "清除搜索或关闭失效过滤。")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(vm.filtered) { BTMRowView(item: $0) }
                        }
                        .padding(24)
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                if vm.hasLoaded {
                    Text("启用 \(vm.enabledCount) · 失效 \(vm.orphanCount)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("系统设置", systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    if hasFolderAccess {
                        vm.load()
                    } else {
                        requestFolderAccess()
                    }
                } label: {
                    Label(vm.hasLoaded ? "刷新" : "读取", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(vm.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}

struct HistoryPane: View {
    @ObservedObject var store: DeletionHistoryStore
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "恢复历史",
                subtitle: "把仍在废纸篓中的项目移回原位置",
                icon: "clock.arrow.circlepath",
                metric: hasFolderAccess ? byteString(store.recoverableBytes) : "待授权"
            )
            Divider()

            if store.batches.isEmpty {
                EmptyStateView(
                    icon: "clock.badge.checkmark",
                    title: "还没有恢复记录",
                    message: "项目产物、安装包、应用及文件型清理进入废纸篓后，会在这里留下恢复点。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 11) {
                        ForEach(store.batches) { batch in
                            HistoryBatchRow(
                                store: store,
                                batch: batch,
                                hasFolderAccess: hasFolderAccess,
                                requestFolderAccess: requestFolderAccess
                            )
                        }
                    }
                    .padding(24)
                }
            }

            if !store.statusMessage.isEmpty {
                Divider()
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
        .onAppear {
            if hasFolderAccess { store.refreshAvailability() }
        }
    }
}

struct HistoryBatchRow: View {
    @ObservedObject var store: DeletionHistoryStore
    let batch: DeletionBatch
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void
    @State private var showRestoreConfirm = false

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(CruftTheme.accentGradient)
                        .opacity(0.14)
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(CruftTheme.accentGradient)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(batch.title).font(.headline)
                    Text(batch.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(batch.tasks.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(byteString(batch.totalBytes))
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                    Text(hasFolderAccess
                         ? "\(store.recoverableCount(in: batch)) / \(batch.items.count) 项可恢复"
                         : "授权后检查可恢复状态")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("恢复") {
                    if hasFolderAccess {
                        showRestoreConfirm = true
                    } else {
                        requestFolderAccess()
                    }
                }
                    .buttonStyle(.bordered)
                    .disabled((hasFolderAccess && store.recoverableCount(in: batch) == 0) || store.isRestoring)

                Menu {
                    Button("只移除记录") { store.forget(batch) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .confirmationDialog("恢复到原位置？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("恢复 \(store.recoverableCount(in: batch)) 项") {
                Task { await store.restore(batch) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("如果原位置已经存在同名文件，Cruft 会保留现有文件并跳过该项目。")
        }
    }
}

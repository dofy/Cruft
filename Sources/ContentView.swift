import SwiftUI
import AppKit

// 禁用最大化/全屏；宽高约束交给 SwiftUI 的 windowResizability(.contentSize)
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum Pane: String, CaseIterable, Identifiable {
    case tasks = "清理"
    case projects = "项目产物"
    case installers = "安装包"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var vm = CleanerViewModel()
    @StateObject private var projectsVM = ScanViewModel(mode: .projects)
    @StateObject private var installersVM = ScanViewModel(mode: .installers)
    @State private var pane: Pane = .tasks
    @State private var showConfirm = false
    @State private var showScanDeleteConfirm = false
    @State private var showLog = false

    // 项目产物扫描根目录
    private let projectRoots = ["~/Works", "~/Projects", "~/Developer"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()

            switch pane {
            case .tasks:
                taskList
                Divider()
                logConsole
            case .projects:
                scanPane(projectsVM, emptyHint: "未发现项目产物目录")
            case .installers:
                scanPane(installersVM, emptyHint: "未发现 .dmg / .pkg 安装包")
            }

            Divider()
            footer
        }
        .background(.background)
        .background(WindowConfigurator())
        .onChange(of: vm.isRunning) { _, running in
            if running { withAnimation { showLog = true } }
        }
        .confirmationDialog("确认清理？", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("开始清理 (\(vm.selectedCount) 项)", role: .destructive) {
                Task { await vm.run() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将执行选中的清理与更新任务。删除操作不可撤销，请确认已备份重要数据。")
        }
        .confirmationDialog("移到废纸篓？", isPresented: $showScanDeleteConfirm, titleVisibility: .visible) {
            let svm = activeScanVM
            Button("移到废纸篓 (\(svm?.selectedCount ?? 0) 项)", role: .destructive) {
                Task { await deleteScanSelection() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选中项将移到废纸篓，可在废纸篓中恢复。清空废纸篓后才会真正释放空间。")
        }
    }

    private var activeScanVM: ScanViewModel? {
        switch pane {
        case .projects: return projectsVM
        case .installers: return installersVM
        case .tasks: return nil
        }
    }

    private func deleteScanSelection() async {
        guard let svm = activeScanVM else { return }
        _ = await svm.deleteSelected()
        vm.freeSpace = FileCleaner.freeBytes()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cruft")
                    .font(.title2.weight(.bold))
                Text("清理开发过程中产生的垃圾文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("可用空间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(byteString(vm.freeSpace))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .padding(20)
    }

    // MARK: - Task list

    private var taskList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(CleanupCategory.allCases) { category in
                    let rows = vm.items(in: category)
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.rawValue)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            ForEach(rows) { item in
                                TaskRowView(
                                    item: item,
                                    isEnabled: vm.binding(for: item),
                                    locked: vm.isRunning,
                                    sizeState: vm.sizeState(for: item)
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Scan pane (projects / installers)

    @ViewBuilder
    private func scanPane(_ svm: ScanViewModel, emptyHint: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if svm.isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("扫描中…").font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                } else if !svm.hasScanned {
                    scanPlaceholder(svm)
                } else if svm.items.isEmpty {
                    Text(emptyHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(svm.items) { item in
                        ScanRowView(item: item) { svm.toggle(item.id) }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxHeight: .infinity)
    }

    private func scanPlaceholder(_ svm: ScanViewModel) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(svm.mode == .projects
                 ? "扫描 \(projectRoots.joined(separator: "、")) 下的 node_modules、target、build 等产物"
                 : "扫描 下载 / 桌面 中的安装包")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Log console

    private var logConsole: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation { showLog.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showLog ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Text("日志")
                        .font(.caption.weight(.medium))
                    if !showLog && !vm.log.isEmpty {
                        Circle()
                            .fill(.tint)
                            .frame(width: 5, height: 5)
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .focusable(false)

            if showLog {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(vm.log.isEmpty ? "日志将在这里显示…" : vm.log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(vm.log.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                            .id("logtail")
                    }
                    .frame(height: 150)
                    .background(Color.secondary.opacity(0.06))
                    .onChange(of: vm.log) { _, _ in
                        withAnimation { proxy.scrollTo("logtail", anchor: .bottom) }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch pane {
        case .tasks: taskFooter
        case .projects: scanFooter(projectsVM)
        case .installers: scanFooter(installersVM)
        }
    }

    private var taskFooter: some View {
        HStack(spacing: 14) {
            if vm.isRunning {
                ProgressView(value: vm.progress)
                    .frame(width: 160)
                Text(vm.currentTask)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if vm.finished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("完成，释放 \(byteString(vm.freedBytes))")
                    .font(.callout.weight(.medium))
            } else {
                Text("已选择 \(vm.selectedCount) 项")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showConfirm = true
            } label: {
                Label("清理", systemImage: "play.fill")
                    .frame(minWidth: 70)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .focusable(false)
            .disabled(vm.isRunning || vm.selectedCount == 0)
        }
        .padding(20)
    }

    private func scanFooter(_ svm: ScanViewModel) -> some View {
        HStack(spacing: 14) {
            if svm.isDeleting {
                ProgressView().controlSize(.small)
                Text("正在移到废纸篓…").font(.caption).foregroundStyle(.secondary)
            } else if svm.lastFreed > 0 {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("已移入废纸篓 \(byteString(svm.lastFreed))")
                    .font(.callout.weight(.medium))
            } else if svm.hasScanned {
                Text("选中 \(svm.selectedCount) 项 · \(byteString(svm.selectedBytes)) / 共 \(byteString(svm.totalBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("尚未扫描")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                svm.scan(roots: projectRoots)
            } label: {
                Label(svm.hasScanned ? "重新扫描" : "扫描", systemImage: "magnifyingglass")
                    .frame(minWidth: 70)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .focusable(false)
            .disabled(svm.isScanning || svm.isDeleting)

            Button {
                showScanDeleteConfirm = true
            } label: {
                Label("移到废纸篓", systemImage: "trash")
                    .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .focusable(false)
            .disabled(svm.selectedCount == 0 || svm.isDeleting || svm.isScanning)
        }
        .padding(20)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Task row

struct TaskRowView: View {
    let item: CleanupItem
    @Binding var isEnabled: Bool
    let locked: Bool
    let sizeState: CleanerViewModel.SizeState
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.icon)
                .frame(width: 24)
                .foregroundStyle(item.isAvailable ? Color.primary : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title)
                    .fontWeight(.medium)
                Text(item.isAvailable
                     ? item.kind.subtitle
                     : (item.kind.requiredTool.map { "未安装 \($0)，已禁用" } ?? "未检测到，已禁用"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            sizeBadge

            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("查看清理详情")
            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                DetailPopover(kind: item.kind)
            }

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .focusable(false)
                .disabled(!item.isAvailable || locked)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .opacity(item.isAvailable ? 1 : 0.55)
    }

    @ViewBuilder
    private var sizeBadge: some View {
        switch sizeState {
        case .none:
            EmptyView()
        case .computing:
            Text("计算中…")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .known(let bytes):
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - Scan row

struct ScanRowView: View {
    let item: ScanItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.location) · \(item.daysAgo) 天前")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}

// MARK: - Detail popover

struct DetailPopover: View {
    let kind: CleanupKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(kind.title, systemImage: kind.icon)
                .font(.headline)

            ForEach(Array(kind.details.enumerated()), id: \.offset) { _, detail in
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.target)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text(detail.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }
}

#Preview {
    ContentView()
}

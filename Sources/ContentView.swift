import SwiftUI
import AppKit

// 锁定窗口：禁用缩放/最大化/全屏，固定尺寸
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.remove(.resizable)
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var vm = CleanerViewModel()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            taskList
            Divider()
            logConsole
            Divider()
            footer
        }
        .background(.background)
        .background(WindowConfigurator())
        .confirmationDialog(
            "确认清理？",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("开始清理 (\(vm.selectedCount) 项)", role: .destructive) {
                Task { await vm.run() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将执行选中的清理与更新任务。删除操作不可撤销，请确认已备份重要数据。")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("CleanMyMac")
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

    // MARK: - Log console

    private var logConsole: some View {
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

    // MARK: - Footer

    private var footer: some View {
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
            .disabled(vm.isRunning || vm.selectedCount == 0)
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
                Text(item.isAvailable ? item.kind.subtitle : "未安装 \(item.kind.requiredTool ?? "")，已禁用")
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
            .help("查看清理详情")
            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                DetailPopover(kind: item.kind)
            }

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
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

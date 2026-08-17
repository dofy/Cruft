import SwiftUI

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var items: [CleanupItem]
    @Published var isRunning = false
    @Published var log = ""
    @Published var freeSpace: Int64 = FileCleaner.freeBytes()
    @Published var freedBytes: Int64 = 0
    @Published var currentTask = ""
    @Published var progress: Double = 0
    @Published var finished = false
    @Published var sizes: [String: Int64] = [:] // kind.id -> 估算字节

    enum SizeState {
        case none          // 不可估算（工具类命令）
        case computing     // 计算中
        case known(Int64)  // 已知体积
    }

    init() {
        items = CleanupKind.allCases.map { kind in
            let available = kind.requiredTool.map(Shell.toolExists) ?? true
            return CleanupItem(kind: kind, isEnabled: kind.defaultEnabled && available, isAvailable: available)
        }
        estimateSizes()
    }

    func sizeState(for item: CleanupItem) -> SizeState {
        guard item.kind.isMeasurable else { return .none }
        if let b = sizes[item.id] { return .known(b) }
        return .computing
    }

    // 后台并发估算各目录体积
    func estimateSizes() {
        for item in items where item.kind.isMeasurable {
            sizes.removeValue(forKey: item.id)
            let kind = item.kind
            Task.detached(priority: .utility) {
                let bytes = FileCleaner.size(of: kind.measurablePaths)
                await MainActor.run { self.sizes[kind.id] = bytes }
            }
        }
    }

    var selectedCount: Int { items.filter { $0.isEnabled && $0.isAvailable }.count }

    func items(in category: CleanupCategory) -> [CleanupItem] {
        items.filter { $0.kind.category == category }
    }

    func binding(for item: CleanupItem) -> Binding<Bool> {
        Binding(
            get: { self.items.first { $0.id == item.id }?.isEnabled ?? false },
            set: { newValue in
                if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[idx].isEnabled = newValue
                }
            }
        )
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        finished = false
        freedBytes = 0
        progress = 0
        log = ""

        let before = FileCleaner.freeBytes()
        let selected = items.filter { $0.isEnabled && $0.isAvailable }

        for (i, item) in selected.enumerated() {
            currentTask = item.kind.title
            appendLog("\n==> \(item.kind.title)\n")
            let kind = item.kind
            // 后台执行阻塞命令，输出回主线程
            await Task.detached(priority: .userInitiated) {
                CleanerEngine.execute(kind) { line in
                    Task { @MainActor in self.appendLog(line) }
                }
            }.value
            progress = Double(i + 1) / Double(max(selected.count, 1))
        }

        let after = FileCleaner.freeBytes()
        freedBytes = max(0, after - before)
        freeSpace = after
        currentTask = ""
        isRunning = false
        finished = true
        estimateSizes() // 清理后重新估算，体积应下降
    }

    private func appendLog(_ s: String) {
        log += s
        // 限制日志长度，避免超长文本拖慢 UI
        if log.count > 60_000 {
            log = String(log.suffix(50_000))
        }
    }
}

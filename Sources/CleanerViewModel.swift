import SwiftUI

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var items: [CleanupItem]
    @Published var isRunning = false
    @Published var log = ""
    @Published var freeSpace: Int64 = FileCleaner.freeBytes()
    @Published var totalSpace: Int64 = FileCleaner.totalBytes()
    @Published var freedBytes: Int64 = 0
    @Published var movedToTrashBytes: Int64 = 0
    @Published var currentTask = ""
    @Published var progress: Double = 0
    @Published var finished = false
    @Published var sizes: [String: Int64] = [:] // kind.id -> 估算字节
    @Published private(set) var hasFolderAccess = false

    enum SizeState {
        case none          // 不可估算（工具类命令）
        case computing     // 计算中
        case known(Int64)  // 已知体积
    }

    init() {
        items = CleanupKind.allCases.map { kind in
            let available: Bool
            if let tool = kind.requiredTool {
                available = Shell.toolExists(tool)
            } else {
                // 启动阶段不探测目录；获得 FDA 后再刷新真实可用状态。
                available = true
            }
            return CleanupItem(kind: kind, isEnabled: kind.defaultEnabled && available, isAvailable: available)
        }
    }

    func sizeState(for item: CleanupItem) -> SizeState {
        guard item.kind.isMeasurable else { return .none }
        guard hasFolderAccess else { return .none }
        if let b = sizes[item.id] { return .known(b) }
        return .computing
    }

    func setFolderAccess(_ allowed: Bool) {
        guard hasFolderAccess != allowed else { return }
        hasFolderAccess = allowed
        if allowed {
            refreshAvailability()
            estimateSizes()
        } else {
            sizes.removeAll()
        }
    }

    // 后台并发估算各目录体积
    func estimateSizes() {
        guard hasFolderAccess else { return }
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
        guard hasFolderAccess, !isRunning else { return }
        isRunning = true
        finished = false
        freedBytes = 0
        movedToTrashBytes = 0
        progress = 0
        log = ""

        let before = FileCleaner.freeBytes()
        let chosen = items.filter { $0.isEnabled && $0.isAvailable }
        // 先清空已有废纸篓，再处理总缓存目录，避免同一次运行产生父子路径重叠的恢复记录。
        let selected = chosen.sorted { lhs, rhs in
            cleanupOrder(lhs.kind) < cleanupOrder(rhs.kind)
        }
        var trashedItems: [TrashedItem] = []

        for (i, item) in selected.enumerated() {
            currentTask = item.kind.title
            appendLog("\n==> \(item.kind.title)\n")
            let kind = item.kind
            // 后台执行阻塞命令，输出回主线程
            let result = await Task.detached(priority: .userInitiated) {
                CleanerEngine.execute(kind) { line in
                    Task { @MainActor in self.appendLog(line) }
                }
            }.value
            trashedItems.append(contentsOf: result.trashedItems)
            progress = Double(i + 1) / Double(max(selected.count, 1))
        }

        let after = FileCleaner.freeBytes()
        freedBytes = max(0, after - before)
        movedToTrashBytes = trashedItems.reduce(0) { $0 + $1.size }
        freeSpace = after
        totalSpace = FileCleaner.totalBytes()
        currentTask = ""
        isRunning = false
        finished = true
        DeletionHistoryStore.shared.record(
            title: "常规清理",
            tasks: selected.map(\.kind.title),
            items: trashedItems
        )
        writeHistory(
            tasks: selected.map(\.kind.title),
            freed: freedBytes,
            movedToTrash: movedToTrashBytes
        )
        estimateSizes() // 清理后重新估算，体积应下降
    }

    // 将本次操作追加到 ~/Library/Logs/Cruft/operations.log
    private func writeHistory(tasks: [String], freed: Int64, movedToTrash: Int64) {
        let freedStr = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
        let trashedStr = ByteCountFormatter.string(fromByteCount: movedToTrash, countStyle: .file)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] 释放 \(freedStr) | 移到废纸篓 \(trashedStr) | \(tasks.joined(separator: ", "))\n"
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let dir = ("~/Library/Logs/Cruft" as NSString).expandingTildeInPath
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let file = (dir as NSString).appendingPathComponent("operations.log")
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: file) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: file))
            }
        }
    }

    private func appendLog(_ s: String) {
        log += s
        // 限制日志长度，避免超长文本拖慢 UI
        if log.count > 60_000 {
            log = String(log.suffix(50_000))
        }
    }

    private func refreshAvailability() {
        let fm = FileManager.default
        for index in items.indices {
            let kind = items[index].kind
            let available: Bool
            if let tool = kind.requiredTool {
                available = Shell.toolExists(tool)
            } else if kind.detectionPaths.isEmpty {
                available = true
            } else {
                available = kind.detectionPaths.contains {
                    fm.fileExists(atPath: ($0 as NSString).expandingTildeInPath)
                }
            }
            items[index].isAvailable = available
            if !available { items[index].isEnabled = false }
        }
    }

    private func cleanupOrder(_ kind: CleanupKind) -> Int {
        if kind == .trash { return 0 }
        if kind == .caches { return 1 }
        return (CleanupKind.allCases.firstIndex(of: kind) ?? 0) + 2
    }
}

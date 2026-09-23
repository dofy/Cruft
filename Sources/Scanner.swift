import SwiftUI

// 扫描发现的一条可删除项（动态，区别于固定的 CleanupKind）
struct ScanItem: Identifiable, Hashable {
    let path: String
    let title: String      // 展示名（项目/产物 或 文件名）
    let location: String   // 所在目录
    let size: Int64
    let modified: Date
    var isSelected: Bool
    var id: String { path }

    var daysAgo: Int {
        max(0, Int(Date().timeIntervalSince(modified) / 86_400))
    }
}

enum Scanner {
    // 常见项目产物 / 依赖目录名
    static let artifactDirs: Set<String> = [
        "node_modules", ".next", "dist", "build", "target",
        ".build", "venv", ".venv", "vendor", "Pods", "DerivedData",
    ]

    // 扫描项目产物：遍历根目录，命中产物目录后不再深入
    static func projectArtifacts(roots: [String], maxDepth: Int = 5) -> [ScanItem] {
        let fm = FileManager.default
        var results: [ScanItem] = []
        for root in roots {
            let base = (root as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue else { continue }
            walk(base, depth: 0, maxDepth: maxDepth, fm: fm, into: &results)
        }
        return results.sorted { $0.size > $1.size }
    }

    private static func walk(_ dir: String, depth: Int, maxDepth: Int, fm: FileManager, into results: inout [ScanItem]) {
        guard depth <= maxDepth,
              let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for name in entries {
            // 跳过隐藏目录（.git 等），但保留我们关心的 .build/.next/.venv
            if name.hasPrefix("."), !artifactDirs.contains(name) { continue }
            let full = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }

            if artifactDirs.contains(name) {
                let size = FileCleaner.size(of: [full])
                if size == 0 { continue }
                let attrs = try? fm.attributesOfItem(atPath: full)
                let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
                let project = (dir as NSString).lastPathComponent
                let item = ScanItem(
                    path: full,
                    title: "\(project) / \(name)",
                    location: abbreviate(dir),
                    size: size,
                    modified: mtime,
                    // 最近 7 天动过的项目默认不选，避免误删活跃项目
                    isSelected: max(0, Int(Date().timeIntervalSince(mtime) / 86_400)) >= 7
                )
                results.append(item)
                // 命中即停，不深入产物目录内部
            } else {
                walk(full, depth: depth + 1, maxDepth: maxDepth, fm: fm, into: &results)
            }
        }
    }

    // 扫描安装包：Downloads / Desktop 下的 .dmg / .pkg
    static func installers() -> [ScanItem] {
        let fm = FileManager.default
        var out: [ScanItem] = []
        for root in ["~/Downloads", "~/Desktop"] {
            let base = (root as NSString).expandingTildeInPath
            guard let entries = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for name in entries {
                let ext = (name as NSString).pathExtension.lowercased()
                guard ext == "dmg" || ext == "pkg" else { continue }
                let full = (base as NSString).appendingPathComponent(name)
                let attrs = try? fm.attributesOfItem(atPath: full)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
                out.append(ScanItem(
                    path: full,
                    title: name,
                    location: abbreviate(base),
                    size: size,
                    modified: mtime,
                    isSelected: false // 安装包默认不选，用户逐个确认
                ))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    enum Mode { case projects, installers }
    let mode: Mode
    @Published var items: [ScanItem] = []
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var hasScanned = false
    @Published var lastFreed: Int64 = 0
    @Published var lastFailedCount = 0

    init(mode: Mode) { self.mode = mode }

    var selectedCount: Int { items.filter(\.isSelected).count }
    var selectedBytes: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan(roots: [String]) {
        guard !isScanning else { return }
        isScanning = true
        lastFreed = 0
        lastFailedCount = 0
        let mode = self.mode
        Task.detached(priority: .utility) {
            let found: [ScanItem]
            switch mode {
            case .projects: found = Scanner.projectArtifacts(roots: roots)
            case .installers: found = Scanner.installers()
            }
            await MainActor.run {
                self.items = found
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func toggle(_ id: String) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].isSelected.toggle()
        }
    }

    // 移到废纸篓并写入统一恢复历史，返回移动字节。
    func deleteSelected() async -> Int64 {
        guard !isDeleting else { return 0 }
        isDeleting = true
        let targets = items.filter(\.isSelected)
        let trashed = await Task.detached(priority: .userInitiated) { () -> [TrashedItem] in
            targets.compactMap { FileCleaner.moveToTrash($0.path) }
        }.value
        let deletedPaths = Set(trashed.map(\.originalPath))
        items.removeAll { deletedPaths.contains($0.path) }
        lastFreed = trashed.reduce(0) { $0 + $1.size }
        lastFailedCount = targets.count - trashed.count
        isDeleting = false

        let isProjects = mode == .projects
        DeletionHistoryStore.shared.record(
            title: isProjects
                ? String(localized: "history.batch.projects", defaultValue: "Build products")
                : String(localized: "history.batch.installers", defaultValue: "Installers"),
            tasks: [String(localized: "history.task.trash", defaultValue: "Moved to the Trash")],
            titleKey: isProjects ? DeletionBatch.projectsKey : DeletionBatch.installersKey,
            taskKeys: [DeletionBatch.taskTrashKey],
            items: trashed
        )
        return lastFreed
    }
}

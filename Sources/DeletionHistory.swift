import Foundation
import SwiftUI

struct TrashedItem: Codable, Hashable, Identifiable {
    let originalPath: String
    let trashedPath: String
    let size: Int64

    var id: String { originalPath }
}

struct DeletionBatch: Codable, Hashable, Identifiable {
    let id: UUID
    let createdAt: Date
    /// 写进 deletion-history.json 的标题文案。**存储值**，不要拿它当显示源——
    /// 老记录里是当时那一版语言的字符串。显示走 `displayTitle`。
    let title: String
    /// 同上，存储值。显示走 `displayTasks`。
    let tasks: [String]
    /// 标题的稳定标识。老记录没有这个字段，解码成 nil 后回落到 `title`。
    let titleKey: String?
    /// 标题里要填的名字（目前只有「卸载 <应用名>」用）。
    let titleArgument: String?
    /// 任务的稳定标识：`CleanupKind.rawValue`，或下面 `displayTasks` 里那几个固定 key。
    let taskKeys: [String]?
    var items: [TrashedItem]

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    /// 批次标题，按当前语言渲染；没有 key 的老记录原样显示存下来的字符串。
    var displayTitle: String {
        switch titleKey {
        case DeletionBatch.routineKey:
            return String(localized: "history.batch.routine", defaultValue: "Routine cleanup")
        case DeletionBatch.projectsKey:
            return String(localized: "history.batch.projects", defaultValue: "Build products")
        case DeletionBatch.installersKey:
            return String(localized: "history.batch.installers", defaultValue: "Installers")
        case DeletionBatch.uninstallKey:
            return String(localized: "history.batch.uninstall",
                          defaultValue: "Uninstall \(titleArgument ?? "")")
        default:
            return title
        }
    }

    /// 任务名列表，同样按当前语言渲染。
    var displayTasks: [String] {
        guard let taskKeys else { return tasks }
        return taskKeys.map { key in
            if let kind = CleanupKind(rawValue: key) { return kind.title }
            switch key {
            case DeletionBatch.taskTrashKey:
                return String(localized: "history.task.trash", defaultValue: "Moved to the Trash")
            case DeletionBatch.taskAppKey:
                return String(localized: "history.task.appAndRelated",
                              defaultValue: "The app and its related files")
            default:
                return key
            }
        }
    }

    static let routineKey = "routine"
    static let projectsKey = "projects"
    static let installersKey = "installers"
    static let uninstallKey = "uninstall"
    static let taskTrashKey = "trash"
    static let taskAppKey = "appAndRelated"
}

struct RestoreResult {
    let restored: [TrashedItem]
    let failed: [TrashedItem]
}

@MainActor
final class DeletionHistoryStore: ObservableObject {
    static let shared = DeletionHistoryStore()

    @Published private(set) var batches: [DeletionBatch] = []
    @Published private(set) var isRestoring = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var hasFolderAccess = false

    private let historyURL: URL
    private let maxBatchCount = 20

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cruft", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        historyURL = base.appendingPathComponent("deletion-history.json")
        load()
    }

    var recoverableBytes: Int64 {
        guard hasFolderAccess else { return 0 }
        return batches.reduce(0) { partial, batch in
            partial + batch.items.reduce(0) { itemTotal, item in
                FileManager.default.fileExists(atPath: item.trashedPath)
                    ? itemTotal + item.size
                    : itemTotal
            }
        }
    }

    func recoverableCount(in batch: DeletionBatch) -> Int {
        guard hasFolderAccess else { return 0 }
        return batch.items.filter { FileManager.default.fileExists(atPath: $0.trashedPath) }.count
    }

    func setFolderAccess(_ allowed: Bool) {
        guard hasFolderAccess != allowed else { return }
        hasFolderAccess = allowed
        if allowed { refreshAvailability() }
    }

    func record(
        title: String,
        tasks: [String],
        titleKey: String? = nil,
        titleArgument: String? = nil,
        taskKeys: [String]? = nil,
        items: [TrashedItem]
    ) {
        guard !items.isEmpty else { return }
        let batch = DeletionBatch(
            id: UUID(),
            createdAt: Date(),
            title: title,
            tasks: tasks,
            titleKey: titleKey,
            titleArgument: titleArgument,
            taskKeys: taskKeys,
            items: items
        )
        batches.insert(batch, at: 0)
        if batches.count > maxBatchCount {
            batches = Array(batches.prefix(maxBatchCount))
        }
        statusMessage = String(localized: "history.status.saved",
                               defaultValue: "Restore point saved")
        save()
    }

    func restore(_ batch: DeletionBatch) async {
        guard hasFolderAccess, !isRestoring else { return }
        isRestoring = true
        statusMessage = String(localized: "history.status.restoring", defaultValue: "Restoring…")

        let result = await Task.detached(priority: .userInitiated) {
            Self.restoreItems(batch.items)
        }.value

        if let index = batches.firstIndex(where: { $0.id == batch.id }) {
            if result.failed.isEmpty {
                batches.remove(at: index)
            } else {
                batches[index].items = result.failed
            }
        }

        isRestoring = false
        if result.restored.isEmpty {
            statusMessage = String(localized: "history.status.nothing",
                                   defaultValue: "Nothing could be restored; these may already be out of the Trash")
        } else if result.failed.isEmpty {
            statusMessage = String(localized: "history.status.restored",
                                   defaultValue: "Restored \(result.restored.count) items")
        } else {
            statusMessage = String(localized: "history.status.partial",
                                   defaultValue: "Restored \(result.restored.count) items; \(result.failed.count) conflicted or went missing")
        }
        save()
    }

    func forget(_ batch: DeletionBatch) {
        batches.removeAll { $0.id == batch.id }
        statusMessage = String(localized: "history.status.forgotten",
                               defaultValue: "Record removed; the files in the Trash are untouched")
        save()
    }

    func refreshAvailability() {
        guard hasFolderAccess else { return }
        removeEmptyBatches()
        save()
    }

    nonisolated static func restoreItems(_ items: [TrashedItem]) -> RestoreResult {
        let fm = FileManager.default
        var restored: [TrashedItem] = []
        var failed: [TrashedItem] = []

        for item in items {
            guard fm.fileExists(atPath: item.trashedPath),
                  !fm.fileExists(atPath: item.originalPath) else {
                failed.append(item)
                continue
            }

            let destination = URL(fileURLWithPath: item.originalPath)
            do {
                try fm.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fm.moveItem(
                    at: URL(fileURLWithPath: item.trashedPath),
                    to: destination
                )
                restored.append(item)
            } catch {
                failed.append(item)
            }
        }

        return RestoreResult(restored: restored, failed: failed)
    }

    private func removeEmptyBatches() {
        batches.removeAll { batch in
            batch.items.allSatisfy { !FileManager.default.fileExists(atPath: $0.trashedPath) }
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(batches)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            statusMessage = String(localized: "history.status.saveFailed",
                                   defaultValue: "Couldn’t save the history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            batches = try decoder.decode([DeletionBatch].self, from: data)
        } catch {
            batches = []
            statusMessage = String(localized: "history.status.loadFailed",
                                   defaultValue: "Couldn’t read the history: \(error.localizedDescription)")
        }
    }
}

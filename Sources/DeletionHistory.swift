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
    let title: String
    let tasks: [String]
    var items: [TrashedItem]

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }
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

    func record(title: String, tasks: [String], items: [TrashedItem]) {
        guard !items.isEmpty else { return }
        let batch = DeletionBatch(
            id: UUID(),
            createdAt: Date(),
            title: title,
            tasks: tasks,
            items: items
        )
        batches.insert(batch, at: 0)
        if batches.count > maxBatchCount {
            batches = Array(batches.prefix(maxBatchCount))
        }
        statusMessage = "已保存可恢复记录"
        save()
    }

    func restore(_ batch: DeletionBatch) async {
        guard hasFolderAccess, !isRestoring else { return }
        isRestoring = true
        statusMessage = "正在恢复…"

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
            statusMessage = "没有可恢复的项目；它们可能已从废纸篓移除"
        } else if result.failed.isEmpty {
            statusMessage = "已恢复 \(result.restored.count) 项"
        } else {
            statusMessage = "已恢复 \(result.restored.count) 项，\(result.failed.count) 项存在冲突或已丢失"
        }
        save()
    }

    func forget(_ batch: DeletionBatch) {
        batches.removeAll { $0.id == batch.id }
        statusMessage = "已移除历史记录；废纸篓中的文件未受影响"
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
            statusMessage = "历史记录保存失败：\(error.localizedDescription)"
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
            statusMessage = "历史记录读取失败：\(error.localizedDescription)"
        }
    }
}

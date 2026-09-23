import AppKit
import SwiftUI

struct InstalledApplication: Identifiable, Hashable {
    let path: String
    let name: String
    let bundleIdentifier: String
    let version: String
    let size: Int64
    let modified: Date

    var id: String { path }

    var isChromePWA: Bool {
        bundleIdentifier.lowercased().hasPrefix("com.google.chrome.app.")
    }

    var displayVersion: String? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return nil }
        return trimmed
    }

    var versionLabel: String {
        if isChromePWA { return "Chrome PWA" }
        guard let displayVersion else {
            return String(localized: "app.version.unknown", defaultValue: "v N/A")
        }
        return "v\(displayVersion)"
    }
}

// rawValue 是稳定标识，不是界面文案；显示走 `title`。
enum AppMatchConfidence: String, Hashable {
    case exact
    case likely

    var title: String {
        switch self {
        case .exact:
            return String(localized: "app.match.exact", defaultValue: "Exact match")
        case .likely:
            return String(localized: "app.match.likely", defaultValue: "Name match")
        }
    }
}

struct AppCleanupItem: Identifiable, Hashable {
    let path: String
    let title: String
    let location: String
    let size: Int64
    let reason: String
    let confidence: AppMatchConfidence
    let isApplication: Bool
    var isSelected: Bool

    var id: String { path }
}

enum AppScanner {
    private static let roots = ["/Applications", "~/Applications"]
    private static let relatedRoots = [
        "~/Library/Application Support",
        "~/Library/Application Scripts",
        "~/Library/Caches",
        "~/Library/Containers",
        "~/Library/Group Containers",
        "~/Library/HTTPStorages",
        "~/Library/LaunchAgents",
        "~/Library/Logs",
        "~/Library/Preferences",
        "~/Library/Preferences/ByHost",
        "~/Library/Saved Application State",
        "~/Library/WebKit",
    ]

    static func installedApplications() -> [InstalledApplication] {
        let fm = FileManager.default
        var found: [String: InstalledApplication] = [:]

        for rawRoot in roots {
            let root = (rawRoot as NSString).expandingTildeInPath
            guard let entries = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                if entry.pathExtension.lowercased() == "app" {
                    if let app = application(at: entry) { found[entry.path] = app }
                    continue
                }

                // Utilities、Setapp 等容器目录只下探一层，避免把 App 内部组件列为独立应用。
                guard entry.hasDirectoryPath,
                      let nested = try? fm.contentsOfDirectory(
                        at: entry,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                      ) else { continue }
                for child in nested where child.pathExtension.lowercased() == "app" {
                    if let app = application(at: child) { found[child.path] = app }
                }
            }
        }

        return found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func relatedFiles(for app: InstalledApplication) -> [AppCleanupItem] {
        let fm = FileManager.default
        var found: [String: AppCleanupItem] = [:]

        let appItem = AppCleanupItem(
            path: app.path,
            title: app.name + ".app",
            location: abbreviate((app.path as NSString).deletingLastPathComponent),
            size: FileCleaner.allocatedSize(atPath: app.path),
            reason: String(localized: "app.reason.itself", defaultValue: "The app itself"),
            confidence: .exact,
            isApplication: true,
            isSelected: true
        )
        found[app.path] = appItem

        for rawRoot in relatedRoots {
            let root = (rawRoot as NSString).expandingTildeInPath
            guard let entries = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: nil,
                options: []
            ) else { continue }

            for entry in entries {
                guard let match = association(
                    entryName: entry.lastPathComponent,
                    appName: app.name,
                    bundleIdentifier: app.bundleIdentifier
                ) else { continue }

                found[entry.path] = AppCleanupItem(
                    path: entry.path,
                    title: entry.lastPathComponent,
                    location: abbreviate(root),
                    size: FileCleaner.allocatedSize(atPath: entry.path),
                    reason: match.reason,
                    confidence: match.confidence,
                    isApplication: false,
                    isSelected: match.confidence == .exact
                )
            }
        }

        return found.values.sorted {
            if $0.isApplication != $1.isApplication { return $0.isApplication }
            if $0.confidence != $1.confidence { return $0.confidence == .exact }
            return $0.size > $1.size
        }
    }

    static func association(
        entryName: String,
        appName: String,
        bundleIdentifier: String
    ) -> (confidence: AppMatchConfidence, reason: String)? {
        let lowerEntry = entryName.lowercased()
        let stem = (entryName as NSString).deletingPathExtension.lowercased()
        let bundle = bundleIdentifier.lowercased()

        if !bundle.isEmpty {
            let exactBundle = lowerEntry == bundle
                || stem == bundle
                || lowerEntry == bundle + ".savedstate"
                || lowerEntry == bundle + ".plist"
            let scopedBundle = lowerEntry.hasPrefix(bundle + ".")
                || lowerEntry.hasPrefix("group." + bundle)
                || stem.hasSuffix("." + bundle)

            if exactBundle || scopedBundle {
                return (.exact, String(localized: "app.reason.bundleid",
                                       defaultValue: "Bundle ID: \(bundleIdentifier)"))
            }
        }

        let normalizedEntry = normalize((entryName as NSString).deletingPathExtension)
        let normalizedApp = normalize(appName)
        if normalizedApp.count >= 4, normalizedEntry == normalizedApp {
            return (.likely, String(localized: "app.reason.nameMatch",
                                    defaultValue: "The name matches the app, so it isn’t ticked by default"))
        }
        return nil
    }

    private static func application(at url: URL) -> InstalledApplication? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? fallbackName
        let version = ["CFBundleShortVersionString", "CFBundleVersion"]
            .compactMap { info[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? ""
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attrs?[.modificationDate] as? Date) ?? .distantPast

        return InstalledApplication(
            path: url.path,
            name: name,
            bundleIdentifier: bundle.bundleIdentifier ?? "",
            version: version,
            // Spotlight 通常已索引 App bundle 总大小；列表扫描不递归读取每个 bundle。
            size: (NSMetadataItem(url: url)?.value(forAttribute: "kMDItemFSSize") as? NSNumber)?.int64Value ?? 0,
            modified: modified
        )
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

@MainActor
final class AppCleanerViewModel: ObservableObject {
    @Published var apps: [InstalledApplication] = []
    @Published var query = ""
    @Published var isScanningApps = false
    @Published var hasScannedApps = false
    @Published var selectedApp: InstalledApplication?
    @Published var candidates: [AppCleanupItem] = []
    @Published var isScanningRelated = false
    @Published var isDeleting = false
    @Published var statusMessage = ""

    var filteredApps: [InstalledApplication] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(term)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(term)
        }
    }

    var selectedCount: Int { candidates.filter(\.isSelected).count }
    var selectedBytes: Int64 { candidates.filter(\.isSelected).reduce(0) { $0 + $1.size } }

    func scanApps() {
        guard !isScanningApps else { return }
        isScanningApps = true
        statusMessage = String(localized: "app.status.reading",
                               defaultValue: "Reading apps and their sizes…")
        Task.detached(priority: .utility) {
            let found = AppScanner.installedApplications()
            await MainActor.run {
                self.apps = found
                self.isScanningApps = false
                self.hasScannedApps = true
                self.statusMessage = String(localized: "app.status.found",
                                            defaultValue: "Found \(found.count) apps")
            }
        }
    }

    func inspect(_ app: InstalledApplication) {
        guard !isScanningRelated else { return }
        selectedApp = app
        candidates = []
        isScanningRelated = true
        statusMessage = String(localized: "app.status.matching",
                               defaultValue: "Matching the files related to \(app.name)…")
        Task.detached(priority: .utility) {
            let found = AppScanner.relatedFiles(for: app)
            await MainActor.run {
                self.candidates = found
                self.isScanningRelated = false
                self.statusMessage = String(localized: "app.status.related",
                                            defaultValue: "Found \(max(0, found.count - 1)) related items")
            }
        }
    }

    func toggle(_ id: String) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].isSelected.toggle()
    }

    func moveSelectedToTrash() async {
        guard !isDeleting, let app = selectedApp else { return }
        let targets = candidates.filter(\.isSelected)
        guard !targets.isEmpty else { return }
        isDeleting = true
        statusMessage = String(localized: "app.status.moving",
                               defaultValue: "Moving to the Trash…")

        let trashed = await Task.detached(priority: .userInitiated) {
            targets.compactMap { FileCleaner.moveToTrash($0.path) }
        }.value

        let movedPaths = Set(trashed.map(\.originalPath))
        candidates.removeAll { movedPaths.contains($0.path) }
        if movedPaths.contains(app.path) {
            apps.removeAll { $0.path == app.path }
        }

        DeletionHistoryStore.shared.record(
            title: String(localized: "history.batch.uninstall",
                          defaultValue: "Uninstall \(app.name)"),
            tasks: [String(localized: "history.task.appAndRelated",
                           defaultValue: "The app and its related files")],
            titleKey: DeletionBatch.uninstallKey,
            titleArgument: app.name,
            taskKeys: [DeletionBatch.taskAppKey],
            items: trashed
        )

        isDeleting = false
        let failed = targets.count - trashed.count
        statusMessage = failed == 0
            ? String(localized: "app.status.trashed",
                     defaultValue: "Moved \(trashed.count) items to the Trash")
            : String(localized: "app.status.trashedPartial",
                     defaultValue: "Moved \(trashed.count) items; \(failed) lacked permission or failed to move")
    }
}

import SwiftUI

// 一条「背景 App 活動」记录（登录项 / 背景任务 / 守护进程 / 代理…）
// 数据来自 `sfltool dumpbtm`（Background Task Management），只读展示。
struct BTMItem: Identifiable, Hashable {
    let uuid: String
    let name: String
    let developer: String
    let teamID: String
    let typeRaw: String       // 原始类型串，如 "app (0x2)"
    let dispositionRaw: String // 原始 disposition 串
    let location: String      // URL / Executable Path，缺失为 "—"
    let bundleID: String
    let identifier: String
    let lastUse: String
    let locationExists: Bool  // 解析时磁盘检查结果（后台线程）

    var id: String { uuid }

    var isEnabled: Bool { dispositionRaw.contains("enabled") && !dispositionRaw.contains("disabled") }

    // location 是真实文件系统路径（区别于 background tasks 的 "—" / 无路径）
    var hasPath: Bool { location.hasPrefix("/") }

    // 孤立记录：有路径但 backing app / plist 已不在磁盘 —— 真正的「死」项，清理才有意义
    var isOrphaned: Bool { hasPath && !locationExists }

    // 归一化类型（去掉 legacy 前缀与 0x 后缀）
    private var typeKey: String {
        var s = typeRaw
        if let paren = s.firstIndex(of: "(") { s = String(s[..<paren]) }
        return s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "legacy ", with: "")
    }

    var typeLabel: String {
        switch typeKey {
        case "app": return "应用程序"
        case "login item": return "登录项"
        case "agent": return "代理"
        case "daemon": return "守护进程"
        case "developer": return "开发者"
        case "background tasks": return "背景任务"
        case "quicklook": return "Quick Look"
        case "dock tile": return "Dock 磁贴"
        case "spotlight": return "Spotlight"
        default: return typeKey.isEmpty ? "其他" : typeKey
        }
    }

    var icon: String {
        switch typeKey {
        case "app": return "app.badge"
        case "login item": return "arrow.right.circle"
        case "agent": return "person.crop.circle.badge.clock"
        case "daemon": return "gearshape.2"
        case "developer": return "person.2"
        case "background tasks": return "clock.arrow.circlepath"
        case "quicklook": return "eye"
        case "dock tile": return "dock.rectangle"
        case "spotlight": return "magnifyingglass"
        default: return "puzzlepiece.extension"
        }
    }
}

enum BTM {
    // 运行 sfltool dumpbtm 并解析为结构化列表（无需 sudo，取当前用户视图）
    static func dump() -> [BTMItem] {
        var out = ""
        _ = Shell.run("/usr/bin/sfltool dumpbtm 2>/dev/null") { out += $0 }
        return parse(out)
    }

    static func parse(_ text: String) -> [BTMItem] {
        var items: [BTMItem] = []
        var fields: [String: String] = [:]

        func flush() {
            guard !fields.isEmpty, let uuid = fields["UUID"] else { fields = [:]; return }
            let url = fields["URL"] ?? ""
            let exec = fields["Executable Path"] ?? ""
            let loc = (url.isEmpty || url == "(null)") ? exec : url
            // 只对真实路径查磁盘；无路径项（background tasks 等）视为存在，不误标孤立
            let exists = loc.hasPrefix("/") ? FileManager.default.fileExists(atPath: loc) : true
            items.append(BTMItem(
                uuid: uuid,
                name: clean(fields["Name"]),
                developer: clean(fields["Developer Name"]),
                teamID: clean(fields["Team Identifier"]),
                typeRaw: fields["Type"] ?? "",
                dispositionRaw: fields["Disposition"] ?? "",
                location: loc.isEmpty ? "—" : loc,
                bundleID: clean(fields["Bundle Identifier"]),
                identifier: clean(fields["Identifier"]),
                lastUse: clean(fields["Last Use"]),
                locationExists: exists
            ))
            fields = [:]
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // 新记录起始：形如 "#12:"（冒号后无内容），区别于内嵌 "#1: xxx"
            if line.hasPrefix("#"), line.hasSuffix(":"),
               line.dropFirst().dropLast().allSatisfy(\.isNumber) {
                flush()
                continue
            }
            // "Records for UID …" 等分节 → 结束当前记录
            if line.hasPrefix("Records for UID") || line.hasPrefix("======") {
                flush()
                continue
            }
            // 字段行 "Key: value"，key 可含空格；跳过内嵌的 "#1: …"
            guard let r = line.range(of: ": "), !line.hasPrefix("#") else { continue }
            let key = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let val = String(line[r.upperBound...])
            // 只在 key 尚未出现时记录，避免内嵌块覆盖顶层字段
            if fields[key] == nil { fields[key] = val }
        }
        flush()

        // 孤立在最前（最该清理），再停用、再启用；同组按类型 + 名称
        return items.sorted {
            if $0.isOrphaned != $1.isOrphaned { return $0.isOrphaned && !$1.isOrphaned }
            if $0.isEnabled != $1.isEnabled { return !$0.isEnabled && $1.isEnabled }
            if $0.typeLabel != $1.typeLabel { return $0.typeLabel < $1.typeLabel }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func clean(_ s: String?) -> String {
        guard let s, s != "(null)" else { return "" }
        return s
    }
}

@MainActor
final class BTMViewModel: ObservableObject {
    @Published var items: [BTMItem] = []
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var query = ""
    @Published var orphanOnly = false

    var enabledCount: Int { items.filter(\.isEnabled).count }
    var orphanCount: Int { items.filter(\.isOrphaned).count }

    var filtered: [BTMItem] {
        var out = items
        if orphanOnly { out = out.filter(\.isOrphaned) }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return out }
        return out.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.developer.localizedCaseInsensitiveContains(q)
                || $0.bundleID.localizedCaseInsensitiveContains(q)
                || $0.location.localizedCaseInsensitiveContains(q)
        }
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .utility) {
            let found = BTM.dump()
            await MainActor.run {
                self.items = found
                self.isLoading = false
                self.hasLoaded = true
            }
        }
    }
}

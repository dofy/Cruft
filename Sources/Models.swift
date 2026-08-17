import Foundation

// 清理任务分类
enum CleanupCategory: String, CaseIterable, Identifiable {
    case update = "更新"
    case clean = "清理"
    var id: String { rawValue }
}

// 每一个可执行的清理/更新任务
enum CleanupKind: String, CaseIterable, Identifiable {
    case brewUpdate
    case masUpgrade
    case cocoapods
    case xcode
    case caches
    case logs
    case trash
    case brewCleanup
    case gemCleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brewUpdate: return "更新 Homebrew"
        case .masUpgrade: return "更新 App Store 应用"
        case .cocoapods: return "清理 CocoaPods 缓存"
        case .xcode: return "清理 Xcode"
        case .caches: return "清理系统缓存"
        case .logs: return "清理应用日志"
        case .trash: return "清空废纸篓"
        case .brewCleanup: return "清理 Homebrew"
        case .gemCleanup: return "清理 Ruby Gem"
        }
    }

    var subtitle: String {
        switch self {
        case .brewUpdate: return "brew update / upgrade / upgrade --cask --greedy"
        case .masUpgrade: return "mas upgrade"
        case .cocoapods: return "pod cache clean --all"
        case .xcode: return "DerivedData、Archives、旧 DeviceSupport、无效模拟器"
        case .caches: return "~/Library/Caches 内容"
        case .logs: return "~/Library/Logs 内容"
        case .trash: return "~/.Trash 内容"
        case .brewCleanup: return "brew cleanup"
        case .gemCleanup: return "gem cleanup"
        }
    }

    var icon: String {
        switch self {
        case .brewUpdate: return "arrow.triangle.2.circlepath"
        case .masUpgrade: return "arrow.down.app"
        case .cocoapods: return "shippingbox"
        case .xcode: return "hammer"
        case .caches: return "internaldrive"
        case .logs: return "doc.text"
        case .trash: return "trash"
        case .brewCleanup: return "cup.and.saucer"
        case .gemCleanup: return "diamond"
        }
    }

    var category: CleanupCategory {
        switch self {
        case .brewUpdate, .masUpgrade: return .update
        default: return .clean
        }
    }

    // 依赖的命令行工具，nil 表示纯文件操作无需外部工具
    var requiredTool: String? {
        switch self {
        case .brewUpdate, .brewCleanup: return "brew"
        case .masUpgrade: return "mas"
        case .cocoapods: return "pod"
        case .gemCleanup: return "gem"
        case .xcode: return "xcrun"
        case .caches, .logs, .trash: return nil
        }
    }

    // 详情：具体清理/执行的内容，每条 (目标, 说明)
    var details: [(target: String, note: String)] {
        switch self {
        case .brewUpdate:
            return [
                ("brew update", "更新 formula / cask 索引"),
                ("brew upgrade", "升级所有过时的 formula"),
                ("brew upgrade --cask --greedy", "升级所有 cask，含自带自动更新的应用"),
            ]
        case .masUpgrade:
            return [("mas upgrade", "升级所有已安装的 App Store 应用")]
        case .cocoapods:
            return [("pod cache clean --all", "删除 ~/Library/Caches/CocoaPods 全部 pod 缓存")]
        case .xcode:
            return [
                ("~/Library/Developer/Xcode/DerivedData/*", "编译中间产物与索引"),
                ("~/Library/Developer/Xcode/Archives/*", "打包归档 (.xcarchive)"),
                ("~/Library/Developer/Xcode/Products/*", "导出的产物"),
                ("xcrun simctl delete unavailable", "删除不可用 / 无效的模拟器"),
                ("~/Library/Developer/Xcode/iOS DeviceSupport/*", "旧真机调试符号，保留最新一个版本"),
            ]
        case .caches:
            return [("~/Library/Caches/*", "用户级应用缓存，App 会按需重建")]
        case .logs:
            return [("~/Library/Logs/*", "用户级应用日志 (系统级 /Library/Logs 需管理员权限，不处理)")]
        case .trash:
            return [("~/.Trash/*", "废纸篓内容，删除后无法恢复")]
        case .brewCleanup:
            return [("brew cleanup", "删除旧版本、下载缓存、失效符号链接")]
        case .gemCleanup:
            return [("gem cleanup", "删除各 gem 的旧版本，仅保留最新")]
        }
    }

    // 可估算体积的目录（工具类命令无法预估，返回空）
    var measurablePaths: [String] {
        switch self {
        case .cocoapods:
            return ["~/Library/Caches/CocoaPods"]
        case .xcode:
            let d = "~/Library/Developer/Xcode"
            return ["\(d)/DerivedData", "\(d)/Archives", "\(d)/Products", "\(d)/iOS DeviceSupport"]
        case .caches:
            return ["~/Library/Caches"]
        case .logs:
            return ["~/Library/Logs"]
        case .trash:
            return ["~/.Trash"]
        case .brewUpdate, .masUpgrade, .brewCleanup, .gemCleanup:
            return []
        }
    }

    var isMeasurable: Bool { !measurablePaths.isEmpty }

    // 默认勾选：清理项默认开，网络更新项默认关
    var defaultEnabled: Bool {
        switch self {
        case .brewUpdate, .masUpgrade: return false
        default: return true
        }
    }
}

struct CleanupItem: Identifiable {
    let kind: CleanupKind
    var isEnabled: Bool
    var isAvailable: Bool
    var id: String { kind.id }
}

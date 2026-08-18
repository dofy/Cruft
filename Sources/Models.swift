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
    // 开发生态缓存
    case npm
    case pnpm
    case yarn
    case cargo
    case go
    case gradle
    case maven
    case pip
    case swiftpm
    // 系统 & 工具
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
        case .npm: return "清理 npm 缓存"
        case .pnpm: return "清理 pnpm store"
        case .yarn: return "清理 Yarn 缓存"
        case .cargo: return "清理 Cargo 缓存"
        case .go: return "清理 Go 缓存"
        case .gradle: return "清理 Gradle 缓存"
        case .maven: return "清理 Maven 仓库"
        case .pip: return "清理 pip 缓存"
        case .swiftpm: return "清理 SwiftPM 缓存"
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
        case .npm: return "~/.npm/_cacache"
        case .pnpm: return "pnpm store prune"
        case .yarn: return "~/Library/Caches/Yarn"
        case .cargo: return "~/.cargo/registry 缓存与源码"
        case .go: return "go clean -cache -modcache"
        case .gradle: return "~/.gradle/caches"
        case .maven: return "~/.m2/repository（下次构建会重新下载）"
        case .pip: return "~/Library/Caches/pip"
        case .swiftpm: return "~/Library/Caches/org.swift.swiftpm"
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
        case .npm: return "cube.box"
        case .pnpm: return "cube.box.fill"
        case .yarn: return "cube.transparent"
        case .cargo: return "shippingbox.circle"
        case .go: return "g.circle"
        case .gradle: return "hammer.circle"
        case .maven: return "m.circle"
        case .pip: return "p.circle"
        case .swiftpm: return "swift"
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
        case .pnpm: return "pnpm"
        case .go: return "go"
        case .npm, .yarn, .cargo, .gradle, .maven, .pip, .swiftpm: return nil
        case .caches, .logs, .trash: return nil
        }
    }

    // 无外部工具、但按目录是否存在判断是否显示；空表示无条件显示
    var detectionPaths: [String] {
        switch self {
        case .npm: return ["~/.npm"]
        case .yarn: return ["~/Library/Caches/Yarn"]
        case .cargo: return ["~/.cargo"]
        case .gradle: return ["~/.gradle"]
        case .maven: return ["~/.m2"]
        case .pip: return ["~/Library/Caches/pip"]
        case .swiftpm: return ["~/Library/Caches/org.swift.swiftpm"]
        default: return []
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
        case .npm:
            return [("~/.npm/_cacache/*", "npm 下载缓存，下次安装会重建")]
        case .pnpm:
            return [("pnpm store prune", "删除 pnpm store 中无项目引用的包")]
        case .yarn:
            return [("~/Library/Caches/Yarn/*", "Yarn (classic) 全局缓存")]
        case .cargo:
            return [
                ("~/.cargo/registry/cache/*", "crate 下载压缩包"),
                ("~/.cargo/registry/src/*", "解压的 crate 源码"),
            ]
        case .go:
            return [("go clean -cache -modcache", "构建缓存 + 模块缓存（模块缓存只读，须经 go 删除）")]
        case .gradle:
            return [("~/.gradle/caches/*", "Gradle 依赖与构建缓存")]
        case .maven:
            return [("~/.m2/repository/*", "Maven 本地仓库；清空后下次构建会重新下载全部依赖")]
        case .pip:
            return [("~/Library/Caches/pip/*", "pip wheel / http 缓存")]
        case .swiftpm:
            return [("~/Library/Caches/org.swift.swiftpm/*", "SwiftPM 依赖缓存")]
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
        case .npm:
            return ["~/.npm/_cacache"]
        case .yarn:
            return ["~/Library/Caches/Yarn"]
        case .cargo:
            return ["~/.cargo/registry/cache", "~/.cargo/registry/src"]
        case .gradle:
            return ["~/.gradle/caches"]
        case .maven:
            return ["~/.m2/repository"]
        case .pip:
            return ["~/Library/Caches/pip"]
        case .swiftpm:
            return ["~/Library/Caches/org.swift.swiftpm"]
        case .caches:
            return ["~/Library/Caches"]
        case .logs:
            return ["~/Library/Logs"]
        case .trash:
            return ["~/.Trash"]
        case .brewUpdate, .masUpgrade, .brewCleanup, .gemCleanup, .pnpm, .go:
            return []
        }
    }

    var isMeasurable: Bool { !measurablePaths.isEmpty }

    // 默认勾选：清理项默认开；网络更新项与代价高昂的重建项默认关
    var defaultEnabled: Bool {
        switch self {
        case .brewUpdate, .masUpgrade: return false
        case .maven: return false // 清空后全量重新下载，成本高，默认不选
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

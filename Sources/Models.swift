import Foundation

// 清理任务分类
//
// rawValue 同时当 Identifiable.id 用，所以它必须是稳定的 ASCII 标识，不能是界面文案——
// 文案一翻译，id 就跟着语言变。显示走 `title`。
enum CleanupCategory: String, CaseIterable, Identifiable {
    case update
    case clean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .update: return String(localized: "category.update", defaultValue: "Update")
        case .clean: return String(localized: "category.clean", defaultValue: "Clean")
        }
    }
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
    // Docker
    case dockerImages
    case dockerBuildCache
    case dockerContainers
    case dockerVolumes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brewUpdate:
            return String(localized: "kind.brewUpdate.title", defaultValue: "Update Homebrew")
        case .masUpgrade:
            return String(localized: "kind.masUpgrade.title", defaultValue: "Update App Store apps")
        case .cocoapods:
            return String(localized: "kind.cocoapods.title", defaultValue: "Clean the CocoaPods cache")
        case .xcode:
            return String(localized: "kind.xcode.title", defaultValue: "Clean up Xcode")
        case .npm:
            return String(localized: "kind.npm.title", defaultValue: "Clean the npm cache")
        case .pnpm:
            return String(localized: "kind.pnpm.title", defaultValue: "Clean the pnpm store")
        case .yarn:
            return String(localized: "kind.yarn.title", defaultValue: "Clean the Yarn cache")
        case .cargo:
            return String(localized: "kind.cargo.title", defaultValue: "Clean the Cargo cache")
        case .go:
            return String(localized: "kind.go.title", defaultValue: "Clean the Go cache")
        case .gradle:
            return String(localized: "kind.gradle.title", defaultValue: "Clean the Gradle cache")
        case .maven:
            return String(localized: "kind.maven.title", defaultValue: "Clean the Maven repository")
        case .pip:
            return String(localized: "kind.pip.title", defaultValue: "Clean the pip cache")
        case .swiftpm:
            return String(localized: "kind.swiftpm.title", defaultValue: "Clean the SwiftPM cache")
        case .caches:
            return String(localized: "kind.caches.title", defaultValue: "Clean system caches")
        case .logs:
            return String(localized: "kind.logs.title", defaultValue: "Clean app logs")
        case .trash:
            return String(localized: "kind.trash.title", defaultValue: "Empty the Trash")
        case .brewCleanup:
            return String(localized: "kind.brewCleanup.title", defaultValue: "Clean up Homebrew")
        case .gemCleanup:
            return String(localized: "kind.gemCleanup.title", defaultValue: "Clean up Ruby gems")
        case .dockerImages:
            return String(localized: "kind.dockerImages.title", defaultValue: "Clean dangling Docker images")
        case .dockerBuildCache:
            return String(localized: "kind.dockerBuildCache.title", defaultValue: "Clean the Docker build cache")
        case .dockerContainers:
            return String(localized: "kind.dockerContainers.title", defaultValue: "Clean stopped Docker containers")
        case .dockerVolumes:
            return String(localized: "kind.dockerVolumes.title", defaultValue: "Clean unmounted Docker volumes")
        }
    }

    // 副标题：要么是原样的命令 / 路径（不翻译），要么是一句需要本地化的说明。
    // 不要把命令和说明拼在一个本地化字符串里——`brew update` 这种词条进了目录只会被误译。
    var subtitle: String {
        switch self {
        case .brewUpdate: return "brew update / upgrade / upgrade --cask --greedy"
        case .masUpgrade: return "mas upgrade"
        case .cocoapods: return "pod cache clean --all"
        case .xcode:
            return String(localized: "kind.xcode.subtitle",
                          defaultValue: "DerivedData, Archives, old DeviceSupport, unavailable simulators")
        case .npm: return "~/.npm/_cacache"
        case .pnpm: return "pnpm store prune"
        case .yarn: return "~/Library/Caches/Yarn"
        case .cargo:
            return String(localized: "kind.cargo.subtitle",
                          defaultValue: "~/.cargo/registry cache and sources")
        case .go: return "go clean -cache -modcache"
        case .gradle: return "~/.gradle/caches"
        case .maven:
            return String(localized: "kind.maven.subtitle",
                          defaultValue: "~/.m2/repository (the next build downloads it again)")
        case .pip: return "~/Library/Caches/pip"
        case .swiftpm: return "~/Library/Caches/org.swift.swiftpm"
        case .caches:
            return String(localized: "kind.caches.subtitle",
                          defaultValue: "The contents of ~/Library/Caches")
        case .logs:
            return String(localized: "kind.logs.subtitle",
                          defaultValue: "The contents of ~/Library/Logs")
        case .trash:
            return String(localized: "kind.trash.subtitle",
                          defaultValue: "The contents of ~/.Trash")
        case .brewCleanup: return "brew cleanup"
        case .gemCleanup: return "gem cleanup"
        case .dockerImages:
            return String(localized: "kind.dockerImages.subtitle",
                          defaultValue: "docker image prune -f (only <none>:<none> dangling images)")
        case .dockerBuildCache:
            return String(localized: "kind.dockerBuildCache.subtitle",
                          defaultValue: "docker builder prune -af (rebuildable)")
        case .dockerContainers:
            return String(localized: "kind.dockerContainers.subtitle",
                          defaultValue: "docker container prune -f (stopped containers)")
        case .dockerVolumes:
            return String(localized: "kind.dockerVolumes.subtitle",
                          defaultValue: "docker volume prune -f (volumes no container references; the data can’t be recovered)")
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
        case .dockerImages: return "shippingbox.and.arrow.backward"
        case .dockerBuildCache: return "hammer.fill"
        case .dockerContainers: return "square.stack.3d.up"
        case .dockerVolumes: return "externaldrive"
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
        case .dockerImages, .dockerBuildCache, .dockerContainers, .dockerVolumes: return "docker"
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

    // 详情：具体清理/执行的内容，每条 (目标, 说明)。
    // `target` 是原样的命令 / 路径，不进本地化目录；只有 `note` 需要翻译。
    var details: [(target: String, note: String)] {
        switch self {
        case .brewUpdate:
            return [
                ("brew update", String(localized: "detail.brewUpdate.index",
                                       defaultValue: "Refresh the formula / cask index")),
                ("brew upgrade", String(localized: "detail.brewUpdate.upgrade",
                                        defaultValue: "Upgrade every outdated formula")),
                ("brew upgrade --cask --greedy",
                 String(localized: "detail.brewUpdate.cask",
                        defaultValue: "Upgrade every cask, including apps that update themselves")),
            ]
        case .masUpgrade:
            return [("mas upgrade", String(localized: "detail.masUpgrade",
                                           defaultValue: "Upgrade every installed App Store app"))]
        case .cocoapods:
            return [("pod cache clean --all",
                     String(localized: "detail.cocoapods",
                            defaultValue: "Delete every pod cache under ~/Library/Caches/CocoaPods"))]
        case .xcode:
            return [
                ("~/Library/Developer/Xcode/DerivedData/*",
                 String(localized: "detail.xcode.derivedData",
                        defaultValue: "Build intermediates and indexes")),
                ("~/Library/Developer/Xcode/Archives/*",
                 String(localized: "detail.xcode.archives",
                        defaultValue: "Packaged archives (.xcarchive)")),
                ("~/Library/Developer/Xcode/Products/*",
                 String(localized: "detail.xcode.products", defaultValue: "Exported products")),
                ("xcrun simctl delete unavailable",
                 String(localized: "detail.xcode.simulators",
                        defaultValue: "Delete unavailable simulators")),
                ("~/Library/Developer/Xcode/iOS DeviceSupport/*",
                 String(localized: "detail.xcode.deviceSupport",
                        defaultValue: "Old on-device debug symbols, keeping the newest version")),
            ]
        case .npm:
            return [("~/.npm/_cacache/*",
                     String(localized: "detail.npm",
                            defaultValue: "The npm download cache, rebuilt on the next install"))]
        case .pnpm:
            return [("pnpm store prune",
                     String(localized: "detail.pnpm",
                            defaultValue: "Delete packages in the pnpm store that no project references"))]
        case .yarn:
            return [("~/Library/Caches/Yarn/*",
                     String(localized: "detail.yarn",
                            defaultValue: "The Yarn (classic) global cache"))]
        case .cargo:
            return [
                ("~/.cargo/registry/cache/*",
                 String(localized: "detail.cargo.cache", defaultValue: "Downloaded crate archives")),
                ("~/.cargo/registry/src/*",
                 String(localized: "detail.cargo.src", defaultValue: "Unpacked crate sources")),
            ]
        case .go:
            return [("go clean -cache -modcache",
                     String(localized: "detail.go",
                            defaultValue: "The build cache plus the module cache (the module cache is read-only, so go has to delete it)"))]
        case .gradle:
            return [("~/.gradle/caches/*",
                     String(localized: "detail.gradle",
                            defaultValue: "Gradle dependency and build caches"))]
        case .maven:
            return [("~/.m2/repository/*",
                     String(localized: "detail.maven",
                            defaultValue: "The local Maven repository; once emptied, the next build downloads every dependency again"))]
        case .pip:
            return [("~/Library/Caches/pip/*",
                     String(localized: "detail.pip", defaultValue: "The pip wheel / HTTP cache"))]
        case .swiftpm:
            return [("~/Library/Caches/org.swift.swiftpm/*",
                     String(localized: "detail.swiftpm", defaultValue: "The SwiftPM dependency cache"))]
        case .caches:
            return [("~/Library/Caches/*",
                     String(localized: "detail.caches",
                            defaultValue: "User-level app caches, which apps rebuild as they need them"))]
        case .logs:
            return [("~/Library/Logs/*",
                     String(localized: "detail.logs",
                            defaultValue: "User-level app logs (system-level /Library/Logs needs admin rights and is left alone)"))]
        case .trash:
            return [("~/.Trash/*",
                     String(localized: "detail.trash",
                            defaultValue: "The contents of the Trash, unrecoverable once deleted"))]
        case .brewCleanup:
            return [("brew cleanup",
                     String(localized: "detail.brewCleanup",
                            defaultValue: "Delete old versions, download caches and broken symlinks"))]
        case .gemCleanup:
            return [("gem cleanup",
                     String(localized: "detail.gemCleanup",
                            defaultValue: "Delete each gem’s old versions, keeping only the newest"))]
        case .dockerImages:
            return [("docker image prune -f",
                     String(localized: "detail.dockerImages",
                            defaultValue: "Delete untagged <none>:<none> dangling images; images a container references are kept"))]
        case .dockerBuildCache:
            return [("docker builder prune -af",
                     String(localized: "detail.dockerBuildCache",
                            defaultValue: "Empty the BuildKit build cache; the next build rebuilds it and runs slower"))]
        case .dockerContainers:
            return [("docker container prune -f",
                     String(localized: "detail.dockerContainers",
                            defaultValue: "Delete stopped containers; running containers are untouched"))]
        case .dockerVolumes:
            return [("docker volume prune -f",
                     String(localized: "detail.dockerVolumes",
                            defaultValue: "Delete volumes no container references; the data inside can’t be recovered, so this is off by default"))]
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
        case .dockerImages, .dockerBuildCache, .dockerContainers, .dockerVolumes:
            // docker 空间由 daemon 统计（docker system df），非文件系统目录
            return []
        }
    }

    var isMeasurable: Bool { !measurablePaths.isEmpty }

    // 默认勾选：清理项默认开；网络更新项与代价高昂的重建项默认关
    var defaultEnabled: Bool {
        switch self {
        case .brewUpdate, .masUpgrade: return false
        case .maven: return false // 清空后全量重新下载，成本高，默认不选
        case .dockerVolumes: return false // 卷内数据不可恢复，默认不选
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

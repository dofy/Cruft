import Foundation

// 把每个 CleanupKind 映射到具体动作。在后台线程执行。
enum CleanerEngine {
    static func execute(_ kind: CleanupKind, log: @escaping @Sendable (String) -> Void) {
        switch kind {
        case .brewUpdate:
            Shell.run("brew update && brew upgrade && brew upgrade --cask --greedy", log: log)

        case .masUpgrade:
            Shell.run("mas upgrade", log: log)

        case .cocoapods:
            Shell.run("pod cache clean --all", log: log)

        case .xcode:
            let dev = "\(NSHomeDirectory())/Library/Developer/Xcode"
            FileCleaner.removeContents(of: "\(dev)/DerivedData", log: log)
            FileCleaner.removeContents(of: "\(dev)/Archives", log: log)
            FileCleaner.removeContents(of: "\(dev)/Products", log: log)
            log("删除无效模拟器…\n")
            Shell.run("xcrun simctl delete unavailable", log: log)
            pruneDeviceSupport(base: "\(dev)/iOS DeviceSupport", log: log)

        case .npm:
            FileCleaner.removeContents(of: "~/.npm/_cacache", log: log)

        case .pnpm:
            Shell.run("pnpm store prune", log: log)

        case .yarn:
            FileCleaner.removeContents(of: "~/Library/Caches/Yarn", log: log)

        case .cargo:
            FileCleaner.removeContents(of: "~/.cargo/registry/cache", log: log)
            FileCleaner.removeContents(of: "~/.cargo/registry/src", log: log)

        case .go:
            // 模块缓存为只读文件，须经 go 自身删除，不能直接 rm
            Shell.run("go clean -cache -modcache", log: log)

        case .gradle:
            FileCleaner.removeContents(of: "~/.gradle/caches", log: log)

        case .maven:
            FileCleaner.removeContents(of: "~/.m2/repository", log: log)

        case .pip:
            FileCleaner.removeContents(of: "~/Library/Caches/pip", log: log)

        case .swiftpm:
            FileCleaner.removeContents(of: "~/Library/Caches/org.swift.swiftpm", log: log)

        case .caches:
            FileCleaner.removeContents(of: "~/Library/Caches", log: log)

        case .logs:
            // 仅清理用户级日志；/Library/Logs 需管理员权限，故跳过
            FileCleaner.removeContents(of: "~/Library/Logs", log: log)

        case .trash:
            FileCleaner.removeContents(of: "~/.Trash", log: log)

        case .brewCleanup:
            Shell.run("brew cleanup", log: log)

        case .gemCleanup:
            Shell.run("gem cleanup", log: log)
        }
    }

    // 保留最新版本的 iOS DeviceSupport，删除其余旧版本
    private static func pruneDeviceSupport(base: String, log: @Sendable (String) -> Void) {
        let fm = FileManager.default
        guard let versions = try? fm.contentsOfDirectory(atPath: base), !versions.isEmpty else { return }
        // 版本号语义排序，最后一个为最新
        let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        guard let keep = sorted.last else { return }
        log("DeviceSupport 保留最新: \(keep)\n")
        for v in sorted where v != keep {
            let full = (base as NSString).appendingPathComponent(v)
            do { try fm.removeItem(atPath: full); log("已删除 \(v)\n") }
            catch { log("跳过 \(v): \(error.localizedDescription)\n") }
        }
    }
}

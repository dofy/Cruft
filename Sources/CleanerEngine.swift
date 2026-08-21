import Foundation

struct CleanupExecutionResult {
    var trashedItems: [TrashedItem] = []
}

// 把每个 CleanupKind 映射到具体动作。在后台线程执行。
enum CleanerEngine {
    static func execute(_ kind: CleanupKind, log: @escaping @Sendable (String) -> Void) -> CleanupExecutionResult {
        var result = CleanupExecutionResult()
        switch kind {
        case .brewUpdate:
            Shell.run("brew update && brew upgrade && brew upgrade --cask --greedy", log: log)

        case .masUpgrade:
            Shell.run("mas upgrade", log: log)

        case .cocoapods:
            Shell.run("pod cache clean --all", log: log)

        case .xcode:
            let dev = "\(NSHomeDirectory())/Library/Developer/Xcode"
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "\(dev)/DerivedData", log: log)
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "\(dev)/Archives", log: log)
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "\(dev)/Products", log: log)
            log("删除无效模拟器…\n")
            Shell.run("xcrun simctl delete unavailable", log: log)
            result.trashedItems += pruneDeviceSupport(base: "\(dev)/iOS DeviceSupport", log: log)

        case .npm:
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/.npm/_cacache", log: log)

        case .pnpm:
            Shell.run("pnpm store prune", log: log)

        case .yarn:
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/Library/Caches/Yarn", log: log)

        case .cargo:
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/.cargo/registry/cache", log: log)
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/.cargo/registry/src", log: log)

        case .go:
            // 模块缓存为只读文件，须经 go 自身删除，不能直接 rm
            Shell.run("go clean -cache -modcache", log: log)

        case .gradle:
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/.gradle/caches", log: log)

        case .maven:
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/.m2/repository", log: log)

        case .pip:
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/Library/Caches/pip", log: log)

        case .swiftpm:
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/Library/Caches/org.swift.swiftpm", log: log)

        case .caches:
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/Library/Caches", log: log)

        case .logs:
            // 仅清理用户级日志；/Library/Logs 需管理员权限，故跳过
            result.trashedItems += FileCleaner.moveContentsToTrash(of: "~/Library/Logs", log: log)

        case .trash:
            FileCleaner.removeContents(of: "~/.Trash", log: log)

        case .brewCleanup:
            Shell.run("brew cleanup", log: log)

        case .gemCleanup:
            Shell.run("gem cleanup", log: log)

        case .dockerImages:
            // 仅悬挂 image（<none>:<none>）。用 -a 会连未运行但可能有用的 image 一并删掉，
            // 对开发者不友好，故不加 -a。
            Shell.run("docker image prune -f", log: log)

        case .dockerBuildCache:
            Shell.run("docker builder prune -af", log: log)

        case .dockerContainers:
            Shell.run("docker container prune -f", log: log)

        case .dockerVolumes:
            Shell.run("docker volume prune -f", log: log)
        }
        return result
    }

    // 保留最新版本的 iOS DeviceSupport，删除其余旧版本
    private static func pruneDeviceSupport(base: String, log: @Sendable (String) -> Void) -> [TrashedItem] {
        let fm = FileManager.default
        guard let versions = try? fm.contentsOfDirectory(atPath: base), !versions.isEmpty else { return [] }
        // 版本号语义排序，最后一个为最新
        let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        guard let keep = sorted.last else { return [] }
        log("DeviceSupport 保留最新: \(keep)\n")
        var trashed: [TrashedItem] = []
        for v in sorted where v != keep {
            let full = (base as NSString).appendingPathComponent(v)
            if let record = FileCleaner.moveToTrash(full) {
                trashed.append(record)
                log("已移到废纸篓 \(v)\n")
            } else {
                log("跳过 \(v)：无法移到废纸篓\n")
            }
        }
        return trashed
    }
}

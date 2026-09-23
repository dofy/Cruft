import Foundation

// 执行外部命令 + 文件系统操作的底层封装
enum Shell {
    // 显式 PATH：GUI 进程默认不含 Homebrew 路径
    static let searchPath = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ].joined(separator: ":")

    static func toolExists(_ name: String) -> Bool {
        for dir in searchPath.split(separator: ":") {
            if FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)") { return true }
        }
        return false
    }

    // 阻塞执行；输出逐块回调。必须在后台线程调用。
    @discardableResult
    static func run(_ command: String, log: @escaping @Sendable (String) -> Void) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            log(String(localized: "log.launchFailed",
                       defaultValue: "Couldn’t launch: \(error.localizedDescription)\n"))
            return -1
        }

        // 同步读取，避免 readabilityHandler 的并发/生命周期问题
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            if let s = String(data: data, encoding: .utf8) { log(s) }
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

// 纯 Swift 文件清理，比 rm -rf 更安全可控
enum FileCleaner {
    // 删除目录内容但保留目录本身
    static func removeContents(of directory: String, log: @Sendable (String) -> Void) {
        let fm = FileManager.default
        let path = (directory as NSString).expandingTildeInPath
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
            log(String(localized: "log.skipPath",
                       defaultValue: "Skipped (missing or no permission): \(path)\n"))
            return
        }
        for item in items {
            let full = (path as NSString).appendingPathComponent(item)
            do {
                try fm.removeItem(atPath: full)
                log(String(localized: "log.deleted", defaultValue: "Deleted \(item)\n"))
            } catch {
                log(String(localized: "log.skipItemError",
                           defaultValue: "Skipped \(item): \(error.localizedDescription)\n"))
            }
        }
    }

    // 将目录的直接子项逐个移到废纸篓，保留目录本身，并返回可恢复映射。
    static func moveContentsToTrash(of directory: String, log: @Sendable (String) -> Void) -> [TrashedItem] {
        let fm = FileManager.default
        let path = (directory as NSString).expandingTildeInPath
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
            log(String(localized: "log.skipPath",
                       defaultValue: "Skipped (missing or no permission): \(path)\n"))
            return []
        }

        var trashed: [TrashedItem] = []
        for item in items {
            let full = (path as NSString).appendingPathComponent(item)
            if let record = moveToTrash(full) {
                trashed.append(record)
                log(String(localized: "log.trashed", defaultValue: "Moved \(item) to the Trash\n"))
            } else {
                log(String(localized: "log.trashFailed",
                           defaultValue: "Skipped \(item): couldn’t move it to the Trash\n"))
            }
        }
        return trashed
    }

    // 递归统计多个目录的占用字节（用于估算）
    static func size(of paths: [String]) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for p in paths {
            let path = (p as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: path)
            guard let en = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                options: [],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let file as URL in en {
                let v = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
                if v?.isRegularFile == true {
                    total += Int64(v?.totalFileAllocatedSize ?? 0)
                }
            }
        }
        return total
    }

    // 移到废纸篓并记录系统生成的实际目标路径，供历史恢复使用。
    static func moveToTrash(_ path: String) -> TrashedItem? {
        let expanded = (path as NSString).expandingTildeInPath
        guard isSafeTrashTarget(expanded) else { return nil }

        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let bytes = allocatedSize(atPath: url.path)
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            guard let destination = resultingURL as URL? else { return nil }
            return TrashedItem(
                originalPath: url.path,
                trashedPath: destination.path,
                size: bytes
            )
        } catch {
            return nil
        }
    }

    // 用户目录所在卷的可用字节
    static func freeBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    static func totalBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
    }

    static func allocatedSize(atPath path: String) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        if isDirectory.boolValue {
            return size(of: [path])
        }

        let values = try? URL(fileURLWithPath: path).resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        )
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
    }

    static func isSafeTrashTarget(_ path: String) -> Bool {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path

        let blocked = [
            "/", "/Applications", "/Library", "/System", "/Users", home,
            "\(home)/Library", "\(home)/Applications", "\(home)/Desktop",
            "\(home)/Documents", "\(home)/Downloads",
        ]
        guard !blocked.contains(target) else { return false }

        if target.hasPrefix(home + "/") { return true }

        // 应用清理仅允许移动 /Applications 下的完整 .app bundle。
        return target.hasPrefix("/Applications/") && target.hasSuffix(".app")
    }
}

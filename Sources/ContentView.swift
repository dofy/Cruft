import AppKit
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case tasks
    case projects
    case installers
    case applications
    case background
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: return "清理"
        case .projects: return "项目产物"
        case .installers: return "安装包"
        case .applications: return "应用清理"
        case .background: return "背景 App"
        case .history: return "恢复历史"
        }
    }

    var icon: String {
        switch self {
        case .tasks: return "sparkles"
        case .projects: return "shippingbox"
        case .installers: return "opticaldiscdrive"
        case .applications: return "app.badge.checkmark"
        case .background: return "bolt.badge.clock"
        case .history: return "clock.arrow.circlepath"
        }
    }

    static let cleanup: [Pane] = [.tasks, .projects, .installers, .applications]
    static let system: [Pane] = [.background, .history]
}

struct ContentView: View {
    @StateObject private var folderAccess = FolderAccessManager.shared
    @StateObject private var cleanerVM = CleanerViewModel()
    @StateObject private var projectsVM = ScanViewModel(mode: .projects)
    @StateObject private var installersVM = ScanViewModel(mode: .installers)
    @StateObject private var appsVM = AppCleanerViewModel()
    @StateObject private var btmVM = BTMViewModel()
    @StateObject private var history = DeletionHistoryStore.shared
    @State private var pane: Pane? = .tasks
    @State private var showFolderAccess = false
    @FocusState private var sidebarFocused: Bool

    private let projectRoots = ["~/Works", "~/Projects", "~/Developer"]

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 245)
        } detail: {
            ZStack {
                CruftTheme.canvas
                    .ignoresSafeArea()
                detail
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !folderAccess.hasFullDiskAccess {
                    Divider()
                    FolderAccessBanner(
                        isChecking: folderAccess.isChecking,
                        showDetails: { showFolderAccess = true }
                    )
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(CruftTheme.amber)
        .sheet(isPresented: $showFolderAccess) {
            FolderAccessSheet(manager: folderAccess)
        }
        .onAppear {
            folderAccess.check()
            syncFolderAccess(folderAccess.hasFullDiskAccess)
            DispatchQueue.main.async { sidebarFocused = true }
        }
        .onChange(of: folderAccess.hasFullDiskAccess) { _, allowed in
            syncFolderAccess(allowed)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            folderAccess.check()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                // The real app icon rather than a hand-built tile: a gradient
                // rectangle plus an SF Symbol drifted away from the icon as
                // soon as the icon was redesigned (flat colour, heavier glyph).
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Cruft")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("DEV HYGIENE")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            List(selection: $pane) {
                Section("空间维护") {
                    ForEach(Pane.cleanup) { item in
                        sidebarLabel(item)
                            .tag(item)
                    }
                }

                Section("系统") {
                    ForEach(Pane.system) { item in
                        HStack {
                            Image(systemName: item.icon)
                                .foregroundStyle(pane == item ? CruftTheme.coral : Color.secondary)
                                .frame(width: 20)
                            Text(item.title)
                            if item == .history, !history.batches.isEmpty {
                                Spacer()
                                Text("\(history.batches.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .focused($sidebarFocused)

            Divider()
            StorageGauge(free: cleanerVM.freeSpace, total: cleanerVM.totalSpace)
                .padding(16)
        }
        .background(.ultraThinMaterial)
    }

    private func sidebarLabel(_ item: Pane) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .foregroundStyle(pane == item ? CruftTheme.coral : Color.secondary)
                .frame(width: 20)
            Text(item.title)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch pane ?? .tasks {
        case .tasks:
            CleanPane(
                vm: cleanerVM,
                hasFolderAccess: folderAccess.hasFullDiskAccess,
                requestFolderAccess: { showFolderAccess = true }
            )
        case .projects:
            ScanPane(
                vm: projectsVM,
                title: "项目产物",
                subtitle: "找出长期未使用的依赖和构建目录",
                icon: "shippingbox",
                emptyHint: "未发现项目产物目录",
                roots: projectRoots,
                hasFolderAccess: folderAccess.hasFullDiskAccess,
                requestFolderAccess: { showFolderAccess = true }
            )
        case .installers:
            ScanPane(
                vm: installersVM,
                title: "安装包",
                subtitle: "整理下载目录和桌面上的 DMG、PKG",
                icon: "opticaldiscdrive",
                emptyHint: "未发现 .dmg / .pkg 安装包",
                roots: projectRoots,
                hasFolderAccess: folderAccess.hasFullDiskAccess,
                requestFolderAccess: { showFolderAccess = true }
            )
        case .applications:
            ApplicationsPane(
                vm: appsVM,
                hasFolderAccess: folderAccess.hasFullDiskAccess,
                requestFolderAccess: { showFolderAccess = true }
            )
        case .background:
            BackgroundPane(
                vm: btmVM,
                hasFolderAccess: folderAccess.hasFullDiskAccess,
                requestFolderAccess: { showFolderAccess = true }
            )
        case .history:
            HistoryPane(
                store: history,
                hasFolderAccess: folderAccess.hasFullDiskAccess,
                requestFolderAccess: { showFolderAccess = true }
            )
        }
    }

    private func syncFolderAccess(_ allowed: Bool) {
        cleanerVM.setFolderAccess(allowed)
        history.setFolderAccess(allowed)
    }
}

#Preview {
    ContentView()
        .frame(width: 980, height: 720)
}

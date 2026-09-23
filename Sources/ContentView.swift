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
        case .tasks:
            return String(localized: "clean.title", defaultValue: "Clean")
        case .projects:
            return String(localized: "projects.title", defaultValue: "Build products")
        case .installers:
            return String(localized: "installers.title", defaultValue: "Installers")
        case .applications:
            return String(localized: "apps.title", defaultValue: "App cleanup")
        case .background:
            return String(localized: "btm.title", defaultValue: "Background apps")
        case .history:
            return String(localized: "history.title", defaultValue: "Restore history")
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

/// Sidebar row icon.
///
/// The focused selection now fills the row with the app accent (coral), so a
/// coral glyph on top of it disappears; white reads cleanly instead. An
/// unfocused selection keeps its light grey fill, where white would vanish
/// just as badly, so only `.increased` prominence — a focused selection —
/// switches to white. Reading `backgroundProminence` needs its own view: in a
/// method on ContentView it resolves against the list, not the row.
private struct SidebarIcon: View {
    let name: String
    let isSelected: Bool

    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Image(systemName: name)
            .foregroundStyle(iconColor)
            .frame(width: 20)
    }

    private var iconColor: Color {
        if prominence == .increased { return .white }
        return isSelected ? CruftTheme.coral : .secondary
    }
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
        .tint(CruftTheme.coral)
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
                    Text(verbatim: "Cruft")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(verbatim: "DEV HYGIENE")
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
                Section(String(localized: "sidebar.section.space", defaultValue: "Space")) {
                    ForEach(Pane.cleanup) { item in
                        sidebarLabel(item)
                            .tag(item)
                    }
                }

                Section(String(localized: "sidebar.section.system", defaultValue: "System")) {
                    ForEach(Pane.system) { item in
                        HStack {
                            SidebarIcon(name: item.icon, isSelected: pane == item)
                            Text(item.title)
                            if item == .history, !history.batches.isEmpty {
                                Spacer()
                                Text(verbatim: "\(history.batches.count)")
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
            SidebarIcon(name: item.icon, isSelected: pane == item)
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
                title: String(localized: "projects.title", defaultValue: "Build products"),
                subtitle: String(localized: "projects.subtitle",
                                 defaultValue: "Find dependency and build directories nobody has touched in a while"),
                icon: "shippingbox",
                emptyHint: String(localized: "projects.empty",
                                  defaultValue: "No build product directories found"),
                roots: projectRoots,
                hasFolderAccess: folderAccess.hasFullDiskAccess,
                requestFolderAccess: { showFolderAccess = true }
            )
        case .installers:
            ScanPane(
                vm: installersVM,
                title: String(localized: "installers.title", defaultValue: "Installers"),
                subtitle: String(localized: "installers.subtitle",
                                 defaultValue: "Tidy up the DMGs and PKGs in Downloads and on the Desktop"),
                icon: "opticaldiscdrive",
                emptyHint: String(localized: "installers.empty",
                                  defaultValue: "No .dmg / .pkg installers found"),
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

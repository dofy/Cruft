import AppKit
import SwiftUI

struct CleanPane: View {
    @ObservedObject var vm: CleanerViewModel
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConfirm = false
    @State private var showLog = false

    private var logAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: String(localized: "clean.title", defaultValue: "Clean"),
                subtitle: String(localized: "clean.subtitle",
                                 defaultValue: "Send rebuildable development caches to the Trash"),
                icon: "sparkles",
                metric: String(localized: "clean.metric.free",
                               defaultValue: "\(byteString(vm.freeSpace)) free")
            )
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(CleanupCategory.allCases) { category in
                        let rows = vm.items(in: category)
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(category.title)
                                        .font(.system(.headline, design: .rounded, weight: .semibold))
                                    Spacer()
                                    Text(verbatim: "\(rows.filter { $0.isEnabled }.count) / \(rows.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                SurfaceCard {
                                    VStack(spacing: 0) {
                                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                                            TaskRowView(
                                                item: item,
                                                isEnabled: vm.binding(for: item),
                                                locked: vm.isRunning,
                                                sizeState: vm.sizeState(for: item)
                                            )
                                            if index < rows.count - 1 { Divider().padding(.leading, 42) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            logConsole
            Divider()
            footer
        }
        .onChange(of: vm.isRunning) { _, running in
            if running { withAnimation(logAnimation) { showLog = true } }
        }
        .confirmationDialog(
            String(localized: "clean.confirm.title", defaultValue: "Start this maintenance run?"),
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "clean.confirm.start",
                       defaultValue: "Start cleaning (\(vm.selectedCount) tasks)"),
                role: .destructive
            ) {
                Task { await vm.run() }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "clean.confirm.message",
                        defaultValue: "File tasks move things to the Trash and record a restore point. Command tasks, emptying the Trash and Docker prune can’t be undone."))
        }
    }

    private var logConsole: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(logAnimation) { showLog.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showLog ? 90 : 0))
                    Text(String(localized: "log.title", defaultValue: "Run log"))
                    if !showLog && !vm.log.isEmpty {
                        Circle().fill(CruftTheme.coral).frame(width: 6, height: 6)
                    }
                    Spacer()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        Text(vm.log.isEmpty
                             ? String(localized: "log.empty",
                                      defaultValue: "Task output shows up here.")
                             : vm.log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(vm.log.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(14)
                            .id("log-tail")
                    }
                    .background(Color.black.opacity(0.035))
                    .opacity(showLog ? 1 : 0)
                    .offset(y: showLog ? 0 : 16)
                    .onChange(of: vm.log) { _, _ in
                        proxy.scrollTo("log-tail", anchor: .bottom)
                    }
                }
                .frame(height: showLog ? 140 : 0, alignment: .bottom)
                .clipped()
                .allowsHitTesting(showLog)
                .accessibilityHidden(!showLog)
            }
        }
        .animation(logAnimation, value: showLog)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if vm.isRunning {
                ProgressView(value: vm.progress)
                    .frame(width: 170)
                Text(vm.currentTask)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if vm.finished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(String(localized: "clean.footer.result",
                            defaultValue: "\(byteString(vm.movedToTrashBytes)) moved to the Trash · \(byteString(vm.freedBytes)) actually freed"))
                    .font(.callout.weight(.medium))
            } else {
                Text(String(localized: "clean.footer.selected",
                            defaultValue: "\(vm.selectedCount) tasks selected"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                guard hasFolderAccess else {
                    requestFolderAccess()
                    return
                }
                showConfirm = true
            } label: {
                Label(String(localized: "clean.start", defaultValue: "Start maintenance"),
                      systemImage: "play.fill")
            }
            .buttonStyle(AccentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(vm.isRunning || vm.selectedCount == 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

struct ScanPane: View {
    @ObservedObject var vm: ScanViewModel
    let title: String
    let subtitle: String
    let icon: String
    let emptyHint: String
    let roots: [String]
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: title,
                subtitle: subtitle,
                icon: icon,
                metric: vm.hasScanned ? byteString(vm.totalBytes) : nil
            )
            Divider()

            Group {
                if vm.isScanning {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "scan.scanning", defaultValue: "Scanning…"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !vm.hasScanned {
                    EmptyStateView(
                        icon: icon,
                        title: String(localized: "scan.empty.title",
                                      defaultValue: "Start with a safe scan"),
                        message: vm.mode == .projects
                            ? String(localized: "scan.empty.projects",
                                     defaultValue: "Scans Works, Projects and Developer. Projects touched in the last 7 days aren’t ticked by default.")
                            : String(localized: "scan.empty.installers",
                                     defaultValue: "Scans your Downloads folder and the Desktop. Installers are always yours to pick one by one.")
                    )
                } else if vm.items.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.seal",
                        title: String(localized: "scan.clean.title", defaultValue: "Nothing here"),
                        message: emptyHint
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(vm.items) { item in
                                ScanRowView(item: item) { vm.toggle(item.id) }
                            }
                        }
                        .padding(24)
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                if vm.hasScanned {
                    Text(String(localized: "scan.footer.selected",
                                defaultValue: "\(vm.selectedCount) selected · \(byteString(vm.selectedBytes))"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "scan.footer.notscanned", defaultValue: "Not scanned yet"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if vm.lastFailedCount > 0 {
                    Text(String(localized: "scan.footer.failed",
                                defaultValue: "· \(vm.lastFailedCount) failed to move"))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    if hasFolderAccess {
                        vm.scan(roots: roots)
                    } else {
                        requestFolderAccess()
                    }
                } label: {
                    Label(vm.hasScanned
                          ? String(localized: "scan.rescan", defaultValue: "Scan again")
                          : String(localized: "scan.scan", defaultValue: "Scan"),
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(vm.isScanning || vm.isDeleting)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Label(String(localized: "common.movetotrash", defaultValue: "Move to Trash"),
                          systemImage: "trash")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(vm.selectedCount == 0 || vm.isScanning || vm.isDeleting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .confirmationDialog(
            String(localized: "scan.confirm.title", defaultValue: "Move to the Trash?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "scan.confirm.move", defaultValue: "Move \(vm.selectedCount) items"),
                role: .destructive
            ) {
                Task { _ = await vm.deleteSelected() }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "scan.confirm.message",
                        defaultValue: "The path mapping is saved, so Restore History can move these back. Once the Trash is emptied they’re gone."))
        }
    }
}

struct ApplicationsPane: View {
    @ObservedObject var vm: AppCleanerViewModel
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: String(localized: "apps.title", defaultValue: "App cleanup"),
                subtitle: String(localized: "apps.subtitle",
                                 defaultValue: "Uninstall an app and review what it left in your home folder"),
                icon: "app.badge.checkmark",
                metric: vm.hasScannedApps
                    ? String(localized: "apps.metric.count", defaultValue: "\(vm.apps.count) apps")
                    : nil
            )
            Divider()

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "apps.search.prompt",
                                 defaultValue: "Search apps or bundle IDs"),
                          text: $vm.query)
                    .textFieldStyle(.plain)
                Spacer()
                if !vm.statusMessage.isEmpty {
                    Text(vm.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    if hasFolderAccess {
                        vm.scanApps()
                    } else {
                        requestFolderAccess()
                    }
                } label: {
                    Label(vm.hasScannedApps
                          ? String(localized: "scan.rescan", defaultValue: "Scan again")
                          : String(localized: "apps.scan", defaultValue: "Scan apps"),
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(vm.isScanningApps)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(Color.primary.opacity(0.025))
            Divider()

            Group {
                if vm.isScanningApps {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "apps.loading",
                                    defaultValue: "Reading apps and the space they take…"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !vm.hasScannedApps {
                    EmptyStateView(
                        icon: "square.grid.2x2",
                        title: String(localized: "apps.empty.title",
                                      defaultValue: "Build the app list first"),
                        message: String(localized: "apps.empty.message",
                                        defaultValue: "Reads /Applications and ~/Applications. Only files matched by an exact bundle ID are ticked by default.")
                    )
                } else if vm.filteredApps.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: String(localized: "apps.nomatch.title",
                                      defaultValue: "No app matches"),
                        message: String(localized: "apps.nomatch.message",
                                        defaultValue: "Try a different name or bundle ID.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(vm.filteredApps) { app in
                                ApplicationRow(app: app) { vm.inspect(app) }
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .sheet(item: $vm.selectedApp) { app in
            AppCleanupSheet(vm: vm, app: app)
        }
    }
}

struct AppCleanupSheet: View {
    @ObservedObject var vm: AppCleanerViewModel
    let app: InstalledApplication
    @Environment(\.dismiss) private var dismiss
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AppIconView(path: app.path, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "appsheet.title", defaultValue: "Clean up \(app.name)"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(app.bundleIdentifier.isEmpty
                         ? String(localized: "appsheet.nobundleid",
                                  defaultValue: "No bundle ID was read; only the app itself is shown")
                         : app.bundleIdentifier)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(app.bundleIdentifier.isEmpty ? Color.orange : Color.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button(String(localized: "appsheet.finder", defaultValue: "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                }
                Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() }
            }
            .padding(20)
            Divider()

            if vm.isScanningRelated {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: "appsheet.matching",
                                defaultValue: "Matching related files…"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(String(localized: "appsheet.legend.exact",
                                         defaultValue: "Exact matches are ticked"),
                                  systemImage: "checkmark.shield")
                            Spacer()
                            Label(String(localized: "appsheet.legend.name",
                                         defaultValue: "Name matches need confirming"),
                                  systemImage: "exclamationmark.triangle")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(vm.candidates) { item in
                            AppCleanupRow(item: item) { vm.toggle(item.id) }
                        }
                    }
                    .padding(20)
                }
            }

            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "appsheet.selected",
                                defaultValue: "\(vm.selectedCount) selected · \(byteString(vm.selectedBytes))"))
                        .font(.callout.weight(.medium))
                    if !vm.statusMessage.isEmpty {
                        Text(vm.statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    showConfirm = true
                } label: {
                    Label(vm.isDeleting
                          ? String(localized: "appsheet.moving", defaultValue: "Moving…")
                          : String(localized: "common.movetotrash", defaultValue: "Move to Trash"),
                          systemImage: "trash")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(vm.selectedCount == 0 || vm.isScanningRelated || vm.isDeleting)
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 540)
        .confirmationDialog(
            String(localized: "appsheet.confirm.title", defaultValue: "Uninstall and clean up?"),
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "scan.confirm.move", defaultValue: "Move \(vm.selectedCount) items"),
                role: .destructive
            ) {
                Task { await vm.moveSelectedToTrash() }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "appsheet.confirm.message",
                        defaultValue: "The selected items go to the Trash and a restore point is recorded. Cruft won’t force its way to admin rights, so a protected app may fail to move."))
        }
    }
}

struct BackgroundPane: View {
    @ObservedObject var vm: BTMViewModel
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: String(localized: "btm.title", defaultValue: "Background apps"),
                subtitle: String(localized: "btm.subtitle",
                                 defaultValue: "A read-only look at login items, agents, daemons and stale records"),
                icon: "bolt.badge.clock",
                metric: vm.hasLoaded
                    ? String(localized: "btm.metric.count", defaultValue: "\(vm.items.count) items")
                    : nil
            )
            Divider()

            if vm.hasLoaded {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(String(localized: "btm.search.prompt",
                                     defaultValue: "Search names, developers, bundle IDs"),
                              text: $vm.query)
                        .textFieldStyle(.plain)
                    if vm.orphanCount > 0 {
                        Toggle(String(localized: "btm.orphanonly",
                                      defaultValue: "Stale only (\(vm.orphanCount))"),
                               isOn: $vm.orphanOnly)
                            .toggleStyle(.checkbox)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Color.primary.opacity(0.025))
                Divider()
            }

            Group {
                if vm.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(String(localized: "btm.loading",
                                    defaultValue: "Reading the system’s background activity…"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !vm.hasLoaded {
                    EmptyStateView(
                        icon: "bolt.badge.clock",
                        title: String(localized: "btm.empty.title",
                                      defaultValue: "See what runs in the background"),
                        message: String(localized: "btm.empty.message",
                                        defaultValue: "The data comes from sfltool dumpbtm. This pane only observes; it never edits the system’s records.")
                    )
                } else if vm.filtered.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.seal",
                        title: String(localized: "btm.nomatch.title", defaultValue: "No matches"),
                        message: String(localized: "btm.nomatch.message",
                                        defaultValue: "Clear the search or turn off the stale filter.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(vm.filtered) { BTMRowView(item: $0) }
                        }
                        .padding(24)
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                if vm.hasLoaded {
                    Text(String(localized: "btm.footer",
                                defaultValue: "\(vm.enabledCount) enabled · \(vm.orphanCount) stale"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "btm.systemsettings", defaultValue: "System Settings"),
                          systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    if hasFolderAccess {
                        vm.load()
                    } else {
                        requestFolderAccess()
                    }
                } label: {
                    Label(vm.hasLoaded
                          ? String(localized: "btm.refresh", defaultValue: "Refresh")
                          : String(localized: "btm.load", defaultValue: "Read"),
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(vm.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}

struct HistoryPane: View {
    @ObservedObject var store: DeletionHistoryStore
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: String(localized: "history.title", defaultValue: "Restore history"),
                subtitle: String(localized: "history.subtitle",
                                 defaultValue: "Move items still in the Trash back where they came from"),
                icon: "clock.arrow.circlepath",
                metric: hasFolderAccess
                    ? byteString(store.recoverableBytes)
                    : String(localized: "history.metric.needauth", defaultValue: "Needs access")
            )
            Divider()

            if store.batches.isEmpty {
                EmptyStateView(
                    icon: "clock.badge.checkmark",
                    title: String(localized: "history.empty.title",
                                  defaultValue: "No restore points yet"),
                    message: String(localized: "history.empty.message",
                                    defaultValue: "Once build products, installers, apps and file-based cleanups go to the Trash, they leave a restore point here.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 11) {
                        ForEach(store.batches) { batch in
                            HistoryBatchRow(
                                store: store,
                                batch: batch,
                                hasFolderAccess: hasFolderAccess,
                                requestFolderAccess: requestFolderAccess
                            )
                        }
                    }
                    .padding(24)
                }
            }

            if !store.statusMessage.isEmpty {
                Divider()
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
        .onAppear {
            if hasFolderAccess { store.refreshAvailability() }
        }
    }
}

struct HistoryBatchRow: View {
    @ObservedObject var store: DeletionHistoryStore
    let batch: DeletionBatch
    let hasFolderAccess: Bool
    let requestFolderAccess: () -> Void
    @State private var showRestoreConfirm = false

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(CruftTheme.accentGradient)
                        .opacity(0.14)
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(CruftTheme.accentGradient)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(batch.displayTitle).font(.headline)
                    Text(batch.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(batch.displayTasks.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(byteString(batch.totalBytes))
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                    Text(hasFolderAccess
                         ? String(localized: "history.recoverable",
                                  defaultValue: "\(store.recoverableCount(in: batch)) of \(batch.items.count) can be restored")
                         : String(localized: "history.needauth",
                                  defaultValue: "Grant access to check what can be restored"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(String(localized: "history.restore", defaultValue: "Restore")) {
                    if hasFolderAccess {
                        showRestoreConfirm = true
                    } else {
                        requestFolderAccess()
                    }
                }
                    .buttonStyle(.bordered)
                    .disabled((hasFolderAccess && store.recoverableCount(in: batch) == 0) || store.isRestoring)

                Menu {
                    Button(String(localized: "history.forget",
                                  defaultValue: "Remove the record only")) {
                        store.forget(batch)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .confirmationDialog(
            String(localized: "history.confirm.title", defaultValue: "Restore to the original location?"),
            isPresented: $showRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "history.confirm.restore",
                          defaultValue: "Restore \(store.recoverableCount(in: batch)) items")) {
                Task { await store.restore(batch) }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "history.confirm.message",
                        defaultValue: "If a file of the same name is already there, Cruft keeps the existing file and skips that item."))
        }
    }
}

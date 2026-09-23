import AppKit
import Darwin
import SwiftUI

@MainActor
final class FolderAccessManager: ObservableObject {
    static let shared = FolderAccessManager()

    @Published private(set) var hasFullDiskAccess = false
    @Published private(set) var isChecking = false

    private init() {}

    func check() {
        guard !isChecking else { return }
        isChecking = true
        Task.detached(priority: .userInitiated) {
            let allowed = Self.checkFullDiskAccess()
            await MainActor.run {
                self.hasFullDiskAccess = allowed
                self.isChecking = false
            }
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// FDA has no public authorization-status API. Checking read permission on
    /// protected app-data directories avoids enumerating their contents and does
    /// not trigger the per-folder consent dialogs used by Desktop/Downloads.
    nonisolated static func checkFullDiskAccess() -> Bool {
        let probes = [
            "~/Library/Containers/com.apple.stocks",
            "~/Library/Safari",
            "~/Library/Mail",
        ]

        return probes.contains { rawPath in
            let path = (rawPath as NSString).expandingTildeInPath
            return path.withCString { access($0, R_OK) == 0 }
        }
    }
}

struct FolderAccessBanner: View {
    let isChecking: Bool
    let showDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isChecking ? "hourglass" : "folder.badge.questionmark")
                .foregroundStyle(CruftTheme.accentGradient)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(isChecking
                     ? String(localized: "access.banner.checking",
                              defaultValue: "Checking file access")
                     : String(localized: "access.banner.off",
                              defaultValue: "File access isn’t on yet"))
                    .font(.callout.weight(.semibold))
                Text(isChecking
                     ? String(localized: "access.banner.checking.body",
                              defaultValue: "Nothing is read until the check finishes.")
                     : String(localized: "access.banner.off.body",
                              defaultValue: "Cruft hasn’t scanned caches, logs, projects, downloads or the Trash."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if !isChecking {
                Button(String(localized: "access.banner.enable", defaultValue: "Turn on access"),
                       action: showDetails)
                    .buttonStyle(.borderedProminent)
                    .tint(CruftTheme.coral)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.regularMaterial)
    }
}

struct FolderAccessSheet: View {
    @ObservedObject var manager: FolderAccessManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(CruftTheme.accentGradient)
                        .opacity(0.16)
                    Image(systemName: manager.hasFullDiskAccess ? "checkmark.shield.fill" : "folder.badge.gearshape")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(manager.hasFullDiskAccess ? AnyShapeStyle(Color.green) : AnyShapeStyle(CruftTheme.accentGradient))
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(manager.hasFullDiskAccess
                         ? String(localized: "access.sheet.title.on",
                                  defaultValue: "File access is on")
                         : String(localized: "access.sheet.title.off",
                                  defaultValue: "Turn on Full Disk Access"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(String(localized: "access.sheet.subtitle",
                                defaultValue: "macOS manages this, and you can turn it off in System Settings at any time"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(localized: "access.sheet.body",
                        defaultValue: "Cruft has to read the development caches, logs, build products, downloads and Trash in your home folder to estimate what they take up and to run the cleanups you confirm. File contents are processed on this machine and never uploaded."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "access.sheet.steps", defaultValue: "How to grant it"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Label(String(localized: "access.sheet.step1",
                                 defaultValue: "Open Privacy & Security → Full Disk Access"),
                          systemImage: "1.circle.fill")
                    Label(String(localized: "access.sheet.step2",
                                 defaultValue: "Add or switch on /Applications/Cruft.app"),
                          systemImage: "2.circle.fill")
                    Label(String(localized: "access.sheet.step3",
                                 defaultValue: "Come back to Cruft; it re-checks by itself"),
                          systemImage: "3.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Label(String(localized: "access.sheet.note",
                         defaultValue: "Without access, Cruft doesn’t scan anything."),
                  systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    manager.check()
                } label: {
                    Label(manager.isChecking
                          ? String(localized: "access.sheet.checking", defaultValue: "Checking…")
                          : String(localized: "access.sheet.recheck", defaultValue: "Check again"),
                          systemImage: "arrow.clockwise")
                }
                .disabled(manager.isChecking)

                if !manager.hasFullDiskAccess {
                    Button(String(localized: "common.opensystemsettings",
                                  defaultValue: "Open System Settings")) {
                        manager.openSystemSettings()
                    }
                    .buttonStyle(AccentButtonStyle())
                }
            }
        }
        .padding(22)
        .frame(width: 500)
        .onChange(of: manager.hasFullDiskAccess) { _, allowed in
            if allowed { dismiss() }
        }
    }
}

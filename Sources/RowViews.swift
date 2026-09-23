import SwiftUI

private let emptyToggleLabel = ""

struct TaskRowView: View {
    let item: CleanupItem
    @Binding var isEnabled: Bool
    let locked: Bool
    let sizeState: CleanerViewModel.SizeState
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.055))
                Image(systemName: item.kind.icon)
                    .foregroundStyle(item.isAvailable ? CruftTheme.coral : Color.secondary)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title).fontWeight(.medium)
                Text(item.isAvailable
                     ? item.kind.subtitle
                     : (item.kind.requiredTool.map {
                         String(localized: "task.unavailable.tool",
                                defaultValue: "\($0) isn’t installed, so this is off")
                       } ?? String(localized: "task.unavailable",
                                   defaultValue: "Not detected, so this is off")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            sizeBadge
            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "task.details.help", defaultValue: "See what gets cleaned"))
            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                DetailPopover(kind: item.kind)
            }
            // 空标签用常量而不是字面量 ""：SwiftUI 会把空串当成本地化 key 抽进目录。
            Toggle(emptyToggleLabel, isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!item.isAvailable || locked)
        }
        .padding(.vertical, 9)
        .opacity(item.isAvailable ? 1 : 0.5)
    }

    @ViewBuilder
    private var sizeBadge: some View {
        switch sizeState {
        case .none:
            EmptyView()
        case .computing:
            Text(String(localized: "task.size.computing", defaultValue: "Measuring…"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .known(let bytes):
            Text(byteString(bytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
    }
}

struct ScanRowView: View {
    let item: ScanItem
    let onToggle: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isSelected ? CruftTheme.coral : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(String(localized: "scan.row.age",
                                defaultValue: "\(item.location) · \(item.daysAgo) days ago"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(byteString(item.size))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.isSelected
            ? String(localized: "scan.row.deselect", defaultValue: "Deselect \(item.title)")
            : String(localized: "scan.row.select", defaultValue: "Select \(item.title)"))
    }
}

struct ApplicationRow: View {
    let app: InstalledApplication
    let onInspect: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                AppIconView(path: app.path, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.headline)
                    Text(app.bundleIdentifier.isEmpty ? app.path : app.bundleIdentifier)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(app.size > 0
                         ? byteString(app.size)
                         : String(localized: "app.size.pending",
                                  defaultValue: "Size not checked yet"))
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                    if app.isChromePWA {
                        Text(app.versionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CruftTheme.coral)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(CruftTheme.coral.opacity(0.12), in: Capsule())
                    } else if app.displayVersion != nil {
                        Text(app.versionLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "app.version.unknown", defaultValue: "v N/A"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Button(String(localized: "app.inspect", defaultValue: "Inspect")) { onInspect() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct AppCleanupRow: View {
    let item: AppCleanupItem
    let onToggle: () -> Void

    var body: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isSelected ? CruftTheme.coral : Color.secondary)

                if item.isApplication {
                    AppIconView(path: item.path, size: 36)
                } else {
                    Image(systemName: "doc.badge.gearshape")
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: "\(item.location) · \(item.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(item.confidence.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(item.confidence == .exact ? Color.green : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (item.confidence == .exact ? Color.green : Color.orange).opacity(0.12),
                        in: Capsule()
                    )
                Text(byteString(item.size))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

struct BTMRowView: View {
    let item: BTMItem
    @State private var showInfo = false

    var body: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.055))
                    Image(systemName: item.icon)
                        .foregroundStyle(item.isEnabled ? CruftTheme.coral : Color.secondary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name.isEmpty
                         ? String(localized: "btm.unnamed", defaultValue: "(unnamed)")
                         : item.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(item.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(item.typeLabel).font(.caption).foregroundStyle(.secondary)
                if item.isOrphaned { orphanBadge }
                statusBadge
                Button {
                    showInfo.toggle()
                } label: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                    BTMDetailPopover(item: item)
                }
            }
        }
        .opacity(item.isEnabled ? 1 : 0.62)
    }

    private var statusBadge: some View {
        Text(item.isEnabled
             ? String(localized: "btm.enabled", defaultValue: "Enabled")
             : String(localized: "btm.disabled", defaultValue: "Disabled"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(item.isEnabled ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((item.isEnabled ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
    }

    private var orphanBadge: some View {
        Text(String(localized: "btm.stale", defaultValue: "Stale"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.12), in: Capsule())
    }
}

struct BTMDetailPopover: View {
    let item: BTMItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(item.name.isEmpty
                  ? String(localized: "btm.unnamed", defaultValue: "(unnamed)")
                  : item.name,
                  systemImage: item.icon)
                .font(.headline)
            row(String(localized: "btm.field.type", defaultValue: "Type"), item.typeLabel)
            row(String(localized: "btm.field.status", defaultValue: "Status"), item.dispositionRaw)
            row(String(localized: "btm.field.developer", defaultValue: "Developer"), item.developer)
            row("Team ID", item.teamID)
            row("Bundle ID", item.bundleID)
            row(String(localized: "btm.field.location", defaultValue: "Location"),
                item.isOrphaned
                    ? String(localized: "btm.location.missing",
                             defaultValue: "\(item.location)  ⚠︎ file is missing")
                    : item.location)
            row(String(localized: "btm.field.lastuse", defaultValue: "Last used"), item.lastUse)
        }
        .padding(16)
        .frame(width: 400, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DetailPopover: View {
    let kind: CleanupKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(kind.title, systemImage: kind.icon).font(.headline)
            ForEach(Array(kind.details.enumerated()), id: \.offset) { _, detail in
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.target)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text(detail.note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}

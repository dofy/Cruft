import AppKit
import SwiftUI

enum CruftTheme {
    /// #FF674D — the app's only accent colour: the same flat coral the app icon
    /// uses, shared with the sibling apps, and the colour the sidebar selection
    /// picks up through the AccentColor asset. Kept in sync with `tileColor` in
    /// Scripts/generate_app_icon.swift.
    ///
    /// There used to be a second accent (amber #F59421) on the toggles, row
    /// icons and badges. Once the sidebar started drawing its selection in
    /// coral, the two oranges read as an accident rather than a pair, so
    /// everything accent-coloured now uses this one.
    static let coral = Color(red: 255 / 255, green: 103 / 255, blue: 77 / 255)
    /// #FF965C — the light end of the accent gradient. A brightened coral, not
    /// a second hue, so the gradient stays one colour family.
    static let coralLight = Color(red: 255 / 255, green: 150 / 255, blue: 92 / 255)
    static let ink = Color(red: 0.13, green: 0.15, blue: 0.18)
    static let accentGradient = LinearGradient(
        colors: [coralLight, coral],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.09)
}

func byteString(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "0 KB" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct SurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(CruftTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CruftTheme.border, lineWidth: 1)
            }
    }
}

struct PaneHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    var metric: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(CruftTheme.accentGradient)
                    .opacity(0.16)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CruftTheme.accentGradient)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if let metric {
                Text(metric)
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.055), in: Capsule())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(CruftTheme.accentGradient)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct StorageGauge: View {
    let free: Int64
    let total: Int64

    private var usedRatio: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - free) / Double(total)))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.09), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: usedRatio)
                    .stroke(
                        CruftTheme.accentGradient,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: "internaldrive.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("可用空间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(byteString(free))
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
            }
        }
    }
}

struct AppIconView: View {
    let path: String
    var size: CGFloat = 42

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                CruftTheme.accentGradient
                    .opacity(configuration.isPressed ? 0.76 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

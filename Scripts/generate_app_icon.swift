#!/usr/bin/env swift

import AppKit

private let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/Assets.xcassets/AppIcon.appiconset")
private let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

private let amber = NSColor(red: 0.96, green: 0.58, blue: 0.13, alpha: 1)
private let coral = NSColor(red: 0.96, green: 0.35, blue: 0.22, alpha: 1)

private func renderIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let scale = CGFloat(size) / 1024
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let tile = canvas.insetBy(dx: 72 * scale, dy: 72 * scale)
    let cornerRadius = 205 * scale
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.current = graphicsContext
    graphicsContext.cgContext.clear(canvas)
    graphicsContext.cgContext.interpolationQuality = .high

    graphicsContext.cgContext.saveGState()
    graphicsContext.cgContext.setShadow(
        offset: CGSize(width: 0, height: -18 * scale),
        blur: 30 * scale,
        color: NSColor.black.withAlphaComponent(0.20).cgColor
    )
    coral.setFill()
    tilePath.fill()
    graphicsContext.cgContext.restoreGState()

    let gradient = NSGradient(colors: [amber, coral])!
    gradient.draw(in: tilePath, angle: -45)

    NSColor.white.withAlphaComponent(0.16).setStroke()
    tilePath.lineWidth = max(1, 2 * scale)
    tilePath.stroke()

    let pointSize = max(9, 400 * scale)
    let baseConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
    let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white])
    guard let symbol = NSImage(systemSymbolName: "wind", accessibilityDescription: nil)?
        .withSymbolConfiguration(baseConfiguration.applying(colorConfiguration)) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let maximumSymbolSize = CGSize(width: 500 * scale, height: 390 * scale)
    let symbolScale = min(
        maximumSymbolSize.width / symbol.size.width,
        maximumSymbolSize.height / symbol.size.height
    )
    let symbolSize = CGSize(
        width: symbol.size.width * symbolScale,
        height: symbol.size.height * symbolScale
    )
    let symbolRect = CGRect(
        x: canvas.midX - symbolSize.width / 2,
        y: canvas.midY - symbolSize.height / 2 + 8 * scale,
        width: symbolSize.width,
        height: symbolSize.height
    )
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for size in iconSizes {
    let destination = outputDirectory.appendingPathComponent("icon_\(size).png")
    try renderIcon(size: size).write(to: destination, options: .atomic)
    print("Generated \(destination.path)")
}

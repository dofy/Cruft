#!/usr/bin/env swift

import AppKit

private let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sources/Assets.xcassets/AppIcon.appiconset")
private let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

// Shared look across the phpz.xyz apps, measured off LinguaDock's master icon:
// a flat coral tile inset from the canvas, a 25% corner radius, and one solid
// white glyph. No gradient, no shadow, no rim stroke — those were what made
// this icon read as unrelated to its siblings.
private let tileColor = NSColor(red: 255 / 255, green: 103 / 255, blue: 77 / 255, alpha: 1)
private let canvasInset: CGFloat = 62          // 6.1% of the canvas on every side
private let cornerRadiusRatio: CGFloat = 0.25  // of the tile's width
private let glyphWidthRatio: CGFloat = 0.68    // of the tile's width
private let strokeRatio: CGFloat = 0.062       // of the tile's width

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
    let tile = canvas.insetBy(dx: canvasInset * scale, dy: canvasInset * scale)
    let cornerRadius = tile.width * cornerRadiusRatio
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.current = graphicsContext
    graphicsContext.cgContext.clear(canvas)
    graphicsContext.cgContext.interpolationQuality = .high

    tileColor.setFill()
    tilePath.fill()

    NSColor.white.setStroke()
    let glyphWidth = tile.width * glyphWidthRatio
    let glyphHeight = glyphWidth * 0.72
    let glyph = windPath(in: CGRect(
        x: tile.midX - glyphWidth / 2,
        y: tile.midY - glyphHeight / 2,
        width: glyphWidth, height: glyphHeight
    ), lineWidth: tile.width * strokeRatio)
    glyph.stroke()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

/// Three wind streaks, each ending in a hooked curl.
///
/// Drawn by hand rather than using the `wind` SF Symbol: even at `.black` that
/// symbol's strokes are far lighter than the chunky glyphs the sibling icons
/// use, so it read as thin and small next to them.
private func windPath(in rect: CGRect, lineWidth: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    let radius = rect.height * 0.15

    // Top streak: shorter, hooks upward.
    let topY = rect.maxY - radius * 2
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: topY))
    path.line(to: CGPoint(x: rect.minX + rect.width * 0.58, y: topY))
    path.appendArc(
        withCenter: CGPoint(x: rect.minX + rect.width * 0.58, y: topY + radius),
        radius: radius, startAngle: -90, endAngle: 170, clockwise: false
    )

    // Middle streak: the longest, hooks downward at the far right.
    let midY = rect.midY
    path.move(to: CGPoint(x: rect.minX, y: midY))
    path.line(to: CGPoint(x: rect.maxX - radius, y: midY))
    path.appendArc(
        withCenter: CGPoint(x: rect.maxX - radius, y: midY - radius),
        radius: radius, startAngle: 90, endAngle: -170, clockwise: true
    )

    // Bottom streak: hooks downward, shortest of the three.
    let bottomY = rect.minY + radius * 2
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.04, y: bottomY))
    path.line(to: CGPoint(x: rect.minX + rect.width * 0.46, y: bottomY))
    path.appendArc(
        withCenter: CGPoint(x: rect.minX + rect.width * 0.46, y: bottomY - radius),
        radius: radius, startAngle: 90, endAngle: -170, clockwise: true
    )

    return path
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for size in iconSizes {
    let destination = outputDirectory.appendingPathComponent("icon_\(size).png")
    try renderIcon(size: size).write(to: destination, options: .atomic)
    print("Generated \(destination.path)")
}

// Renders assets/AppIcon.icns — a Liquid Glass–style coffee cup on a warm squircle.
// Usage: swift scripts/make-icon.swift   (only needed if you change the design)
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: 824/1024 body, centred, continuous-corner squircle.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    // Soft drop shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Espresso → caramel base.
    NSGradient(colors: [NSColor(red: 0.98, green: 0.66, blue: 0.33, alpha: 1),
                        NSColor(red: 0.55, green: 0.27, blue: 0.11, alpha: 1),
                        NSColor(red: 0.20, green: 0.10, blue: 0.05, alpha: 1)])!
        .draw(in: shape, angle: -90)

    // Glass: specular sheen on the upper half + bright rim.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [.white.withAlphaComponent(0.38), .white.withAlphaComponent(0.0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: s * 0.004, dy: s * 0.004),
                           xRadius: body.width * 0.222, yRadius: body.width * 0.222)
    rim.lineWidth = s * 0.008
    NSColor.white.withAlphaComponent(0.45).setStroke()
    rim.stroke()

    // Frosted cup glyph.
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let cup = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = cup.size
        let rect = NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2 - s * 0.01,
                          width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = .black.withAlphaComponent(0.35)
        glow.shadowBlurRadius = s * 0.02
        glow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
        glow.set()
        cup.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.95)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try render(pt).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try render(pt * 2).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let out = root.appendingPathComponent("assets/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run(); p.waitUntilExit()
print("Wrote \(out.path)")

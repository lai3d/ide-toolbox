// Draws the IDE Toolbox app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (needs iconutil, part of macOS)
import AppKit

func render(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024
    // macOS icon grid: 824pt body inset 100pt, corner radius ~185pt.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(red: 0.20, green: 0.23, blue: 0.30, alpha: 1).cgColor,
                 NSColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 924 * s), end: CGPoint(x: 1024 * s, y: 100 * s), options: [])

    // A 2x2 grid of tiles, one colour per IDE in the family.
    let colors = [
        NSColor(red: 0.00, green: 0.68, blue: 0.85, alpha: 1),  // Go
        NSColor(red: 0.98, green: 0.78, blue: 0.20, alpha: 1),  // Python
        NSColor(red: 0.25, green: 0.47, blue: 0.98, alpha: 1),  // Database
        NSColor(red: 0.30, green: 0.80, blue: 0.45, alpha: 1),  // Git
    ]
    let tile = 270 * s, gap = 44 * s
    let origin = 512 * s - tile - gap / 2
    for (i, color) in colors.enumerated() {
        let x = origin + CGFloat(i % 2) * (tile + gap)
        let y = origin + CGFloat(1 - i / 2) * (tile + gap)
        let r = CGPath(roundedRect: CGRect(x: x, y: y, width: tile, height: tile),
                       cornerWidth: 64 * s, cornerHeight: 64 * s, transform: nil)
        ctx.addPath(r)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }
    img.unlockFocus()
    return img
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        render(px).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")

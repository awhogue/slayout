#!/usr/bin/env swift
import AppKit

// Renders Slayout's app icon as Resources/Slayout.icns.
// Design: rounded-square purple tile with "SL" / "AY" stacked in white.

let outputDir = "Resources"
let iconsetDir = "\(outputDir)/Slayout.iconset"
let icnsPath = "\(outputDir)/Slayout.icns"

let fm = FileManager.default
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
try? fm.removeItem(atPath: iconsetDir)
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!
    ctx.imageInterpolation = .high

    // Rounded-square background.
    let inset: CGFloat = max(1, s * 0.04)
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(srgbRed: 0.42, green: 0.27, blue: 0.86, alpha: 1.0).setFill()
    path.fill()

    // Subtle inner highlight.
    let highlightRect = rect.insetBy(dx: s * 0.04, dy: s * 0.04)
    let highlight = NSBezierPath(roundedRect: highlightRect,
                                 xRadius: radius * 0.85, yRadius: radius * 0.85)
    NSColor(white: 1.0, alpha: 0.07).setFill()
    highlight.fill()

    // "SL" / "AY" stacked, monospaced-looking.
    let fontSize = s * 0.42
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -fontSize * 0.04,
    ]
    let line1 = NSAttributedString(string: "SL", attributes: attrs)
    let line2 = NSAttributedString(string: "AY", attributes: attrs)
    let m1 = line1.size()
    let m2 = line2.size()
    let lineHeight = fontSize * 0.85
    let blockHeight = lineHeight * 2
    // Cocoa coords: y grows upward. Stack so line1 sits above line2.
    let centerY = s / 2
    let topY = centerY + blockHeight / 2 - lineHeight + (lineHeight - m1.height) / 2
    let bottomY = centerY - blockHeight / 2 + (lineHeight - m2.height) / 2
    line1.draw(at: NSPoint(x: (s - m1.width) / 2, y: topY))
    line2.draw(at: NSPoint(x: (s - m2.width) / 2, y: bottomY))

    img.unlockFocus()

    let tiff = img.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    return rep.representation(using: .png, properties: [:])!
}

// Apple iconset spec: 10 PNGs at 1x and 2x for 16/32/128/256/512.
let outputs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in outputs {
    let data = renderIcon(size: size)
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(name)")
    try data.write(to: url)
    print("wrote \(url.lastPathComponent) (\(size)x\(size))")
}

// Build the .icns via iconutil.
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["--convert", "icns", iconsetDir, "--output", icnsPath]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    print("iconutil failed")
    exit(1)
}
// Cleanup the iconset directory; the .icns is self-contained.
try? fm.removeItem(atPath: iconsetDir)
print("==> \(icnsPath)")

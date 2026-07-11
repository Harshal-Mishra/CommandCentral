// Generates AppIcon.icns: deep-blue gradient squircle with a command symbol.
// Run from the project root:  swift scripts/make_icon.swift
import AppKit

let projectDir = FileManager.default.currentDirectoryPath
let iconsetPath = projectDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // macOS-style margin around the squircle
    let inset = size * 0.09
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.24, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.01, green: 0.03, blue: 0.10, alpha: 1),
    ])
    gradient?.draw(in: rect, angle: -60)

    // Command symbol, tinted white
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "command", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { drawRect in
            symbol.draw(in: drawRect)
            NSColor(calibratedRed: 0.75, green: 0.87, blue: 1.0, alpha: 1).set()
            drawRect.fill(using: .sourceAtop)
            return true
        }
        let symbolRect = NSRect(x: (size - tinted.size.width) / 2,
                                y: (size - tinted.size.height) / 2,
                                width: tinted.size.width,
                                height: tinted.size.height)
        tinted.draw(in: symbolRect)
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, pixels: Int, name: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: iconsetPath + "/" + name))
}

for base in [16, 32, 128, 256, 512] {
    savePNG(drawIcon(pixels: base), pixels: base, name: "icon_\(base)x\(base).png")
    savePNG(drawIcon(pixels: base * 2), pixels: base * 2, name: "icon_\(base)x\(base)@2x.png")
}

print("Wrote \(iconsetPath)")

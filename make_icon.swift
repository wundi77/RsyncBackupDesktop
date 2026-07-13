import AppKit

// AppKit ohne Fenster/Dock initialisieren
_ = NSApplication.shared

let iconsetDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func zeichneIcon(pixel: Int) -> NSImage {
    let s = CGFloat(pixel)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // Abgerundetes Rechteck (Apple-Squircle: ~22,5 % Radius)
    let radius = s * 0.225
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Verlauf: helles Grün oben → kräftiges Grün unten (passend zum
    // App-Akzent Color.backupAccent in RsyncBackupApp.swift)
    let farben = [
        CGColor(red: 0.40, green: 0.78, blue: 0.50, alpha: 1.0),
        CGColor(red: 0.15, green: 0.48, blue: 0.24, alpha: 1.0),
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: farben,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: s / 2, y: s),
        end:   CGPoint(x: s / 2, y: 0),
        options: []
    )

    // SF Symbol in Weiß zentriert zeichnen
    let symbolKonfig = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

    if let symbol = NSImage(systemSymbolName: "externaldrive.badge.timemachine",
                            accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolKonfig) {
        let sw = symbol.size.width
        let sh = symbol.size.height
        symbol.draw(in: CGRect(x: (s - sw) / 2, y: (s - sh) / 2, width: sw, height: sh))
    }

    return image
}

func speicherePNG(_ image: NSImage, pfad: String) {
    guard let tiff   = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png    = bitmap.representation(using: .png, properties: [:])
    else { return }
    try? png.write(to: URL(fileURLWithPath: pfad))
}

let specs: [(name: String, logisch: Int, scale: Int)] = [
    ("icon_16x16",       16,  1),
    ("icon_16x16@2x",    16,  2),
    ("icon_32x32",       32,  1),
    ("icon_32x32@2x",    32,  2),
    ("icon_128x128",    128,  1),
    ("icon_128x128@2x", 128,  2),
    ("icon_256x256",    256,  1),
    ("icon_256x256@2x", 256,  2),
    ("icon_512x512",    512,  1),
    ("icon_512x512@2x", 512,  2),
]

for spec in specs {
    let pixel = spec.logisch * spec.scale
    let icon  = zeichneIcon(pixel: pixel)
    let pfad  = "\(iconsetDir)/\(spec.name).png"
    speicherePNG(icon, pfad: pfad)
    print("  \(pfad) (\(pixel)px)")
}
print("Iconset fertig.")

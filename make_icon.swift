import AppKit

// 生成 AppIcon.iconset：macOS 26+ 规范的 squircle 磁贴
// 深色渐变圆角方块 + 白色 ">_"（左上布局），向 Terminal.app 的新版图标看齐
let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(pixels: Int, name: String) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    // Apple 图标网格：1024 画布中磁贴约 832（81.25%），居中
    let tileSize = s * 0.8125
    let tile = NSRect(x: (s - tileSize) / 2, y: (s - tileSize) / 2, width: tileSize, height: tileSize)
    // squircle 圆角约为磁贴边长的 22.5%
    let radius = tileSize * 0.225
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    // 深色渐变（上浅下深），Terminal.app 风格
    let top = NSColor(calibratedRed: 0.255, green: 0.275, blue: 0.310, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.094, green: 0.102, blue: 0.122, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)

    // 顶部细高光，一点玻璃感
    if let highlight = path.copy() as? NSBezierPath {
        highlight.addClip()
        let hlRect = NSRect(x: tile.minX, y: tile.maxY - tileSize * 0.04, width: tile.width, height: tileSize * 0.04)
        NSColor(calibratedWhite: 1, alpha: 0.18).setFill()
        hlRect.fill(using: .sourceOver)
        NSGraphicsContext.current?.cgContext.resetClip()
    }

    // 白色 ">_"，左上布局（Terminal.app 同款排版）
    let fontSize = tileSize * 0.30
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    let text = ">_" as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let textSize = text.size(withAttributes: attrs)
    let origin = NSPoint(
        x: tile.minX + tileSize * 0.12,
        y: tile.maxY - tileSize * 0.14 - textSize.height
    )
    text.draw(at: origin, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }
}

for base in [16, 32, 128, 256, 512] {
    render(pixels: base, name: "icon_\(base)x\(base)")
    render(pixels: base * 2, name: "icon_\(base)x\(base)@2x")
}
print("iconset generated")

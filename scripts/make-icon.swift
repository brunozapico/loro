import AppKit

let directory = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.08, green: 0.19, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 210, yRadius: 210).fill()
        if let bird = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Loro") {
            let config = NSImage.SymbolConfiguration(pointSize: 570, weight: .medium)
                .applying(.init(paletteColors: [NSColor(calibratedRed: 0.70, green: 0.89, blue: 0.56, alpha: 1)]))
            bird.withSymbolConfiguration(config)?.draw(in: NSRect(x: 195, y: 195, width: 634, height: 634))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        )
    }
}

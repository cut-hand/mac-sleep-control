import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let rect = NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88)
        let path = NSBezierPath(roundedRect: rect, xRadius: p * 0.20, yRadius: p * 0.20)
        NSGradient(starting: NSColor(srgbRed: 0.22, green: 0.31, blue: 0.57, alpha: 1), ending: NSColor(srgbRed: 0.49, green: 0.53, blue: 0.77, alpha: 1))!.draw(in: path, angle: 55)
        if let symbol = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: p * 0.55, weight: .regular)) {
            let tinted = NSImage(size: symbol.size)
            tinted.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: symbol.size).fill()
            symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: p * 0.23, y: p * 0.24, width: p * 0.55, height: p * 0.52))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(filename))
    }
}

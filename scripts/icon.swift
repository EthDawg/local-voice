import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size), inset = s * 0.045
    let shape = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2), xRadius: s * 0.21, yRadius: s * 0.21)
    NSGradient(starting: NSColor(red: 0.10, green: 0.24, blue: 0.23, alpha: 1), ending: NSColor(red: 0.035, green: 0.075, blue: 0.085, alpha: 1))!.draw(in: shape, angle: -65)
    NSColor(red: 0.48, green: 0.89, blue: 0.73, alpha: 1).setFill()
    for (i, height) in [0.19, 0.36, 0.54, 0.40, 0.25].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: s * (0.235 + Double(i) * 0.115), y: s * (0.5 - height / 2), width: s * 0.07, height: s * height), xRadius: s * 0.035, yRadius: s * 0.035).fill()
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { let base = size / 2; try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(base)x\(base)@2x.png")) }
}

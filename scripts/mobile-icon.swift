import AppKit
// Native resource adaptation of scripts/icon.swift: the same five voice bars,
// with an opaque full-bleed square for the system's iOS icon mask.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.15, green: 0.20, blue: 0.26, alpha: 1),
    CGColor(red: 0.035, green: 0.055, blue: 0.09, alpha: 1)
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
context.setFillColor(CGColor(red: 0.43, green: 0.89, blue: 0.73, alpha: 1))
for (i, height) in [0.19, 0.36, 0.54, 0.40, 0.25].enumerated() {
    let rect = CGRect(x: 1024 * (0.235 + Double(i) * 0.115), y: 1024 * (0.5 - height / 2), width: 1024 * 0.07, height: 1024 * height)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 1024 * 0.035, cornerHeight: 1024 * 0.035, transform: nil))
    context.fillPath()
}
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: output)

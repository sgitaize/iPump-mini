// Renders the app icon (1024×1024 PNG, opaque). Usage: swift Scripts/render-icon.swift <out.png>
// Design "iPump-mini" (variant A, docs/internal/design/ipump-mini.md): a small petrol device whose
// screen shows a CGM trace ending in the current value.
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
// No alpha channel: iOS icons must be opaque (iOS masks the corners itself).
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

ctx.setFillColor(color(0xF4F6F8))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Device body.
let body = CGRect(x: 232, y: 232, width: 560, height: 560)
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x0F172A, 0.18))
ctx.addPath(CGPath(roundedRect: body, cornerWidth: 150, cornerHeight: 150, transform: nil))
ctx.setFillColor(color(0x0F766E))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Screen.
let screen = body.insetBy(dx: 80, dy: 120).offsetBy(dx: 0, dy: 40)
ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 60, cornerHeight: 60, transform: nil))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()

// CGM trace on the screen.
let pts = [(-150, -10), (-90, 25), (-30, -25), (30, 5), (90, 55), (140, 40)].map {
    CGPoint(x: screen.midX + CGFloat($0.0), y: screen.midY + CGFloat($0.1))
}
let line = CGMutablePath()
line.move(to: pts[0])
for i in 1..<pts.count {
    let p0 = pts[i - 1], p1 = pts[i]
    line.addQuadCurve(to: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2), control: p0)
    if i == pts.count - 1 { line.addLine(to: p1) }
}
ctx.addPath(line)
ctx.setLineWidth(26)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setStrokeColor(color(0x0F766E))
ctx.strokePath()

// Current value.
let last = pts.last!
ctx.setFillColor(color(0x2563EB))
ctx.fillEllipse(in: CGRect(x: last.x - 26, y: last.y - 26, width: 52, height: 52))

// Button under the screen.
ctx.setFillColor(color(0xFFFFFF, 0.85))
ctx.fillEllipse(in: CGRect(x: body.midX - 34, y: body.minY + 52, width: 68, height: 68))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

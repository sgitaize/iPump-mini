// Renders the app icon (1024×1024 PNG). Usage: swift Scripts/render-icon.swift <out.png>
// Design: white drop on a teal→blue gradient, inside a CGM trace ending in a dot (current value).
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background gradient (iOS masks the corners itself).
let bg = CGGradient(colorsSpace: cs, colors: [color(0x14B8A6), color(0x2563EB)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Drop: circle bottom, pointed top (CoreGraphics y axis points up).
let cx = size / 2, cy: CGFloat = 430, r: CGFloat = 285
let tip = CGPoint(x: cx, y: 905)
let drop = CGMutablePath()
// Tangent point: CP ⟂ PT, so the angle between CT (straight up) and CP is acos(r / |CT|).
let start = CGFloat.pi / 2 - acos(r / (tip.y - cy))
drop.move(to: tip)
drop.addLine(to: CGPoint(x: cx + r * cos(start), y: cy + r * sin(start)))
drop.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: start, endAngle: .pi - start, clockwise: true)
drop.closeSubpath()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x0F172A, 0.28))
ctx.addPath(drop)
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// CGM trace inside the drop.
let pts: [CGPoint] = [(-190, -40), (-120, -10), (-60, -70), (0, -30), (60, 40), (120, 20), (175, 95)]
    .map { CGPoint(x: cx + $0.0, y: cy + $0.1) }
let line = CGMutablePath()
line.move(to: pts[0])
for i in 1..<pts.count {
    let p0 = pts[i - 1], p1 = pts[i]
    let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
    line.addQuadCurve(to: mid, control: p0)
    if i == pts.count - 1 { line.addLine(to: p1) }
}
ctx.addPath(line)
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setStrokeColor(color(0x0F766E))
ctx.strokePath()

// Current value dot with halo.
let last = pts.last!
ctx.setFillColor(color(0x2563EB, 0.22))
ctx.fillEllipse(in: CGRect(x: last.x - 52, y: last.y - 52, width: 104, height: 104))
ctx.setFillColor(color(0x2563EB))
ctx.fillEllipse(in: CGRect(x: last.x - 30, y: last.y - 30, width: 60, height: 60))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

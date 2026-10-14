// Renders icon proposals for "iPump-mini" (1024×1024 PNG).
// Usage: swift docs/design/render-proposals.swift <out-dir>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(name)")
}

func trace(_ ctx: CGContext, _ pts: [CGPoint], width: CGFloat, color c: CGColor) {
    let p = CGMutablePath()
    p.move(to: pts[0])
    for i in 1..<pts.count {
        let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
        p.addQuadCurve(to: mid, control: pts[i - 1])
        if i == pts.count - 1 { p.addLine(to: pts[i]) }
    }
    ctx.addPath(p)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(c)
    ctx.strokePath()
}

// A – "Pump": a small rounded device with a screen showing the trace and the current dot.
render("A-pump") { ctx in
    ctx.setFillColor(color(0xF4F6F8)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let body = CGRect(x: 232, y: 232, width: 560, height: 560)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x0F172A, 0.18))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 150, cornerHeight: 150, transform: nil))
    ctx.setFillColor(color(0x0F766E)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let screen = body.insetBy(dx: 80, dy: 120).offsetBy(dx: 0, dy: 40)
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 60, cornerHeight: 60, transform: nil))
    ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    let pts = [(-150, -10), (-90, 25), (-30, -25), (30, 5), (90, 55), (140, 40)].map {
        CGPoint(x: screen.midX + CGFloat($0.0), y: screen.midY + CGFloat($0.1))
    }
    trace(ctx, pts, width: 26, color: color(0x0F766E))
    ctx.setFillColor(color(0x2563EB))
    ctx.fillEllipse(in: CGRect(x: pts.last!.x - 26, y: pts.last!.y - 26, width: 52, height: 52))
    // button under the screen
    ctx.setFillColor(color(0xFFFFFF, 0.85))
    ctx.fillEllipse(in: CGRect(x: body.midX - 34, y: body.minY + 52, width: 68, height: 68))
}

// B – "i·mini": a lowercase i whose dot is a drop, on teal.
render("B-i-drop") { ctx in
    ctx.setFillColor(color(0x0F766E)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 452, y: 210, width: 120, height: 400), cornerWidth: 60, cornerHeight: 60, transform: nil))
    ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    let c = CGPoint(x: 512, y: 720), r: CGFloat = 78, tip = CGPoint(x: 512, y: 860)
    let start = CGFloat.pi / 2 - acos(r / (tip.y - c.y))
    let drop = CGMutablePath()
    drop.move(to: tip)
    drop.addLine(to: CGPoint(x: c.x + r * cos(start), y: c.y + r * sin(start)))
    drop.addArc(center: c, radius: r, startAngle: start, endAngle: .pi - start, clockwise: true)
    drop.closeSubpath()
    ctx.addPath(drop); ctx.setFillColor(color(0x5EEAD4)); ctx.fillPath()
}

// C – "Ring": a calm ring (sensor/gauge) with a short trace and the current dot.
render("C-ring") { ctx in
    ctx.setFillColor(color(0x111827)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setLineWidth(56)
    ctx.setStrokeColor(color(0x1F2937))
    ctx.strokeEllipse(in: CGRect(x: 212, y: 212, width: 600, height: 600))
    ctx.addArc(center: CGPoint(x: 512, y: 512), radius: 300, startAngle: .pi * 0.75, endAngle: .pi * 0.05, clockwise: true)
    ctx.setStrokeColor(color(0x2DD4BF)); ctx.setLineCap(.round); ctx.strokePath()
    let pts = [(-150, -30), (-80, 10), (-20, -40), (50, 10), (130, 70)].map { CGPoint(x: 512 + CGFloat($0.0), y: 512 + CGFloat($0.1)) }
    trace(ctx, pts, width: 30, color: color(0xFFFFFF))
    ctx.setFillColor(color(0x2DD4BF))
    ctx.fillEllipse(in: CGRect(x: pts.last!.x - 30, y: pts.last!.y - 30, width: 60, height: 60))
}

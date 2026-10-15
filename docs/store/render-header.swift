// Renders the App Store header artwork ("Kopfzeile") from the app icon and two screenshots.
// Usage: swift docs/store/render-header.swift <lang de|en> <width> <height> <out.png>
// Sizes accepted by App Store Connect: 5244 x 2950 and 3840 x 1646.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let lang = args.count > 1 ? args[1] : "de"
let W = Int(args.count > 2 ? args[2] : "3840") ?? 3840
let H = Int(args.count > 3 ? args[3] : "1646") ?? 1646
let out = args.count > 4 ? args[4] : "header.png"
let store = URL(fileURLWithPath: #filePath).deletingLastPathComponent()   // docs/store
let repo = store.deletingLastPathComponent().deletingLastPathComponent()

let texts: [String: [String]] = [
    "de": ["iPump-mini", "Deine Insulinpumpe auf dem iPhone.", "Nur lesend. Lokal. Open Source."],
    "en": ["iPump-mini", "Your insulin pump on your iPhone.", "Read-only. Local. Open source."],
]
let t = texts[lang] ?? texts["de"]!

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func image(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
let w = CGFloat(W), h = CGFloat(H), s = h / 1646
// Text scales with the narrower dimension so it never runs into the phones.
let ts = min(s, w / 3840)

// Calm petrol background, slightly darker band on the right (no gloss, no gradients).
ctx.setFillColor(color(0x0F766E)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
ctx.setFillColor(color(0x115E59)); ctx.fill(CGRect(x: w * 0.55, y: 0, width: w * 0.45, height: h))

// Icon (rounded)
if let icon = image(repo.appendingPathComponent("apps/ios/OpenMinipump/Assets.xcassets/AppIcon.appiconset/AppIcon.png")) {
    let size = 300 * ts
    let r = CGRect(x: w * 0.07, y: h * 0.62, width: size, height: size)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: size * 0.225, cornerHeight: size * 0.225, transform: nil))
    ctx.clip()
    ctx.draw(icon, in: r)
    ctx.restoreGState()
}

func text(_ str: String, size: CGFloat, bold: Bool, alpha: CGFloat, y: CGFloat) {
    let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size * ts, nil)!
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0xFFFFFF, alpha),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: str, attributes: attrs))
    ctx.textPosition = CGPoint(x: w * 0.07, y: y)
    CTLineDraw(line, ctx)
}
text(t[0], size: 210, bold: true, alpha: 1, y: h * 0.44)
text(t[1], size: 92, bold: true, alpha: 0.95, y: h * 0.32)
text(t[2], size: 92, bold: false, alpha: 0.75, y: h * 0.24)

// Two phones with the screenshots on the right.
let shots = ["01-home", "02-home-dark"].compactMap { image(store.appendingPathComponent("screenshots/\(lang)/\($0).png")) }
let phoneH = h * 0.86
let phoneW = phoneH * 1320 / 2868
for (i, img) in shots.enumerated() {
    let r = CGRect(x: w * 0.60 + CGFloat(i) * phoneW * 0.78, y: (h - phoneH) / 2 - CGFloat(i) * 40 * s,
                   width: phoneW, height: phoneH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20 * s), blur: 60 * s, color: color(0x000000, 0.35))
    ctx.addPath(CGPath(roundedRect: r.insetBy(dx: -14 * s, dy: -14 * s), cornerWidth: 110 * s, cornerHeight: 110 * s, transform: nil))
    ctx.setFillColor(color(0x0B1F1D)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 96 * s, cornerHeight: 96 * s, transform: nil))
    ctx.clip()
    ctx.draw(img, in: r)
    ctx.restoreGState()
}

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out) \(W)x\(H)")

// Renders LUAM's app icon into LUAM/Assets.xcassets/AppIcon.appiconset.
// Usage: swift Scripts/make-icon.swift   (from the project root)
//
// Design: macOS rounded-square on an indigo→violet gradient, a white page with
// a folded corner, and the Markdown "M↓" mark lifted up — "M↑".

import AppKit

let canvas: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
    let s = canvas
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Big Sur icon grid: 824pt body centred on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(red: 0.30, green: 0.25, blue: 0.85, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient fill.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.47, green: 0.36, blue: 0.98, alpha: 1),   // violet (top)
        CGColor(red: 0.23, green: 0.33, blue: 0.90, alpha: 1),   // indigo (bottom)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s / 2, y: body.maxY),
                           end: CGPoint(x: s / 2, y: body.minY), options: [])
    // Soft top highlight.
    let shine = CGGradient(colorsSpace: space, colors: [
        CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: s / 2, y: body.maxY),
                           end: CGPoint(x: s / 2, y: body.midY), options: [])
    ctx.restoreGState()

    // The page, with a folded top-right corner.
    let page = CGRect(x: 262, y: 200, width: 500, height: 624)
    let fold: CGFloat = 130
    let r: CGFloat = 36
    let pagePath = CGMutablePath()
    pagePath.move(to: CGPoint(x: page.minX + r, y: page.minY))
    pagePath.addLine(to: CGPoint(x: page.maxX - r, y: page.minY))
    pagePath.addQuadCurve(to: CGPoint(x: page.maxX, y: page.minY + r),
                          control: CGPoint(x: page.maxX, y: page.minY))
    pagePath.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    pagePath.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    pagePath.addLine(to: CGPoint(x: page.minX + r, y: page.maxY))
    pagePath.addQuadCurve(to: CGPoint(x: page.minX, y: page.maxY - r),
                          control: CGPoint(x: page.minX, y: page.maxY))
    pagePath.addLine(to: CGPoint(x: page.minX, y: page.minY + r))
    pagePath.addQuadCurve(to: CGPoint(x: page.minX + r, y: page.minY),
                          control: CGPoint(x: page.minX, y: page.minY))
    pagePath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                  color: CGColor(gray: 0, alpha: 0.30))
    ctx.addPath(pagePath)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Folded flap.
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: page.maxX, y: page.maxY - fold))
    flap.addLine(to: CGPoint(x: page.maxX - fold + 18, y: page.maxY - fold))
    flap.addQuadCurve(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold + 18),
                      control: CGPoint(x: page.maxX - fold, y: page.maxY - fold))
    flap.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY))
    flap.closeSubpath()
    ctx.addPath(flap)
    ctx.setFillColor(CGColor(red: 0.82, green: 0.84, blue: 0.95, alpha: 1))
    ctx.fillPath()

    // Faint text lines at the bottom of the page.
    ctx.setFillColor(CGColor(red: 0.78, green: 0.80, blue: 0.92, alpha: 1))
    for (i, width) in [340.0, 280.0].enumerated() {
        let y = page.minY + 70 + CGFloat(i) * 52
        ctx.addPath(CGPath(roundedRect: CGRect(x: page.minX + 80, y: y, width: width, height: 22),
                           cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.fillPath()
    }

    // The mark: "M" + upward arrow, in the gradient's indigo.
    let ink = CGColor(red: 0.27, green: 0.30, blue: 0.88, alpha: 1)
    ctx.setFillColor(ink)
    ctx.setStrokeColor(ink)

    // M — drawn as a stroked polyline for crisp, even weight.
    let stroke: CGFloat = 48
    ctx.setLineWidth(stroke)
    ctx.setLineJoin(.miter)
    ctx.setLineCap(.butt)
    let mBase: CGFloat = 420, mTop: CGFloat = 640
    let mLeft: CGFloat = 345, mRight: CGFloat = 545
    ctx.move(to: CGPoint(x: mLeft, y: mBase))
    ctx.addLine(to: CGPoint(x: mLeft, y: mTop))
    ctx.addLine(to: CGPoint(x: (mLeft + mRight) / 2, y: mTop - 100))
    ctx.addLine(to: CGPoint(x: mRight, y: mTop))
    ctx.addLine(to: CGPoint(x: mRight, y: mBase))
    ctx.strokePath()

    // ↑ arrow, stem bottom level with the M's feet.
    let ax: CGFloat = 645
    let headBase = mTop - 90
    ctx.addPath(CGPath(rect: CGRect(x: ax - 20, y: mBase, width: 40, height: headBase - mBase + 1),
                       transform: nil))
    ctx.fillPath()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: ax, y: mTop + stroke / 2))
    head.addLine(to: CGPoint(x: ax - 58, y: headBase))
    head.addLine(to: CGPoint(x: ax + 58, y: headBase))
    head.closeSubpath()
    ctx.addPath(head)
    ctx.fillPath()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = gc.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: ctx)
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "LUAM/Assets.xcassets/AppIcon.appiconset")
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! png(pixels: size * scale).write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: dir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images")

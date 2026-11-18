// Draws the app icon (1024×1024 PNG) with Core Graphics.
// Usage: swift tools/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint, in path: CGPath) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [])
    ctx.restoreGState()
}

// --- Background squircle (macOS icon grid: 824 pt body, 100 pt margin) ---
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x1d2a44))
ctx.fillPath()
ctx.restoreGState()
linear([color(0x3a5a8c), color(0x16213a)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100), in: bodyPath)

// --- Tablet (tilted slightly, like it's lying on a desk) ---
ctx.saveGState()
ctx.translateBy(x: 512, y: 470)
ctx.rotate(by: -0.10)
let tablet = CGRect(x: -330, y: -230, width: 660, height: 460)
let tabletPath = CGPath(roundedRect: tablet, cornerWidth: 70, cornerHeight: 70, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: color(0x000000, 0.45))
ctx.addPath(tabletPath)
ctx.setFillColor(color(0xd9dde3))
ctx.fillPath()
ctx.restoreGState()
linear([color(0xf4f6f8), color(0xc4cad3)], from: CGPoint(x: 0, y: 230), to: CGPoint(x: 0, y: -230), in: tabletPath)

// Active area
let area = CGRect(x: -270, y: -170, width: 540, height: 340)
let areaPath = CGPath(roundedRect: area, cornerWidth: 26, cornerHeight: 26, transform: nil)
linear([color(0x2b3442), color(0x3c4757)], from: CGPoint(x: 0, y: 170), to: CGPoint(x: 0, y: -170), in: areaPath)

// Drawn stroke on the active area
ctx.saveGState()
ctx.addPath(areaPath)
ctx.clip()
let stroke = CGMutablePath()
stroke.move(to: CGPoint(x: -215, y: -60))
stroke.addCurve(to: CGPoint(x: -20, y: 40), control1: CGPoint(x: -150, y: 120), control2: CGPoint(x: -90, y: -120))
stroke.addCurve(to: CGPoint(x: 120, y: 20), control1: CGPoint(x: 30, y: 140), control2: CGPoint(x: 80, y: 90))
ctx.addPath(stroke)
ctx.setLineCap(.round)
ctx.setLineWidth(22)
ctx.setStrokeColor(color(0x5ac8fa))
ctx.strokePath()
ctx.restoreGState()

// Wacom-style status light
ctx.setFillColor(color(0x34c759))
ctx.fillEllipse(in: CGRect(x: 250, y: 188, width: 22, height: 22))
ctx.restoreGState()

// --- Pen, tip resting at the end of the stroke ---
ctx.saveGState()
let tip = CGPoint(x: 512 + 120 * cos(-0.10) - 20 * sin(-0.10), y: 470 + 120 * sin(-0.10) + 20 * cos(-0.10))
ctx.translateBy(x: tip.x, y: tip.y)
ctx.rotate(by: 0.80)   // pen points down-left toward the tip
ctx.setShadow(offset: CGSize(width: 14, height: -20), blur: 22, color: color(0x000000, 0.45))

let penLength: CGFloat = 560, penWidth: CGFloat = 78
// Body (from y = 120 to the end)
let barrel = CGPath(roundedRect: CGRect(x: -penWidth / 2, y: 120, width: penWidth, height: penLength - 120),
                    cornerWidth: penWidth / 2, cornerHeight: penWidth / 2, transform: nil)
ctx.addPath(barrel)
ctx.setFillColor(color(0x2a2f38))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
linear([color(0x1c2027), color(0x4a5260), color(0x1c2027)],
       from: CGPoint(x: -penWidth / 2, y: 0), to: CGPoint(x: penWidth / 2, y: 0), in: barrel)

// Cone toward the tip
let cone = CGMutablePath()
cone.move(to: CGPoint(x: -penWidth / 2, y: 140))
cone.addLine(to: CGPoint(x: penWidth / 2, y: 140))
cone.addLine(to: CGPoint(x: 9, y: 14))
cone.addLine(to: CGPoint(x: -9, y: 14))
cone.closeSubpath()
linear([color(0x9aa3b0), color(0xe6e9ee), color(0x9aa3b0)],
       from: CGPoint(x: -penWidth / 2, y: 0), to: CGPoint(x: penWidth / 2, y: 0), in: cone)
// Nib
ctx.setFillColor(color(0x1c2027))
ctx.fillEllipse(in: CGRect(x: -9, y: 0, width: 18, height: 28))

// Side switch (rocker)
let rocker = CGPath(roundedRect: CGRect(x: -18, y: 220, width: 36, height: 110),
                    cornerWidth: 18, cornerHeight: 18, transform: nil)
linear([color(0x5ac8fa), color(0x2f7fd0)], from: CGPoint(x: 0, y: 330), to: CGPoint(x: 0, y: 220), in: rocker)

// Eraser end band
let band = CGRect(x: -penWidth / 2, y: penLength - 90, width: penWidth, height: 14)
ctx.setFillColor(color(0x9aa3b0))
ctx.fill(band)
ctx.restoreGState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

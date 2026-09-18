import AppKit
import CoreGraphics
import UniformTypeIdentifiers

// 生成 kearch 的 App 图标(1024×1024 PNG)。
// 设计:渐变圆角方块(indigo→cyan)+ 白色放大镜 + AI 火花。
// 用法:swift GenerateAppIcon.swift   →   输出 appicon.png

let S: CGFloat = 1024

func sparklePath(center c: CGPoint, radius r: CGFloat) -> CGPath {
    let inner = r * 0.36
    let path = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 - .pi / 2
        let radius = (i % 2 == 0) ? r : inner
        let p = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S),
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

// 背景圆角方块(squircle 近似)
let inset = S * 0.0976
let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius = rect.width * 0.2237
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let gradColors = [
    CGColor(red: 0.42, green: 0.34, blue: 0.96, alpha: 1),  // indigo(左上)
    CGColor(red: 0.13, green: 0.80, blue: 0.86, alpha: 1)   // cyan(右下)
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end: CGPoint(x: rect.maxX, y: rect.minY),
                       options: [])
// 顶部一层柔光
let glow = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0)
] as CFArray
let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glow, locations: [0, 1])!
ctx.drawLinearGradient(glowGradient,
                       start: CGPoint(x: rect.midX, y: rect.maxY),
                       end: CGPoint(x: rect.midX, y: rect.midY),
                       options: [])
ctx.restoreGState()

// 玻璃投影
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012),
              blur: S * 0.03,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))

// 放大镜镜环
let lensCenter = CGPoint(x: S * 0.455, y: S * 0.555)
let lensRadius = S * 0.175
let ringWidth = S * 0.052
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(ringWidth)
ctx.strokeEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
                             width: lensRadius * 2, height: lensRadius * 2))

// 手柄(指向右下)
let angle = -CGFloat.pi / 4
let handleStart = CGPoint(x: lensCenter.x + cos(angle) * (lensRadius + ringWidth * 0.1),
                          y: lensCenter.y + sin(angle) * (lensRadius + ringWidth * 0.1))
let handleEnd = CGPoint(x: lensCenter.x + cos(angle) * (lensRadius + S * 0.15),
                        y: lensCenter.y + sin(angle) * (lensRadius + S * 0.15))
ctx.setLineCap(.round)
ctx.setLineWidth(S * 0.058)
ctx.move(to: handleStart)
ctx.addLine(to: handleEnd)
ctx.strokePath()

// AI 火花(镜内 + 右上小的)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.addPath(sparklePath(center: CGPoint(x: S * 0.455, y: S * 0.565), radius: S * 0.072))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
ctx.addPath(sparklePath(center: CGPoint(x: S * 0.60, y: S * 0.70), radius: S * 0.032))
ctx.fillPath()

guard let image = ctx.makeImage() else { fatalError("no image") }
let outURL = URL(fileURLWithPath: "appicon.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote appicon.png")

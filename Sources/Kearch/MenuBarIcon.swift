import AppKit

/// 菜单栏用的扁平模板图标:与 App 图标同款「放大镜 + 火花」,纯黑轮廓。
/// isTemplate=true → 系统按明暗菜单栏自动着色。运行时绘制,无需资源文件。
enum MenuBarIcon {
    static func make(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            let s = rect.width
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // 镜环
            let lineWidth = s * 0.11
            let center = CGPoint(x: s * 0.42, y: s * 0.46)
            let r = s * 0.24
            let ring = NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            ring.lineWidth = lineWidth
            ring.stroke()

            // 手柄(右下)
            let angle = -CGFloat.pi / 4
            let start = CGPoint(x: center.x + cos(angle) * (r + lineWidth * 0.1),
                                y: center.y + sin(angle) * (r + lineWidth * 0.1))
            let end = CGPoint(x: center.x + cos(angle) * (r + s * 0.22),
                              y: center.y + sin(angle) * (r + s * 0.22))
            let handle = NSBezierPath()
            handle.move(to: start)
            handle.line(to: end)
            handle.lineWidth = lineWidth
            handle.lineCapStyle = .round
            handle.stroke()

            // 火花(右上)
            sparkle(center: CGPoint(x: s * 0.74, y: s * 0.76), radius: s * 0.16).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func sparkle(center c: CGPoint, radius r: CGFloat) -> NSBezierPath {
        let inner = r * 0.36
        let path = NSBezierPath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let rad = (i % 2 == 0) ? r : inner
            let point = CGPoint(x: c.x + cos(angle) * rad, y: c.y + sin(angle) * rad)
            if i == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }
}

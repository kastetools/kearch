import AppKit

// kearch — 常驻菜单栏的 Spotlight 式 AI 搜索工具。
// LSUIElement=true(Info.plist)+ .accessory 策略:无 Dock 图标,只在菜单栏出现。
@main
struct KearchApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

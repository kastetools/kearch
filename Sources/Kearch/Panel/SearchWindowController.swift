import AppKit
import SwiftUI
import Carbon.HIToolbox

/// 负责搜索面板的显隐、定位、随内容高度动画、以及 ESC / ⌘ / 回车 / 失焦 的处理。
/// 每次唤起都会重建 ViewModel,保证不保存历史会话。
@MainActor
final class SearchWindowController {
    private let panel = SearchPanel()
    private var width: CGFloat = 680

    private var viewModel: SearchViewModel?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var isVisible = false

    /// 唤起前的前台 App,ESC 关闭时把焦点还给它,避免用户被迫用鼠标重新点击。
    private var previousApp: NSRunningApplication?

    // MARK: - 显隐

    func toggle() {
        isVisible ? dismiss() : show()
    }

    func show() {
        // 记住之前的前台 App(排除 kearch 自己),供关闭时归还焦点。
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        rebuildContent()
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        installMonitors()
    }

    /// - Parameter restoreFocus: 是否把焦点还给之前的前台 App。
    ///   ESC / 主动切换关闭时为 true;失焦关闭时为 false(用户是主动点去别处,不该抢回)。
    func dismiss(restoreFocus: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        removeMonitors()
        viewModel?.cancel()
        panel.orderOut(nil)
        if restoreFocus, let app = previousApp, !app.isTerminated {
            app.activate()
        }
        previousApp = nil
    }

    // MARK: - 内容重建(全新状态)

    private func rebuildContent() {
        let scale = SettingsStore.shared.panelScale
        width = PanelMetrics.width(scale: scale)
        let maxResultHeight = PanelMetrics.maxResultHeight(scale: scale)

        let vm = SearchViewModel()
        viewModel = vm
        let root = SearchRootView(
            viewModel: vm,
            panelWidth: width,
            maxResultHeight: maxResultHeight,
            onHeightChange: { [weak self] height in self?.updateHeight(height) }
        )
        panel.contentView = NSHostingView(rootView: root)
    }

    private func positionPanel() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let height = panel.frame.height
        let topY = visible.maxY - visible.height * 0.20
        let origin = NSPoint(x: visible.midX - width / 2, y: topY - height)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)),
                       display: false)
    }

    /// SwiftUI 内容高度变化时,保持顶边不动、向下增高(实现「回车后向下展开」)。
    private func updateHeight(_ height: CGFloat) {
        let clamped = max(1, height)
        var frame = panel.frame
        guard abs(frame.height - clamped) > 0.5 else { return }
        let top = frame.origin.y + frame.height
        frame.size.height = clamped
        frame.size.width = width
        frame.origin.y = top - clamped
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - 事件监听

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // 失焦关闭:用户主动切去别的窗口,不抢回焦点。
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    /// 焦点文本框的字段编辑器是否正处于输入法合成态(存在 marked text)。
    private var isComposing: Bool {
        (panel.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let viewModel else { return event }
        switch event.type {
        case .flagsChanged:
            viewModel.commandDown = event.modifierFlags.contains(.command)
            return event
        case .keyDown:
            // 输入法合成中(拼音选词/取消):放行给字段编辑器,不触发 submit/dismiss。
            if isComposing { return event }
            let commandDown = event.modifierFlags.contains(.command)
            switch Int(event.keyCode) {
            case kVK_Escape:
                dismiss()
                return nil
            case kVK_ANSI_N where commandDown:
                viewModel.newConversation()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if commandDown {
                    viewModel.copyToClipboard()
                    return nil
                }
                viewModel.submit()
                return nil
            default:
                return event
            }
        default:
            return event
        }
    }
}

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var searchController: SearchWindowController?
    private var hotKey: GlobalHotKey?

    private var settingsWindow: NSWindow?
    private let settingsTabModel = SettingsTabModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        let controller = SearchWindowController()
        searchController = controller

        statusBar = StatusBarController(
            onToggle: { [weak controller] in controller?.toggle() },
            onSettings: { [weak self] in self?.showSettings(.general) },
            onAbout: { [weak self] in self?.showSettings(.about) },
            onQuit: { NSApp.terminate(nil) }
        )

        applyHotKey()
    }

    /// accessory 应用默认无主菜单,标准编辑快捷键(⌘A/⌘C/⌘V/⌘X/⌘Z)无处响应。
    /// 装一个 Edit 菜单让这些命令经响应链到达文本框的字段编辑器(菜单栏对 accessory 应用不可见)。
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    /// 依据设置注册 / 注销全局 ⌥Space。设置变更后可再次调用刷新。
    func applyHotKey() {
        if SettingsStore.shared.hotKeyEnabled {
            hotKey = GlobalHotKey { [weak self] in self?.searchController?.toggle() }
        } else {
            hotKey = nil
        }
    }

    // MARK: - 设置窗口

    private func showSettings(_ tab: SettingsTab) {
        if settingsWindow == nil {
            let view = SettingsView(tabModel: settingsTabModel,
                                    onChange: { [weak self] in self?.applyHotKey() })
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "kearch 设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsTabModel.tab = tab
        guard let window = settingsWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

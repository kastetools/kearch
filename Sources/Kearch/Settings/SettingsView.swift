import SwiftUI

enum SettingsTab: Hashable { case general, ai, about }

/// 控制设置窗口初始/当前选中的 Tab(供右键菜单「关于」直接定位到 About)。
@MainActor
final class SettingsTabModel: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// 设置窗口:通用 / AI / 关于 三个 Tab(参考 kaste 布局)。
struct SettingsView: View {
    @ObservedObject var tabModel: SettingsTabModel
    var onChange: () -> Void = {}

    var body: some View {
        TabView(selection: $tabModel.tab) {
            GeneralTab(onChange: onChange)
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AITab()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsTab.ai)
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - 通用

private struct GeneralTab: View {
    var onChange: () -> Void

    @AppStorage(SettingsStore.Key.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(SettingsStore.Key.effort) private var effort = "low"

    private let effortOptions = ["minimal", "low", "medium", "high"]

    var body: some View {
        Form {
            Section("快捷键") {
                Toggle("启用全局快捷键 ⌥Space", isOn: $hotKeyEnabled)
                    .onChange(of: hotKeyEnabled) { _, _ in onChange() }
                LabeledContent("唤起 / 关闭", value: "点击菜单栏图标 或 ⌥Space")
            }
            Section("回答") {
                Picker("推理强度", selection: $effort) {
                    ForEach(effortOptions, id: \.self) { Text($0).tag($0) }
                }
                Text("越高越深入但越慢;日常问答建议 low。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("面板内快捷键") {
                LabeledContent("提交提问", value: "⏎")
                LabeledContent("复制回答", value: "⌘⏎")
                LabeledContent("关闭", value: "Esc / 失焦")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - AI 接口

private struct AITab: View {
    @AppStorage(SettingsStore.Key.baseURL) private var baseURL = ""
    @AppStorage(SettingsStore.Key.model) private var model = ""
    @AppStorage(SettingsStore.Key.apiKey) private var apiKey = ""
    @AppStorage(SettingsStore.Key.systemPrompt) private var systemPrompt = ""

    var body: some View {
        Form {
            Section("接口(留空则读取 ~/.codex 配置)") {
                TextField("Base URL", text: $baseURL, prompt: Text("https://…/openai"))
                TextField("Model", text: $model, prompt: Text("gpt-5.5"))
                SecureField("API Key", text: $apiKey, prompt: Text("留空使用 auth.json"))
            }
            Section {
                TextEditor(text: $systemPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if systemPrompt.isEmpty {
                            Text("例如:用中文简洁回答,先给结论再解释,不要寒暄。")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5).padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("预设系统提示词(每次请求都会附加)")
            } footer: {
                Text("附加在内置提示(注入本机时间、禁止工具调用)之后;留空则不附加。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 关于 + 检查更新

private struct AboutTab: View {
    @State private var checking = false
    @State private var installing = false
    @State private var latest: UpdateChecker.ReleaseInfo?
    @State private var status = ""

    private var currentVersion: String { UpdateChecker.currentVersion() }
    private var hasNewer: Bool {
        guard let latest else { return false }
        return UpdateChecker.isNewer(latest.version, than: currentVersion)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("kearch").font(.title2.weight(.semibold))
            Text("v\(currentVersion)").foregroundStyle(.secondary)
            Text("常驻菜单栏的 Spotlight 式 AI 搜索。")
                .font(.footnote).foregroundStyle(.tertiary)

            Divider().padding(.vertical, 4)

            HStack(spacing: 8) {
                Button(checking ? "检查中…" : "检查更新") {
                    Task { await check() }
                }
                .disabled(checking || installing)

                if hasNewer, let latest {
                    Button(installing ? "安装中…" : "下载 v\(latest.version)") {
                        Task { await install(latest) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(installing)
                }
            }

            if !status.isEmpty {
                Text(status).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 14) {
                if hasNewer, let latest {
                    Link("查看发布说明", destination: latest.htmlURL).font(.footnote)
                }
                Link("GitHub 仓库",
                     destination: URL(string: "https://github.com/\(UpdateChecker.repoOwner)/\(UpdateChecker.repoName)")!)
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @MainActor
    private func check() async {
        checking = true
        status = "正在查询 GitHub…"
        defer { checking = false }
        do {
            let info = try await UpdateChecker.fetchLatest()
            latest = info
            status = UpdateChecker.isNewer(info.version, than: currentVersion)
                ? "发现新版本 v\(info.version)。"
                : "✓ 已是最新版本。"
        } catch {
            status = "失败:\(error.localizedDescription)"
        }
    }

    @MainActor
    private func install(_ info: UpdateChecker.ReleaseInfo) async {
        let alert = NSAlert()
        alert.messageText = "下载并安装 v\(info.version)?"
        alert.informativeText = "kearch 会下载最新 DMG,替换当前的 Kearch.app 并重启。"
        alert.addButton(withTitle: "安装")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        installing = true
        status = "正在下载 v\(info.version)…"
        defer { installing = false }
        do {
            try await UpdateChecker.downloadAndInstall(info)
        } catch {
            status = "安装失败:\(error.localizedDescription)"
        }
    }
}

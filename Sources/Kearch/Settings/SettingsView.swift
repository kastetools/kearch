import SwiftUI

enum SettingsTab: Hashable { case general, ai, about }

/// 控制设置窗口初始/当前选中的分区(供右键菜单「关于」直接定位)。
@MainActor
final class SettingsTabModel: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// 设置窗口:左侧材质导航栏 + 右侧分组内容。
struct SettingsView: View {
    @ObservedObject var tabModel: SettingsTabModel
    var onChange: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 184)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 660, height: 480)
    }

    // MARK: 侧栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("kearch").font(.system(size: 14, weight: .semibold))
                    Text("v\(UpdateChecker.currentVersion())")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)

            navItem(.general, title: "通用", icon: "gearshape")
            navItem(.ai, title: "AI", icon: "sparkles")
            navItem(.about, title: "关于", icon: "info.circle")

            Spacer()
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private func navItem(_ tab: SettingsTab, title: String, icon: String) -> some View {
        let selected = tabModel.tab == tab
        return HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20)
            Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { tabModel.tab = tab }
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch tabModel.tab {
        case .general: GeneralPane(onChange: onChange)
        case .ai: AIPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - 通用

private struct GeneralPane: View {
    var onChange: () -> Void

    @AppStorage(SettingsStore.Key.hotKeyEnabled) private var hotKeyEnabled = true
    @AppStorage(SettingsStore.Key.effort) private var effort = "low"

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $hotKeyEnabled) {
                    Text("启用全局快捷键 ⌥Space")
                }
                .onChange(of: hotKeyEnabled) { _, _ in onChange() }
                LabeledContent("唤起 / 关闭") {
                    Text("菜单栏图标 · ⌥Space").foregroundStyle(.secondary)
                }
            } header: {
                Label("快捷键", systemImage: "command")
            }

            Section {
                Picker("推理强度", selection: $effort) {
                    Text("最小").tag("minimal")
                    Text("低").tag("low")
                    Text("中").tag("medium")
                    Text("高").tag("high")
                }
                .pickerStyle(.segmented)
                Text("越高越深入但越慢;日常问答建议「低」。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Label("回答", systemImage: "brain.head.profile")
            }

            Section {
                keyRow("提交提问", "⏎")
                keyRow("复制回答", "⌘⏎")
                keyRow("关闭窗口", "Esc")
            } header: {
                Label("面板内快捷键", systemImage: "keyboard")
            }
        }
        .formStyle(.grouped)
    }

    private func keyRow(_ label: String, _ keys: String) -> some View {
        LabeledContent(label) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AI 接口

private struct AIPane: View {
    @AppStorage(SettingsStore.Key.baseURL) private var baseURL = ""
    @AppStorage(SettingsStore.Key.model) private var model = ""
    @AppStorage(SettingsStore.Key.apiKey) private var apiKey = ""
    @AppStorage(SettingsStore.Key.systemPrompt) private var systemPrompt = ""

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $baseURL, prompt: Text("https://…/openai"))
                TextField("Model", text: $model, prompt: Text("gpt-5.5"))
                SecureField("API Key", text: $apiKey, prompt: Text("留空使用 auth.json"))
            } header: {
                Label("接口", systemImage: "network")
            } footer: {
                Text("留空则读取 ~/.codex 配置(auth.json / config.toml)。")
            }

            Section {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                    if systemPrompt.isEmpty {
                        Text("例如:用中文简洁回答,先给结论再解释,不要寒暄。")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11).padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $systemPrompt)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                }
                .frame(height: 112)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1))
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            } header: {
                Label("预设系统提示词", systemImage: "text.badge.plus")
            } footer: {
                Text("每次请求附加在内置提示(注入本机时间、禁止工具调用)之后;留空则不附加。")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 关于 + 检查更新

private struct AboutPane: View {
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
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            VStack(spacing: 3) {
                Text("kearch").font(.system(size: 21, weight: .semibold))
                Text("版本 \(currentVersion)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            Text("常驻菜单栏的 Spotlight 式 AI 搜索")
                .font(.footnote).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    Task { await check() }
                } label: {
                    Text(checking ? "检查中…" : "检查更新").frame(minWidth: 72)
                }
                .buttonStyle(.bordered)
                .disabled(checking || installing)

                if hasNewer, let latest {
                    Button {
                        Task { await install(latest) }
                    } label: {
                        Text(installing ? "安装中…" : "下载 v\(latest.version)").frame(minWidth: 84)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(installing)
                }
            }
            .padding(.top, 4)

            if !status.isEmpty {
                Text(status)
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }

            Spacer()

            HStack(spacing: 16) {
                if hasNewer, let latest {
                    Link("发布说明", destination: latest.htmlURL)
                }
                Link("GitHub 仓库",
                     destination: URL(string: "https://github.com/\(UpdateChecker.repoOwner)/\(UpdateChecker.repoName)")!)
            }
            .font(.footnote)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .task {
            // 打开「关于」时自动检查一次,避免手动点击的困惑。
            if latest == nil { await check() }
        }
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
                ? "发现新版本 v\(info.version)(当前 v\(currentVersion))"
                : "✓ 已是最新版本(当前 v\(currentVersion),最新 v\(info.version))"
        } catch {
            status = "检查失败:\(error.localizedDescription)"
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

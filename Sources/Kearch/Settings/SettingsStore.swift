import Foundation

/// UserDefaults 读取层。空字符串视为「未覆盖」,回落到 Codex 配置。
/// 与 SettingsView 的 @AppStorage 使用同一批 key。
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private init() {}

    enum Key {
        static let baseURL = "baseURLOverride"
        static let model = "modelOverride"
        static let apiKey = "apiKeyOverride"
        static let effort = "reasoningEffort"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let systemPrompt = "systemPrompt"
        static let panelScale = "panelScale"
    }

    private func nonEmpty(_ key: String) -> String? {
        guard let value = defaults.string(forKey: key), !value.isEmpty else { return nil }
        return value
    }

    var baseURLOverride: String? { nonEmpty(Key.baseURL) }
    var modelOverride: String? { nonEmpty(Key.model) }
    var apiKeyOverride: String? { nonEmpty(Key.apiKey) }
    var effort: String { nonEmpty(Key.effort) ?? "low" }

    /// 用户自定义系统提示词,每次请求都会附加(为空则不附加)。
    var systemPrompt: String { nonEmpty(Key.systemPrompt) ?? "" }

    /// 面板尺寸(0–100),缩放唤起窗口的宽度与最大高度。默认 50。
    var panelScale: Int {
        defaults.object(forKey: Key.panelScale) == nil ? 50 : defaults.integer(forKey: Key.panelScale)
    }

    var hotKeyEnabled: Bool {
        defaults.object(forKey: Key.hotKeyEnabled) == nil ? true : defaults.bool(forKey: Key.hotKeyEnabled)
    }
}

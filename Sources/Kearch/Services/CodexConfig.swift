import Foundation

/// 最终生效的运行配置(设置覆盖 > Codex 本机配置)。
struct AppConfig {
    let baseURL: String   // 形如 https://host/openai
    let apiKey: String
    let model: String
    let effort: String    // reasoning effort: minimal / low / medium / high
    let systemPrompt: String // 用户自定义系统提示词(可为空)

    var responsesURL: URL {
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/responses")!
    }

    static func resolve() throws -> AppConfig {
        let settings = SettingsStore.shared
        let effort = settings.effort
        let systemPrompt = settings.systemPrompt

        // 非默认档案:直接用该档案的 endpoint/key/model。
        let activeID = ProfilesStore.activeID()
        if activeID != ProfilesStore.defaultID, let profile = ProfilesStore.profile(id: activeID) {
            guard !profile.baseURL.isEmpty else { throw ConfigError.missingEndpoint }
            guard !profile.apiKey.isEmpty else { throw ConfigError.missingKey }
            return AppConfig(baseURL: profile.baseURL,
                             apiKey: profile.apiKey,
                             model: profile.model.isEmpty ? "gpt-5.5" : profile.model,
                             effort: effort, systemPrompt: systemPrompt)
        }

        // 默认档案:读取本机 ~/.codex。
        let codex = CodexConfig.load()
        let baseURL = codex?.baseURL ?? ""
        let apiKey = codex?.apiKey ?? ""
        let model = codex?.model ?? "gpt-5.5"
        guard !baseURL.isEmpty else { throw ConfigError.missingEndpoint }
        guard !apiKey.isEmpty else { throw ConfigError.missingKey }
        return AppConfig(baseURL: baseURL, apiKey: apiKey, model: model,
                         effort: effort, systemPrompt: systemPrompt)
    }
}

enum ConfigError: Error {
    case missingEndpoint
    case missingKey

    var message: String {
        switch self {
        case .missingEndpoint:
            return "未找到 API endpoint。请在 ~/.codex/config.toml 配置,或在设置中填写 Base URL。"
        case .missingKey:
            return "未找到 API Key。请在 ~/.codex/auth.json 配置 OPENAI_API_KEY,或在设置中填写。"
        }
    }
}

/// 读取本机 Codex 配置:auth.json 取 API key;config.toml 取 model / provider base_url。
struct CodexConfig {
    let apiKey: String?
    let baseURL: String?
    let model: String?

    static func load() -> CodexConfig? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let apiKey = loadAPIKey(from: home.appendingPathComponent(".codex/auth.json"))
        let toml = loadToml(from: home.appendingPathComponent(".codex/config.toml"))
        if apiKey == nil && toml.baseURL == nil && toml.model == nil { return nil }
        return CodexConfig(apiKey: apiKey, baseURL: toml.baseURL, model: toml.model)
    }

    private static func loadAPIKey(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = obj["OPENAI_API_KEY"] as? String,
              !key.isEmpty else { return nil }
        return key
    }

    /// 极简 TOML 提取:只解析我们需要的 model / model_provider 及 [model_providers.<name>].base_url。
    private static func loadToml(from url: URL) -> (baseURL: String?, model: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, nil)
        }

        var section = ""
        var model: String?
        var provider: String?
        var providerBaseURLs: [String: String] = [:]

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                section = String(line[line.index(after: line.startIndex)..<close])
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = unquote(String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces))

            if section.isEmpty {
                if key == "model" { model = value }
                if key == "model_provider" { provider = value }
            } else if section.hasPrefix("model_providers.") {
                let name = String(section.dropFirst("model_providers.".count))
                if key == "base_url" { providerBaseURLs[name] = value }
            }
        }

        let baseURL = provider.flatMap { providerBaseURLs[$0] } ?? providerBaseURLs.values.first
        return (baseURL, model)
    }

    /// 去掉两侧引号;无引号时去掉行尾内联注释。
    private static func unquote(_ raw: String) -> String {
        if raw.hasPrefix("\"") {
            if let end = raw.dropFirst().firstIndex(of: "\"") {
                return String(raw[raw.index(after: raw.startIndex)..<end])
            }
        }
        if let hash = raw.firstIndex(of: "#") {
            return raw[..<hash].trimmingCharacters(in: .whitespaces)
        }
        return raw
    }
}

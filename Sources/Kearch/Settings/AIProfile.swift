import Foundation

/// 一个 AI 配置档案(一组 endpoint + key + model)。
struct AIProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var baseURL: String = ""
    var model: String = ""
    var apiKey: String = ""
}

/// 档案持久化(UserDefaults JSON)。默认档案用哨兵 id "default" 表示读取本机 ~/.codex。
enum ProfilesStore {
    static let defaultID = "default"
    private static let profilesKey = "aiProfiles"
    private static let activeKey = "activeProfileID"

    static func load() -> [AIProfile] {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let list = try? JSONDecoder().decode([AIProfile].self, from: data) else { return [] }
        return list
    }

    static func save(_ profiles: [AIProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    static func activeID() -> String {
        UserDefaults.standard.string(forKey: activeKey) ?? defaultID
    }

    static func setActiveID(_ id: String) {
        UserDefaults.standard.set(id, forKey: activeKey)
    }

    static func profile(id: String) -> AIProfile? {
        load().first { $0.id.uuidString == id }
    }
}

/// 连通性测试:向档案的 /responses 发一次最小的非流式请求,看是否 2xx。
enum ConnectionTester {
    static func test(baseURL: String, apiKey: String, model: String) async -> (ok: Bool, message: String) {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty, let url = URL(string: base + "/responses") else {
            return (false, "Base URL 无效")
        }
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (false, "缺少 API Key")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20

        let body: [String: Any] = [
            "model": model.isEmpty ? "gpt-5.5" : model,
            "input": [["role": "user", "content": [["type": "input_text", "text": "ping"]]]],
            "stream": false,
            "store": false,
            "reasoning": ["effort": "low"]
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return (false, "无响应") }
            if (200..<300).contains(http.statusCode) {
                return (true, "连接成功")
            }
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(160) ?? ""
            return (false, "HTTP \(http.statusCode)\(snippet.isEmpty ? "" : ":\(snippet)")")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

import Foundation

enum ClientError: Error {
    case badResponse
    case http(String)

    var message: String {
        switch self {
        case .badResponse: return "无效的服务器响应"
        case .http(let m): return m
        }
    }
}

/// OpenAI Responses API 流式客户端(对应 codex wire_api = "responses")。
/// 以 SSE 逐行解析,产出文本增量。
struct ResponsesClient {
    let config: AppConfig

    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(prompt: prompt)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw ClientError.badResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ClientError.http(try await Self.readError(status: http.statusCode, bytes: bytes))
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty || payload == "[DONE]" { continue }

                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "response.output_text.delta":
                            if let delta = event["delta"] as? String {
                                continuation.yield(delta)
                            }
                        case "response.completed":
                            continuation.finish()
                            return
                        case "response.failed", "response.error", "error":
                            throw ClientError.http(Self.extractError(from: event))
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(prompt: String) throws -> URLRequest {
        var request = URLRequest(url: config.responsesURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // 该 codex 代理无视顶层 instructions,但认 input 里的 developer 消息。
        // 注入本机真实时间并禁止工具调用:既让实时类问题答对,也抑制 {"cmd":...} 泄漏。
        var developerText = """
        你是 kearch 的问答助手,直接用简洁的自然语言或 Markdown 回答问题。\
        运行环境事实(可信):当前本机时间 \(Self.currentTimeString())。\
        你无法执行任何命令或调用工具,遇到需要实时/本地信息时基于已知事实直接回答;\
        严禁输出任何形如 {"cmd": ...} 的工具调用文本。
        """
        // 追加用户在设置里配置的自定义系统提示词。
        if !config.systemPrompt.isEmpty {
            developerText += "\n\n" + config.systemPrompt
        }

        let body: [String: Any] = [
            "model": config.model,
            "input": [
                ["role": "developer",
                 "content": [["type": "input_text", "text": developerText]]],
                ["role": "user",
                 "content": [["type": "input_text", "text": prompt]]]
            ],
            "stream": true,
            "store": false,
            "reasoning": ["effort": config.effort]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz (EEEE)"
        return formatter.string(from: Date())
    }

    private static func extractError(from event: [String: Any]) -> String {
        if let response = event["response"] as? [String: Any],
           let err = response["error"] as? [String: Any],
           let message = err["message"] as? String {
            return message
        }
        if let err = event["error"] as? [String: Any],
           let message = err["message"] as? String {
            return message
        }
        return "请求失败"
    }

    private static func readError(status: Int, bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 4096 { break }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return "HTTP \(status):\n" + text.prefix(400)
        }
        return "HTTP \(status)"
    }
}

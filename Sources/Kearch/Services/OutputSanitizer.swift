import Foundation

/// 剥离流式输出开头的「工具调用」JSON(如 `{"cmd": "..."}`)。
/// 这类内容来自 codex agent 后端,无法用系统提示彻底关闭,故在客户端兜底清理。
enum OutputSanitizer {
    /// 命令类工具调用的特征 key(命中即视为工具调用,予以剥离)。
    private static let toolKeys: Set<String> = ["cmd", "command", "shell", "bash"]

    /// 返回用于展示的干净文本。
    /// 流式过程中若开头是尚未闭合的 `{...`,返回空串以避免闪现半截 JSON。
    static func clean(_ raw: String) -> String {
        var slice = Substring(raw)

        func dropLeadingWhitespace() {
            while let c = slice.first, c == " " || c == "\n" || c == "\r" || c == "\t" {
                slice = slice.dropFirst()
            }
        }

        dropLeadingWhitespace()
        while slice.first == "{" {
            guard let end = objectEnd(slice) else {
                return "" // 对象未闭合,仍在流式,先不显示
            }
            if isToolCall(String(slice[..<end])) {
                slice = slice[end...]
                dropLeadingWhitespace()
            } else {
                break // 完整且非工具调用的对象(用户可能就想要 JSON),保留
            }
        }
        return String(slice)
    }

    /// 第一个完整 JSON 对象闭合 `}` 的下一个位置;未闭合返回 nil。正确处理字符串与转义。
    private static func objectEnd(_ s: Substring) -> Substring.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return s.index(after: i) }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func isToolCall(_ objectString: String) -> Bool {
        guard let data = objectString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let keys = Set(object.keys.map { $0.lowercased() })
        return !keys.isDisjoint(with: toolKeys)
    }
}

import SwiftUI

/// 精简 Markdown 块级渲染:标题 / 段落 / 有序·无序列表 / 围栏代码块。
/// 内联(粗体、斜体、行内代码、链接)交给系统的 AttributedString(markdown:)。
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            inline(content)
                .font(.system(size: headingSize(level), weight: .semibold))

        case .paragraph(let content):
            inline(content)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").font(.system(size: 14))
                        inline(item).font(.system(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .ordered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).").font(.system(size: 14, weight: .medium))
                        inline(item).font(.system(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .code(let code):
            Text(code)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func inline(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 20
        case 2: return 18
        case 3: return 16
        default: return 15
        }
    }
}

// MARK: - 解析

enum MarkdownBlock {
    case heading(level: Int, content: String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case code(String)
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")

        var index = 0
        var paragraph: [String] = []
        var bullets: [String] = []
        var ordered: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullet(bullets)); bullets.removeAll() }
        }
        func flushOrdered() {
            if !ordered.isEmpty { blocks.append(.ordered(ordered)); ordered.removeAll() }
        }
        func flushAll() { flushParagraph(); flushBullets(); flushOrdered() }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 围栏代码块
            if trimmed.hasPrefix("```") {
                flushAll()
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.code(codeLines.joined(separator: "\n")))
                index += 1 // 跳过收尾 ```
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }

            // 标题
            if let heading = parseHeading(trimmed) {
                flushAll()
                blocks.append(heading)
                index += 1
                continue
            }

            // 无序列表
            if let item = bulletItem(trimmed) {
                flushParagraph(); flushOrdered()
                bullets.append(item)
                index += 1
                continue
            }

            // 有序列表
            if let item = orderedItem(trimmed) {
                flushParagraph(); flushBullets()
                ordered.append(item)
                index += 1
                continue
            }

            // 普通段落
            flushBullets(); flushOrdered()
            paragraph.append(trimmed)
            index += 1
        }

        flushAll()
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var rest = Substring(line)
        while rest.first == "#" { level += 1; rest = rest.dropFirst() }
        guard level <= 6, rest.first == " " else { return nil }
        return .heading(level: level, content: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."),
              line[line.startIndex..<dot].allSatisfy(\.isNumber),
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else { return nil }
        return String(line[line.index(dot, offsetBy: 2)...])
    }
}

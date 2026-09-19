import AppKit
import SwiftUI
import Combine

/// 一轮对话中的一条消息。
struct ChatTurn: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

/// 搜索面板的状态机与多轮对话编排。@MainActor:所有状态更新都在主线程。
@MainActor
final class SearchViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle       // 尚无对话
        case loading    // 已提交,等待首个 token
        case streaming  // 正在接收流式内容
        case done       // 完成
        case error(String)
    }

    @Published var query = ""
    @Published var phase: Phase = .idle
    @Published var turns: [ChatTurn] = []
    @Published var commandDown = false
    @Published var showCopied = false

    private var task: Task<Void, Never>?

    var isExpanded: Bool { !turns.isEmpty || phase != .idle }
    var isBusy: Bool { phase == .loading || phase == .streaming }
    var hasConversation: Bool { !turns.isEmpty }

    /// 最后一条 AI 回答(清洗后),用于复制。
    var lastAnswer: String {
        guard let turn = turns.last(where: { $0.role == .assistant }) else { return "" }
        return OutputSanitizer.clean(turn.text)
    }
    var canCopy: Bool { !lastAnswer.isEmpty }

    // MARK: - 提交(首问 / 追问)

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        query = "" // 清空输入框,方便继续追问
        turns.append(ChatTurn(role: .user, text: trimmed))
        let assistant = ChatTurn(role: .assistant, text: "")
        turns.append(assistant)
        let assistantID = assistant.id

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            phase = .loading
        }

        task?.cancel()
        task = Task { [weak self] in
            await self?.run(assistantID: assistantID)
        }
    }

    private func run(assistantID: UUID) async {
        do {
            let config = try AppConfig.resolve()
            let client = ResponsesClient(config: config)

            // 历史:除去末尾这条空的 assistant 占位;AI 历史先做工具调用清洗。
            let history: [ChatMessage] = turns.dropLast().map { turn in
                switch turn.role {
                case .user:
                    return ChatMessage(role: "user", text: turn.text)
                case .assistant:
                    return ChatMessage(role: "assistant", text: OutputSanitizer.clean(turn.text))
                }
            }

            for try await delta in client.stream(messages: history) {
                if Task.isCancelled { return }
                if phase != .streaming {
                    withAnimation(.easeOut(duration: 0.2)) { phase = .streaming }
                }
                if let idx = turns.firstIndex(where: { $0.id == assistantID }) {
                    turns[idx].text += delta
                }
            }
            if !Task.isCancelled {
                withAnimation { phase = .done }
            }
        } catch is CancellationError {
            // 主动取消,忽略
        } catch {
            if !Task.isCancelled {
                // 删除空的 assistant 占位,避免一直转圈
                if let idx = turns.firstIndex(where: { $0.id == assistantID }), turns[idx].text.isEmpty {
                    turns.remove(at: idx)
                }
                withAnimation { phase = .error(Self.friendly(error)) }
            }
        }
    }

    // MARK: - 新对话 / 复制 / 取消

    /// 清空对话记录,保持面板打开(⌘N)。
    func newConversation() {
        task?.cancel()
        task = nil
        query = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            turns = []
            phase = .idle
        }
    }

    func copyToClipboard() {
        guard canCopy else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastAnswer, forType: .string)
        withAnimation { showCopied = true }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { withAnimation { self?.showCopied = false } }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - 错误文案

    private static func friendly(_ error: Error) -> String {
        if let clientError = error as? ClientError { return clientError.message }
        if let configError = error as? ConfigError { return configError.message }
        return error.localizedDescription
    }
}

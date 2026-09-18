import AppKit
import SwiftUI
import Combine

/// 搜索面板的状态机与请求编排。@MainActor:所有状态更新都在主线程。
@MainActor
final class SearchViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle       // 仅搜索框
        case loading    // 已提交,等待首个 token
        case streaming  // 正在接收流式内容
        case done       // 完成
        case error(String)
    }

    @Published var query = ""
    @Published var phase: Phase = .idle
    @Published var response = ""
    @Published var commandDown = false
    @Published var showCopied = false

    private var task: Task<Void, Never>?

    /// 剥离工具调用 JSON 后、用于展示与复制的干净文本。
    var displayText: String { OutputSanitizer.clean(response) }

    var isExpanded: Bool { phase != .idle }
    var canCopy: Bool { !displayText.isEmpty }
    var isBusy: Bool { phase == .loading || phase == .streaming }

    // MARK: - 提交

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        response = ""
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            phase = .loading
        }

        task?.cancel()
        task = Task { [weak self] in
            await self?.run(prompt: trimmed)
        }
    }

    private func run(prompt: String) async {
        do {
            let config = try AppConfig.resolve()
            let client = ResponsesClient(config: config)
            for try await delta in client.stream(prompt: prompt) {
                if Task.isCancelled { return }
                if phase != .streaming {
                    withAnimation(.easeOut(duration: 0.2)) { phase = .streaming }
                }
                response += delta
            }
            if !Task.isCancelled {
                withAnimation { phase = .done }
            }
        } catch is CancellationError {
            // 主动取消,忽略
        } catch {
            if !Task.isCancelled {
                withAnimation { phase = .error(Self.friendly(error)) }
            }
        }
    }

    // MARK: - 复制 / 取消

    func copyToClipboard() {
        guard canCopy else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayText, forType: .string)
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
        if let clientError = error as? ClientError {
            return clientError.message
        }
        if let configError = error as? ConfigError {
            return configError.message
        }
        return error.localizedDescription
    }
}

import SwiftUI
import Pow

/// 面板内容:顶部搜索框 + 回车后向下展开的结果区。
struct SearchRootView: View {
    @ObservedObject var viewModel: SearchViewModel
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @FocusState private var focused: Bool
    @State private var resultContentHeight: CGFloat = 0

    // 自动吸底:流式时始终贴底;用户手动上滚则暂停,滚回底部附近再恢复。
    @State private var stickToBottom = true
    @State private var lastScrollOffset: CGFloat = 0

    private let width: CGFloat = 680
    private let maxResultHeight: CGFloat = 420
    private static let bottomAnchor = "kearch.result.bottom"

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if viewModel.isExpanded {
                Divider().opacity(0.35)
                resultArea
                    .transition(.movingParts.blur.combined(with: .opacity))
            }
        }
        .frame(width: width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .background(HeightReader(onChange: onHeightChange))
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase == .loading {
                stickToBottom = true
                lastScrollOffset = 0
            }
        }
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(viewModel.hasConversation ? "继续追问…" : "问点什么…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($focused)
                .onSubmit { viewModel.submit() }

            if viewModel.isBusy {
                ProgressView().controlSize(.small)
            } else if viewModel.commandDown {
                hints
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var hints: some View {
        HStack(spacing: 6) {
            if viewModel.canCopy { hintPill("↩", "复制") }
            if viewModel.hasConversation { hintPill("N", "新对话") }
        }
        .transition(.opacity)
    }

    private func hintPill(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "command").font(.system(size: 10, weight: .semibold))
            Text("\(key) \(label)").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }

    // MARK: - 结果区

    private var resultArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                resultContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(key: ContentHeightKey.self, value: g.size.height)
                                .preference(key: ScrollOffsetKey.self,
                                            value: g.frame(in: .named("resultScroll")).minY)
                        }
                    )
                Color.clear.frame(height: 1).id(Self.bottomAnchor)
            }
            .coordinateSpace(name: "resultScroll")
            .frame(height: min(max(resultContentHeight, 1), maxResultHeight))
            .onPreferenceChange(ContentHeightKey.self) { newHeight in
                resultContentHeight = newHeight
                if stickToBottom {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onPreferenceChange(ScrollOffsetKey.self) { minY in
                handleScroll(minY: minY)
            }
            .overlay(alignment: .bottomTrailing) {
                if viewModel.showCopied { copiedToast }
            }
            .overlay(alignment: .bottom) {
                if !stickToBottom {
                    Button {
                        stickToBottom = true
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.accentColor, in: Circle())
                            .shadow(radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                    .transition(.movingParts.pop(Color.accentColor))
                }
            }
        }
    }

    /// 依据滚动偏移判断用户意图:上滚离开底部则暂停吸底,滚回底部附近则恢复。
    private func handleScroll(minY: CGFloat) {
        let viewport = min(max(resultContentHeight, 1), maxResultHeight)
        let offset = -minY // 顶部为 0,向下滚动增大
        let distanceFromBottom = max(0, resultContentHeight - viewport - offset)
        if offset < lastScrollOffset - 1, distanceFromBottom > 16 {
            stickToBottom = false
        }
        if distanceFromBottom <= 12 {
            stickToBottom = true
        }
        lastScrollOffset = offset
    }

    @ViewBuilder
    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(viewModel.turns) { turn in
                turnView(turn)
            }
            if case .error(let message) = viewModel.phase {
                errorRow(message)
            }
        }
    }

    @ViewBuilder
    private func turnView(_ turn: ChatTurn) -> some View {
        switch turn.role {
        case .user:
            HStack(spacing: 0) {
                Spacer(minLength: 44)
                Text(turn.text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        case .assistant:
            let clean = OutputSanitizer.clean(turn.text)
            if clean.isEmpty {
                thinkingRow
            } else {
                MarkdownView(text: clean)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("思考中…").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var copiedToast: some View {
        Text("已复制")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor, in: Capsule())
            .padding(10)
            .transition(.movingParts.pop(Color.accentColor))
    }
}

// MARK: - 尺寸测量辅助

/// 测量整块内容的总高度,回调给窗口控制器动画调整面板高度。
private struct HeightReader: View {
    var onChange: (CGFloat) -> Void
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.height, initial: true) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

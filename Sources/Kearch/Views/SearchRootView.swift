import SwiftUI

/// 面板内容:顶部搜索框 + 回车后向下展开的结果区。
struct SearchRootView: View {
    @ObservedObject var viewModel: SearchViewModel
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @FocusState private var focused: Bool
    @State private var resultContentHeight: CGFloat = 0

    private let width: CGFloat = 680
    private let maxResultHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if viewModel.isExpanded {
                Divider().opacity(0.35)
                resultArea
                    .transition(.move(edge: .top).combined(with: .opacity))
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
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("问点什么…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($focused)
                .onSubmit { viewModel.submit() }

            if viewModel.isBusy {
                ProgressView().controlSize(.small)
            } else if viewModel.commandDown && viewModel.canCopy {
                copyHint
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var copyHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "command").font(.system(size: 10, weight: .semibold))
            Text("↩ 复制").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .transition(.opacity)
    }

    // MARK: - 结果区

    private var resultArea: some View {
        ScrollView {
            resultContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .frame(height: min(max(resultContentHeight, 1), maxResultHeight))
        .onPreferenceChange(ContentHeightKey.self) { resultContentHeight = $0 }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.showCopied { copiedToast }
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch viewModel.phase {
        case .error(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .loading:
            thinkingRow
        default:
            if !viewModel.displayText.isEmpty {
                MarkdownView(text: viewModel.displayText)
            } else if viewModel.isBusy {
                thinkingRow
            } else {
                Text("(无文本内容)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
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
            .transition(.opacity.combined(with: .scale))
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

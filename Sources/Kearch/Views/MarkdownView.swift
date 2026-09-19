import SwiftUI
import MarkdownUI

/// 完整 Markdown 渲染:基于 MarkdownUI(cmark-gfm),支持 GFM 全集——
/// 标题 / 段落 / 有序·无序·任务列表 / 引用块 / 表格 / 围栏代码块(语法高亮)/
/// 删除线 / 链接 / 图片 / 内联样式 等。
struct MarkdownView: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.kearch)
            .textSelection(.enabled)
    }
}

private extension Theme {
    /// 适配迷你结果面板的紧凑主题:基于 GitHub 主题,略微收紧字号与间距。
    static let kearch = Theme.gitHub
        .text {
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12.5)
        }
        .heading1 { config in
            config.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(20) }
                .markdownMargin(top: 8, bottom: 6)
        }
        .heading2 { config in
            config.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(17) }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading3 { config in
            config.label
                .markdownTextStyle { FontWeight(.semibold); FontSize(15) }
                .markdownMargin(top: 6, bottom: 4)
        }
}

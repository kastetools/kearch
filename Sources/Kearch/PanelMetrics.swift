import CoreGraphics

/// 由「面板尺寸」滑杆(0–100)映射出唤起窗口的宽度与结果区最大高度。
/// 默认 50 对应宽 680 / 最大高 420(与历史手感一致)。
enum PanelMetrics {
    private static func clamped(_ scale: Int) -> CGFloat {
        CGFloat(min(100, max(0, scale)))
    }

    /// 宽度:540(0)– 680(50)– 820(100)。
    static func width(scale: Int) -> CGFloat {
        540 + 2.8 * clamped(scale)
    }

    /// 结果区最大高度:300(0)– 420(50)– 540(100)。
    static func maxResultHeight(scale: Int) -> CGFloat {
        300 + 2.4 * clamped(scale)
    }
}

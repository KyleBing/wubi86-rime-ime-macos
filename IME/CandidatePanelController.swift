import AppKit

/// 系统风格朴素候选条：支持横向 / 纵向、可配置字号
/// 内容排版与设置页预览共用 CandidateBarLayout，窗口尺寸直接取自动布局结果。
final class CandidatePanelController {
    private let panel: NSPanel
    private let chrome: RoundedChromeView
    private let stack = NSStackView()
    // 内容相对圆角背景的内边距，保证留白画在背景内侧。
    private var paddingConstraints: (top: NSLayoutConstraint, bottom: NSLayoutConstraint, leading: NSLayoutConstraint, trailing: NSLayoutConstraint)!
    private var onSelect: ((Int) -> Void)?
    private var lastCandidates: [String] = []
    private var lastPreedit = ""
    private var lastCaretRect = NSRect.zero

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 系统阴影不可调参数，改由 RoundedChromeView 按皮肤绘制。
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // 关键：不成为 key window，避免 Finder sheet 后焦点丢失
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        // 默认进出场会把窗口缩放淡入，缩放过程中文字被拉糊。
        panel.animationBehavior = .none

        chrome = RoundedChromeView(frame: panel.contentView?.bounds ?? .zero)
        chrome.autoresizingMask = [.width, .height]
        panel.contentView = chrome
        paddingConstraints = CandidateBarLayout.pin(stack, in: chrome)

        DistributedNotificationCenter.default().addObserver(
            forName: IMEAppearancePrefs.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshIfVisible()
        }
        chrome.onAppearanceChange = { [weak self] in
            guard let self else { return }
            CandidateBarLayout.updateTextColors(
                in: self.stack,
                colors: IMEAppearancePrefs.skin.colors(for: self.chrome.effectiveAppearance)
            )
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func show(candidates: [String], preedit: String, caretRect: NSRect, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        lastCandidates = candidates
        lastPreedit = preedit
        lastCaretRect = caretRect
        // 「不显示」模式只保留编码下划线，选词按键仍由输入控制器处理。
        guard !IMEAppearancePrefs.hideCandidatePanel else {
            panel.orderOut(nil)
            return
        }
        render()
        // 已在屏幕上时重复 orderFront 会再播一次出现动画。
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel.orderOut(nil)
        onSelect = nil
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    var isVisible: Bool { panel.isVisible }

    // 设置变更时，若候选窗正在显示则按新皮肤重排。
    private func refreshIfVisible() {
        guard panel.isVisible else { return }
        if IMEAppearancePrefs.hideCandidatePanel {
            panel.orderOut(nil)
            return
        }
        render()
    }

    // 重建内容 → 取自动布局真实尺寸 → 按可见圆角条贴齐光标。
    private func render() {
        chrome.applySkin()
        let colors = IMEAppearancePrefs.skin.colors(for: chrome.effectiveAppearance)
        CandidateBarLayout.populate(
            stack,
            padding: paddingConstraints,
            candidates: lastCandidates,
            preedit: lastPreedit,
            colors: colors,
            onSelect: { [weak self] idx in self?.onSelect?(idx) }
        )
        // fittingSize 已包含内边距与阴影占位，与预览同一套约束，尺寸不会再有额外空白。
        chrome.layoutSubtreeIfNeeded()
        let fitted = chrome.fittingSize
        let size = NSSize(width: ceil(fitted.width), height: ceil(fitted.height))
        // 一次设好尺寸和位置，并关掉帧动画，避免改大小时整窗被插值缩放。
        let origin = panelOrigin(width: size.width, height: size.height, below: lastCaretRect)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        NSAnimationContext.endGrouping()
    }

    /// 按可见圆角条（不含阴影占位）贴齐光标；offsetTop / offsetLeft 可调。
    private func panelOrigin(width: CGFloat, height: CGFloat, below anchor: NSRect) -> NSPoint {
        let skin = IMEAppearancePrefs.skin
        let shadow = chrome.shadowOutset
        let gapY = CGFloat(skin.offsetTop)
        let gapX = CGFloat(skin.offsetLeft)
        // 阴影占位在窗口四周，定位时扣掉：可见条左上角 = (光标左 + gapX, 光标底 - gapY)。
        var x = anchor.minX + gapX - shadow
        var y = anchor.minY - gapY - (height - shadow)

        let anchorPoint = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if y + shadow < visible.minY {
                // 下方放不下时翻到光标上方：可见条底边在光标顶上方 gapY。
                y = min(anchor.maxY + gapY - shadow, visible.maxY - height + shadow)
            }
            x = min(max(x, visible.minX - shadow), visible.maxX - width + shadow)
            y = max(y, visible.minY - shadow)
        }
        return NSPoint(x: x, y: y)
    }
}

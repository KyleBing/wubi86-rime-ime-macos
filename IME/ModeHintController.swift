import AppKit

/// 光标旁短暂出现的中/英模式胶囊：输入框聚焦出现光标时，或单独按 Shift 切换时显示。
final class ModeHintController {
    private let panel: NSPanel
    private let chrome = ModeHintChrome()
    private var dismissWork: DispatchWorkItem?
    // 淡出动画的完成回调在输入法进程里经常不执行，用它强制收掉窗口。
    private var forceHideWork: DispatchWorkItem?
    // 每次显示递增，避免上一次淡出把新提示关掉。
    private var generation = 0

    init() {
        // 一开始就用胶囊尺寸，避免第一次显示从矮窗口拉高后圆角仍停在旧高度。
        let size = chrome.preferredSize(label: Self.label(asciiMode: false, capsLock: false))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // 只是提示，不能挡住底下的点击。
        panel.ignoresMouseEvents = true
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        chrome.autoresizingMask = [.width, .height]
        panel.contentView = chrome
    }

    deinit {
        dismissWork?.cancel()
        forceHideWork?.cancel()
        // 控制器释放后 AppKit 仍可能留着已显示的面板。
        panel.orderOut(nil)
    }

    /// 胶囊文字：大写锁定优先于中英，锁定时一直显示「大写」。
    static func label(asciiMode: Bool, capsLock: Bool) -> String {
        if capsLock { return "大写" }
        return asciiMode ? "英文" : "中文"
    }

    /// 在光标旁显示当前模式，约一秒后淡出。左、上间距与候选条相同。
    func show(asciiMode: Bool, capsLock: Bool, caretRect: NSRect) {
        generation += 1
        let token = generation
        dismissWork?.cancel()
        forceHideWork?.cancel()

        let label = Self.label(asciiMode: asciiMode, capsLock: capsLock)
        chrome.setMode(label: label)
        let size = chrome.preferredSize(label: label)
        let origin = origin(width: size.width, height: size.height, near: caretRect)

        panel.setFrame(NSRect(origin: origin, size: size), display: false, animate: false)
        // 先把约束落到最终高度，再按胶囊半径画圆角，避免用到拉伸前的 bounds。
        chrome.layoutSubtreeIfNeeded()
        chrome.applyCapsuleShape()
        panel.displayIfNeeded()

        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut(token: token)
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)

        // 约 0.9 秒显示 + 0.28 秒淡出；到点无论动画有没有结束都关掉。
        let force = DispatchWorkItem { [weak self] in
            self?.forceHide(token: token)
        }
        forceHideWork = force
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: force)
    }

    // 开始打字、会话结束或弹出候选时立刻收起，避免挡住编码，也避免切走后还留在屏幕上。
    func hide() {
        generation += 1
        dismissWork?.cancel()
        forceHideWork?.cancel()
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    private func fadeOut(token: Int) {
        guard token == generation, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.forceHide(token: token)
        })
    }

    // 不依赖动画回调，直接把这一轮提示从屏幕上拿掉。
    private func forceHide(token: Int) {
        guard token == generation else { return }
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    // 可见胶囊左上角按候选条的左、上间距贴齐光标；贴底时翻到光标上方。
    private func origin(width: CGFloat, height: CGFloat, near anchor: NSRect) -> NSPoint {
        let skin = IMEAppearancePrefs.skin
        let shadow = chrome.shadowOutset
        let gapY = CGFloat(skin.offsetTop)
        let gapX = CGFloat(skin.offsetLeft)
        var x = anchor.minX + gapX - shadow
        var y = anchor.minY - gapY - (height - shadow)

        let anchorPoint = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if y + shadow < visible.minY {
                y = min(anchor.maxY + gapY - shadow, visible.maxY - height + shadow)
            }
            x = min(max(x, visible.minX - shadow), visible.maxX - width + shadow)
            y = max(y, visible.minY - shadow)
        }
        return NSPoint(x: x, y: y)
    }
}

/// 小字圆角胶囊；文字颜色跟候选词，其余保持最初那版的紧凑样式。
private final class ModeHintChrome: NSView {
    private let shadowHost = NSView()
    private let fill = NSView()
    private let title = NSTextField(labelWithString: "中文")
    private let shadowOutsetValue: CGFloat = 14
    // 可见胶囊的高度；圆角用这个值，不跟首次布局时可能还没拉高的 bounds。
    private let contentHeight: CGFloat = 28

    var shadowOutset: CGFloat { shadowOutsetValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor

        shadowHost.wantsLayer = true
        shadowHost.clipsToBounds = false
        shadowHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shadowHost)

        fill.wantsLayer = true
        fill.layer?.masksToBounds = true
        fill.translatesAutoresizingMaskIntoConstraints = false
        shadowHost.addSubview(fill)

        title.translatesAutoresizingMaskIntoConstraints = false
        fill.addSubview(title)

        let inset = shadowOutsetValue
        NSLayoutConstraint.activate([
            shadowHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            shadowHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            shadowHost.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            shadowHost.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),

            fill.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            fill.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            fill.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),

            title.leadingAnchor.constraint(equalTo: fill.leadingAnchor, constant: 11),
            title.trailingAnchor.constraint(equalTo: fill.trailingAnchor, constant: -11),
            title.centerYAnchor.constraint(equalTo: fill.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 按文字实测宽度定窗口，避免外层约束把自适应尺寸算成 0。
    func preferredSize(label: String) -> NSSize {
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: Self.labelFont]).width)
        let contentWidth = textWidth + 22
        let pad = shadowOutsetValue * 2
        return NSSize(width: contentWidth + pad, height: contentHeight + pad)
    }

    // 固定小字，不跟着候选字号变大。
    private static var labelFont: NSFont {
        .systemFont(ofSize: 13, weight: .medium)
    }

    override func layout() {
        super.layout()
        applyCapsuleShape()
    }

    // 圆角取设计高度的一半。首次显示时 bounds 可能仍是拉伸前的矮高度，用它会变成圆角矩形。
    func applyCapsuleShape() {
        let radius = contentHeight / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowHost.layer?.cornerRadius = radius
        fill.layer?.cornerRadius = radius
        if #available(macOS 10.15, *) {
            shadowHost.layer?.cornerCurve = .continuous
            fill.layer?.cornerCurve = .continuous
        }
        CATransaction.commit()
    }

    func setMode(label: String) {
        let colors = IMEAppearancePrefs.skin.colors(for: effectiveAppearance)
        let background = colors.background.nsColor

        title.stringValue = label
        title.font = Self.labelFont
        title.textColor = colors.candidateText.nsColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowHost.layer?.backgroundColor = background.cgColor
        fill.layer?.backgroundColor = background.cgColor
        fill.layer?.borderWidth = 0
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadowHost.shadow = shadow
        CATransaction.commit()
        needsLayout = true
    }
}

import AppKit

/// 系统风格朴素候选条：支持横向 / 纵向、可配置字号
final class CandidatePanelController {
    private let panel: NSPanel
    private let chrome: RoundedChromeView
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var heightConstraint: NSLayoutConstraint?
    private var onSelect: ((Int) -> Void)?

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
        // 交给 Window Server 绘制阴影，透明圆角窗口可获得系统浮窗效果
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // 关键：不成为 key window，避免 Finder sheet 后焦点丢失
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        chrome = RoundedChromeView(frame: panel.contentView?.bounds ?? .zero)
        chrome.autoresizingMask = [.width, .height]
        panel.contentView = chrome

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        // 上下对称，与预览一致
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        chrome.effectView.addSubview(scroll)

        let h = scroll.heightAnchor.constraint(equalToConstant: 36)
        heightConstraint = h
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: chrome.effectView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: chrome.effectView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: chrome.effectView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: chrome.effectView.bottomAnchor),
            h
        ])

        DistributedNotificationCenter.default().addObserver(
            forName: IMEAppearancePrefs.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearance()
        }
        applyAppearance()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func applyAppearance() {
        let vertical = IMEAppearancePrefs.orientation == .vertical
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        scroll.hasVerticalScroller = vertical
        scroll.hasHorizontalScroller = !vertical
    }

    func show(candidates: [String], preedit: String, caretRect: NSRect, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        applyAppearance()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let fontSize = CGFloat(IMEAppearancePrefs.fontSize)
        let vertical = IMEAppearancePrefs.orientation == .vertical
        let showPreedit = IMEAppearancePrefs.showPreeditInPanel
        let showIndex = IMEAppearancePrefs.showIndex
        let rowHeight = ceil(fontSize * 1.35)

        if showPreedit, !preedit.isEmpty {
            let label = makeLabel(preedit, bold: true, index: nil, fontSize: fontSize, rowHeight: rowHeight)
            stack.addArrangedSubview(label)
            let sep = NSBox()
            sep.boxType = .separator
            sep.translatesAutoresizingMaskIntoConstraints = false
            if vertical {
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                sep.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
            } else {
                sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
                sep.heightAnchor.constraint(equalToConstant: rowHeight - 4).isActive = true
            }
            stack.addArrangedSubview(sep)
        }

        for (i, text) in candidates.enumerated() {
            let title = showIndex ? "\(i + 1). \(text)" : text
            let row = makeLabel(title, bold: false, index: i, fontSize: fontSize, rowHeight: rowHeight)
            stack.addArrangedSubview(row)
        }

        stack.layoutSubtreeIfNeeded()
        let fitted = stack.fittingSize
        // 与预览一致，避免多出一截空白被 ScrollView 顶到首行上方
        let pad: CGFloat = 4
        if vertical {
            let width = min(max(fitted.width + pad, 120), 360)
            let height = min(max(fitted.height + pad, rowHeight + 10), 480)
            heightConstraint?.constant = height
            panel.setContentSize(NSSize(width: width, height: height))
            pinDocumentToTop()
            positionPanel(width: width, height: height, below: caretRect)
        } else {
            let width = min(max(fitted.width + pad, 120), 720)
            let height = max(rowHeight + 10, 30)
            heightConstraint?.constant = height
            panel.setContentSize(NSSize(width: width, height: height))
            pinDocumentToTop()
            positionPanel(width: width, height: height, below: caretRect)
        }
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        onSelect = nil
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    var isVisible: Bool { panel.isVisible }

    /// 默认放在编码正下方；屏幕底部空间不足时翻到输入行上方
    private func positionPanel(width: CGFloat, height: CGFloat, below anchor: NSRect) {
        let gap: CGFloat = 6
        var x = anchor.minX
        var y = anchor.minY - height - gap

        let anchorPoint = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if y < visible.minY {
                y = min(anchor.maxY + gap, visible.maxY - height)
            }
            x = min(max(x, visible.minX), visible.maxX - width)
            y = max(y, visible.minY)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// ScrollView 文档默认贴底，竖直时多出的高度会堆在首行上方；改为贴顶
    private func pinDocumentToTop() {
        scroll.layoutSubtreeIfNeeded()
        guard let doc = scroll.documentView else { return }
        var frame = doc.frame
        let clip = scroll.contentView.bounds
        frame.size.width = max(frame.width, clip.width)
        if scroll.contentView.isFlipped {
            frame.origin = .zero
        } else {
            frame.origin = NSPoint(x: 0, y: clip.height - frame.height)
        }
        doc.frame = frame
    }

    /// 用 TextField 垂直居中，避免 NSButton 标题偏下
    private func makeLabel(_ text: String, bold: Bool, index: Int?, fontSize: CGFloat, rowHeight: CGFloat) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = IMEAppearancePrefs.candidateFont(size: fontSize, bold: bold)
        field.textColor = .labelColor
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.alignment = .left
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.translatesAutoresizingMaskIntoConstraints = false

        let box = CandidateHitView(frame: .zero)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(field)
        // 汉字光学中心略偏上，centerY 再上移 0.5pt
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: box.centerYAnchor, constant: 0.5),
            box.heightAnchor.constraint(equalToConstant: rowHeight)
        ])

        if let index {
            box.candidateIndex = index
            box.onClick = { [weak self] idx in
                self?.onSelect?(idx)
            }
        }
        return box
    }
}

/// 可点击候选行（NSTextField 本身不好点选）
private final class CandidateHitView: NSView {
    var candidateIndex: Int = -1
    var onClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if candidateIndex >= 0 {
            onClick?(candidateIndex)
        }
    }

    override func resetCursorRects() {
        if candidateIndex >= 0 {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

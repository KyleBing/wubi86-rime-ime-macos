import AppKit

/// 系统风格朴素候选条：支持横向 / 纵向、可配置字号
final class CandidatePanelController {
    private let panel: NSPanel
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
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // 关键：不成为 key window，避免 Finder sheet 后焦点丢失
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let root = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        root.material = .menu
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 8
        root.autoresizingMask = [.width, .height]
        panel.contentView = root

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        let h = scroll.heightAnchor.constraint(equalToConstant: 36)
        heightConstraint = h
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
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

    func show(candidates: [String], preedit: String, origin: NSPoint, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        applyAppearance()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let fontSize = CGFloat(IMEAppearancePrefs.fontSize)
        let vertical = IMEAppearancePrefs.orientation == .vertical
        let showPreedit = IMEAppearancePrefs.showPreeditInPanel
        let showIndex = IMEAppearancePrefs.showIndex

        if showPreedit, !preedit.isEmpty {
            let label = makeLabel(preedit, bold: true, index: nil, fontSize: fontSize)
            stack.addArrangedSubview(label)
            let sep = NSBox()
            sep.boxType = .separator
            sep.translatesAutoresizingMaskIntoConstraints = false
            if vertical {
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                sep.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
            } else {
                sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
                sep.heightAnchor.constraint(equalToConstant: fontSize + 4).isActive = true
            }
            stack.addArrangedSubview(sep)
        }

        for (i, text) in candidates.enumerated() {
            let title = showIndex ? "\(i + 1). \(text)" : text
            let row = makeLabel(title, bold: false, index: i, fontSize: fontSize)
            stack.addArrangedSubview(row)
        }

        stack.layoutSubtreeIfNeeded()
        let fitted = stack.fittingSize
        let pad: CGFloat = 16
        if vertical {
            let width = min(max(fitted.width + pad, 120), 360)
            let height = min(max(fitted.height + pad, fontSize + 16), 480)
            heightConstraint?.constant = height
            panel.setContentSize(NSSize(width: width, height: height))
            // 纵向：插在插入点右侧略偏上
            panel.setFrameOrigin(NSPoint(x: origin.x + 8, y: origin.y - height + 8))
        } else {
            let width = min(max(fitted.width + pad, 120), 720)
            let height = max(fontSize + 16, 32)
            heightConstraint?.constant = height
            panel.setContentSize(NSSize(width: width, height: height))
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - height - 6))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        onSelect = nil
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    var isVisible: Bool { panel.isVisible }

    private func makeLabel(_ text: String, bold: Bool, index: Int?, fontSize: CGFloat) -> NSView {
        let button = NSButton(title: text, target: self, action: #selector(click(_:)))
        button.isBordered = false
        // 使用用户在输入法设置里选的字体 / 字号
        button.font = IMEAppearancePrefs.candidateFont(size: fontSize, bold: bold)
        button.contentTintColor = .labelColor
        button.alignment = .left
        if let index {
            button.tag = index
        } else {
            button.isEnabled = false
        }
        return button
    }

    @objc private func click(_ sender: NSButton) {
        onSelect?(sender.tag)
    }
}

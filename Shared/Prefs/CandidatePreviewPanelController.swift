import AppKit

/// 独立浮窗预览候选条：随设置实时刷新，宽度/高度按内容自适应（9 个候选会变宽）
final class CandidatePreviewPanelController {
    static let shared = CandidatePreviewPanelController()

    private let panel: NSPanel
    private let chrome: RoundedChromeView
    private let stack = NSStackView()
    private var observers: [NSObjectProtocol] = []
    private var shown = false
    private weak var anchorWindow: NSWindow?

    private static let samplePreedit = "ww"
    private static let sampleCandidates = ["五", "吾", "伍", "捂", "梧", "妩", "坞", "晤", "勿"]

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 使用与实际候选窗一致的系统圆角阴影
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.title = "候选预览"

        chrome = RoundedChromeView(frame: .zero)
        chrome.autoresizingMask = [.width, .height]
        panel.contentView = chrome

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        chrome.effectView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: chrome.effectView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: chrome.effectView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: chrome.effectView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: chrome.effectView.bottomAnchor)
        ])

        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(
            forName: IMEAppearancePrefs.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadIfVisible()
        })
        observers.append(center.addObserver(
            forName: RimeBehaviorPrefs.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadIfVisible()
        })
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
    }

    /// 打开设置时显示；可相对设置窗口定位（默认在左侧）
    func show(near settingsWindow: NSWindow? = nil) {
        shown = true
        if let settingsWindow {
            anchorWindow = settingsWindow
        }
        reload()
        position(near: anchorWindow)
        panel.orderFrontRegardless()
    }

    func hide() {
        shown = false
        panel.orderOut(nil)
    }

    func reloadIfVisible() {
        guard shown else { return }
        reload()
        // 宽度变化后仍贴在设置窗左侧
        position(near: anchorWindow)
    }

    /// 按当前偏好重绘并缩放到内容尺寸
    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let fontSize = CGFloat(IMEAppearancePrefs.fontSize)
        let vertical = IMEAppearancePrefs.orientation == .vertical
        let showPreedit = IMEAppearancePrefs.showPreeditInPanel
        let showIndex = IMEAppearancePrefs.showIndex
        let pageSize = RimeBehaviorPrefs.pageSize
        let rowHeight = ceil(fontSize * 1.35)

        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY

        if showPreedit {
            stack.addArrangedSubview(makeLabel(Self.samplePreedit, bold: true, fontSize: fontSize, rowHeight: rowHeight))
            let sep = NSBox()
            sep.boxType = .separator
            sep.translatesAutoresizingMaskIntoConstraints = false
            if vertical {
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                sep.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
            } else {
                sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
                sep.heightAnchor.constraint(equalToConstant: max(rowHeight - 4, 12)).isActive = true
            }
            stack.addArrangedSubview(sep)
        }

        let items = Array(Self.sampleCandidates.prefix(pageSize))
        for (i, text) in items.enumerated() {
            let title = showIndex ? "\(i + 1). \(text)" : text
            stack.addArrangedSubview(makeLabel(title, bold: false, fontSize: fontSize, rowHeight: rowHeight))
        }

        stack.layoutSubtreeIfNeeded()
        let fitted = stack.fittingSize
        // 内容变宽/变高时面板跟着变（9 个候选横向会明显变宽）
        let pad: CGFloat = 4
        let width = min(max(fitted.width + pad, 140), 900)
        let height = min(max(fitted.height + pad, rowHeight + 10), 560)
        panel.setContentSize(NSSize(width: width, height: height))
        panel.invalidateShadow()
    }

    private func position(near settingsWindow: NSWindow?) {
        if let win = settingsWindow {
            let f = win.frame
            // 放在设置窗左侧，顶部与标题栏下沿大致对齐
            let gap: CGFloat = 12
            let x = f.origin.x - panel.frame.width - gap
            let y = f.origin.y + f.height - panel.frame.height - 28
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            let origin = NSPoint(
                x: vis.midX - panel.frame.width - 40,
                y: vis.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(origin)
        }
    }

    private func makeLabel(_ text: String, bold: Bool, fontSize: CGFloat, rowHeight: CGFloat) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = IMEAppearancePrefs.candidateFont(size: fontSize, bold: bold)
        field.textColor = .labelColor
        field.drawsBackground = false
        field.isBezeled = false
        field.alignment = .left
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: box.centerYAnchor, constant: 0.5),
            box.heightAnchor.constraint(equalToConstant: rowHeight)
        ])
        return box
    }
}

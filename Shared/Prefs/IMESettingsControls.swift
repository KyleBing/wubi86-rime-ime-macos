import AppKit

/// App、输入法偏好窗口和系统偏好面板共用的设置界面。
enum IMESettingsControls {
    static let preferredWindowSize = NSSize(width: 900, height: 560)
    static let minWindowSize = NSSize(width: 720, height: 460)

    static let preferredFonts: [(name: String, title: String)] = [
        ("", "系统默认"),
        ("PingFang SC", "苹方"),
        ("Heiti SC", "黑体"),
        ("Songti SC", "宋体"),
        ("Kaiti SC", "楷体"),
        ("STSong", "华文宋体"),
        ("Hiragino Sans GB", "冬青黑体")
    ]

    static func makeFormView(size: NSSize = preferredWindowSize) -> NSView {
        SettingsRootView(frame: NSRect(origin: .zero, size: size))
    }

    static func makeFormView(width: CGFloat) -> NSView {
        makeFormView(size: NSSize(width: width, height: preferredWindowSize.height))
    }
}

/// 左侧栏目保持稳定，后续可直接增加登录、同步等设置页。
private final class SettingsRootView: NSView {
    private enum Section: Int, CaseIterable {
        case candidate
        case keyboard
        case account

        var title: String {
            switch self {
            case .candidate: return "候选栏"
            case .keyboard: return "按键"
            case .account: return "账户"
            }
        }

        var symbolName: String {
            switch self {
            case .candidate: return "text.bubble"
            case .keyboard: return "keyboard"
            case .account: return "person.crop.circle"
            }
        }
    }

    private let content = NSView()
    private var sectionButtons: [NSButton] = []
    private var currentSection = Section.candidate

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        show(.candidate)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = makeSidebar()
        sidebar.widthAnchor.constraint(equalToConstant: 184).isActive = true
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(content)

        addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: leadingAnchor),
            split.trailingAnchor.constraint(equalTo: trailingAnchor),
            split.topAnchor.constraint(equalTo: topAnchor),
            split.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeSidebar() -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active

        let icon = NSImageView()
        icon.image = BrandIcon.settingsImage()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44)
        ])

        let title = NSTextField(labelWithString: "玫枫五笔")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "输入法设置")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let nameStack = NSStackView(views: [title, subtitle])
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 1

        let brand = NSStackView(views: [icon, nameStack])
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 10

        let navigation = NSStackView()
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 4

        for section in Section.allCases {
            let button = NSButton(
                title: section.title,
                image: NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title) ?? NSImage(),
                target: self,
                action: #selector(selectSection(_:))
            )
            button.tag = section.rawValue
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.bezelStyle = .recessed
            button.setButtonType(.toggle)
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 152).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            navigation.addArrangedSubview(button)
            sectionButtons.append(button)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        let version = NSTextField(labelWithString: "本地设置自动保存")
        version.font = .systemFont(ofSize: 10)
        version.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [brand, navigation, spacer, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        return effect
    }

    @objc private func selectSection(_ sender: NSButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        show(section)
    }

    private func show(_ section: Section) {
        currentSection = section
        for button in sectionButtons {
            button.state = button.tag == section.rawValue ? .on : .off
        }

        content.subviews.forEach { $0.removeFromSuperview() }
        let page: NSView
        switch section {
        case .candidate:
            page = makeCandidatePage()
        case .keyboard:
            page = makeKeyboardPage()
        case .account:
            page = makeAccountPage()
        }
        page.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            page.topAnchor.constraint(equalTo: content.topAnchor),
            page.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    private func makeCandidatePage() -> NSView {
        let settings = NSStackView()
        settings.orientation = .vertical
        settings.alignment = .leading
        settings.spacing = 14

        let orientation = NSSegmentedControl(
            labels: IMEAppearancePrefs.Orientation.allCases.map(\.title),
            trackingMode: .selectOne,
            target: OrientationTarget.shared,
            action: #selector(OrientationTarget.changed(_:))
        )
        orientation.selectedSegment = IMEAppearancePrefs.orientation == .horizontal ? 0 : 1
        settings.addArrangedSubview(formRow("排列方向", orientation))

        let font = NSPopUpButton(frame: .zero, pullsDown: false)
        for item in IMESettingsControls.preferredFonts {
            font.addItem(withTitle: item.title)
            font.lastItem?.representedObject = item.name
        }
        font.selectItem(at: IMESettingsControls.preferredFonts.firstIndex(where: {
            $0.name == IMEAppearancePrefs.fontName
        }) ?? 0)
        font.target = FontTarget.shared
        font.action = #selector(FontTarget.changed(_:))
        font.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        settings.addArrangedSubview(formRow("候选字体", font))

        let slider = NSSlider(
            value: IMEAppearancePrefs.fontSize,
            minValue: 11,
            maxValue: 24,
            target: FontSizeTarget.shared,
            action: #selector(FontSizeTarget.changed(_:))
        )
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let sizeValue = NSTextField(labelWithString: "\(Int(IMEAppearancePrefs.fontSize))")
        sizeValue.alignment = .right
        sizeValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sizeValue.widthAnchor.constraint(equalToConstant: 26).isActive = true
        FontSizeTarget.shared.valueLabel = sizeValue
        settings.addArrangedSubview(formRow("字体大小", slider, sizeValue))

        let preedit = NSButton(
            checkboxWithTitle: "在候选条内显示编码",
            target: ToggleTarget.shared,
            action: #selector(ToggleTarget.preeditChanged(_:))
        )
        preedit.state = IMEAppearancePrefs.showPreeditInPanel ? .on : .off
        settings.addArrangedSubview(preedit)

        let index = NSButton(
            checkboxWithTitle: "显示候选序号",
            target: ToggleTarget.shared,
            action: #selector(ToggleTarget.indexChanged(_:))
        )
        index.state = IMEAppearancePrefs.showIndex ? .on : .off
        settings.addArrangedSubview(index)

        let pageValue = NSTextField(labelWithString: "\(RimeBehaviorPrefs.pageSize)")
        pageValue.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let stepper = NSStepper()
        stepper.minValue = 3
        stepper.maxValue = 9
        stepper.integerValue = RimeBehaviorPrefs.pageSize
        stepper.target = PageTarget.shared
        stepper.action = #selector(PageTarget.changed(_:))
        PageTarget.shared.valueLabel = pageValue
        settings.addArrangedSubview(formRow("每页候选数", pageValue, stepper))

        let settingsCard = card(title: "显示", subtitle: "调整候选窗口的布局和文字", content: settings)
        // 预览尺寸变化时，左侧设置列保持固定，不参与横向挤压。
        settingsCard.widthAnchor.constraint(equalToConstant: 330).isActive = true
        settingsCard.setContentHuggingPriority(.required, for: .horizontal)
        settingsCard.setContentCompressionResistancePriority(.required, for: .horizontal)

        let preview = CandidateInlinePreviewView()
        let previewCard = card(
            title: "实时预览",
            subtitle: "效果会同步应用到实际候选窗口",
            content: preview
        )
        previewCard.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        previewCard.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let columns = NSStackView(views: [settingsCard, previewCard])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fill
        columns.spacing = 18
        return page(
            title: "候选栏",
            subtitle: "使用系统控件调整候选栏外观，修改会立即保存。",
            content: columns
        )
    }

    private func makeKeyboardPage() -> NSView {
        let settings = NSStackView()
        settings.orientation = .vertical
        settings.alignment = .leading
        settings.spacing = 14

        let paging = NSPopUpButton(frame: .zero, pullsDown: false)
        for item in RimeBehaviorPrefs.PagingKeys.allCases {
            paging.addItem(withTitle: item.title)
            paging.lastItem?.representedObject = item.rawValue
        }
        paging.selectItem(at: RimeBehaviorPrefs.PagingKeys.allCases.firstIndex(
            of: RimeBehaviorPrefs.pagingKeys
        ) ?? 0)
        paging.target = PagingTarget.shared
        paging.action = #selector(PagingTarget.changed(_:))
        paging.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        settings.addArrangedSubview(formRow("翻页键", paging))

        let secondThird = NSPopUpButton(frame: .zero, pullsDown: false)
        for item in RimeBehaviorPrefs.SecondThirdKeys.allCases {
            secondThird.addItem(withTitle: item.title)
            secondThird.lastItem?.representedObject = item.rawValue
        }
        secondThird.selectItem(at: RimeBehaviorPrefs.SecondThirdKeys.allCases.firstIndex(
            of: RimeBehaviorPrefs.secondThirdKeys
        ) ?? 0)
        secondThird.target = SecondThirdTarget.shared
        secondThird.action = #selector(SecondThirdTarget.changed(_:))
        secondThird.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        settings.addArrangedSubview(formRow("二三候选", secondThird))

        let note = NSTextField(wrappingLabelWithString: "按键设置会写入 Rime 配置，并在输入法下次处理按键时自动生效。")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        note.preferredMaxLayoutWidth = 420
        settings.addArrangedSubview(note)

        return page(
            title: "按键",
            subtitle: "设置翻页方式与快捷选词。",
            content: card(title: "候选按键", subtitle: nil, content: settings)
        )
    }

    private func makeAccountPage() -> NSView {
        let symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: "person.crop.circle.badge.clock", accessibilityDescription: nil)
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)

        let title = NSTextField(labelWithString: "登录与同步")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "账户功能正在准备中。这里将用于登录、词库同步和设备管理。")
        detail.alignment = .center
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = 320

        let stack = NSStackView(views: [symbol, title, detail])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 48, left: 40, bottom: 48, right: 40)
        return page(
            title: "账户",
            subtitle: "为后续的登录与云同步预留。",
            content: card(title: nil, subtitle: nil, content: stack)
        )
    }

    private func page(title: String, subtitle: String, content body: NSView) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        let detail = NSTextField(wrappingLabelWithString: subtitle)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [heading, detail, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(24, after: detail)
        stack.edgeInsets = NSEdgeInsets(top: 26, left: 28, bottom: 26, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // 内容填满可用宽度，同时保留左右各 28 pt 的窗口边距。
        body.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -56).isActive = true

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        // AppKit 默认文档坐标从底部开始；使用 flipped 容器让设置始终靠左上排列。
        let document = TopAlignedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        return scroll
    }

    private func card(title: String?, subtitle: String?, content body: NSView) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.contentViewMargins = NSSize(width: 18, height: 16)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            stack.addArrangedSubview(label)
        }
        if let subtitle {
            let label = NSTextField(wrappingLabelWithString: subtitle)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
            stack.setCustomSpacing(16, after: label)
        }
        stack.addArrangedSubview(body)
        box.contentView = stack
        return box
    }

    private func formRow(_ title: String, _ controls: NSView...) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 82).isActive = true
        let row = NSStackView(views: [label] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }
}

/// 滚动区域采用从上向下的坐标系，避免短内容垂直居中或贴底。
private final class TopAlignedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// 嵌入设置页右侧的候选栏预览。
private final class CandidateInlinePreviewView: NSView {
    private let chrome = RoundedChromeView(frame: .zero)
    private let candidates = NSStackView()
    private var observers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8

        chrome.translatesAutoresizingMaskIntoConstraints = false
        candidates.translatesAutoresizingMaskIntoConstraints = false
        chrome.effectView.addSubview(candidates)
        addSubview(chrome)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 264),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
            chrome.centerXAnchor.constraint(equalTo: centerXAnchor),
            chrome.centerYAnchor.constraint(equalTo: centerYAnchor),
            chrome.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            chrome.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            candidates.leadingAnchor.constraint(equalTo: chrome.effectView.leadingAnchor, constant: 10),
            candidates.trailingAnchor.constraint(equalTo: chrome.effectView.trailingAnchor, constant: -10),
            candidates.topAnchor.constraint(equalTo: chrome.effectView.topAnchor, constant: 5),
            candidates.bottomAnchor.constraint(equalTo: chrome.effectView.bottomAnchor, constant: -5)
        ])

        let center = DistributedNotificationCenter.default()
        for name in [IMEAppearancePrefs.didChangeNotification, RimeBehaviorPrefs.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.reload()
            })
        }
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    private func reload() {
        candidates.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let fontSize = CGFloat(IMEAppearancePrefs.fontSize)
        let vertical = IMEAppearancePrefs.orientation == .vertical
        let rowHeight = ceil(fontSize * 1.35)
        candidates.orientation = vertical ? .vertical : .horizontal
        candidates.alignment = vertical ? .leading : .centerY
        candidates.spacing = 6

        if IMEAppearancePrefs.showPreeditInPanel {
            candidates.addArrangedSubview(label("ww", bold: true, size: fontSize, height: rowHeight))
            let separator = NSBox()
            separator.boxType = .separator
            if vertical {
                separator.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
            } else {
                separator.heightAnchor.constraint(equalToConstant: max(12, rowHeight - 4)).isActive = true
            }
            candidates.addArrangedSubview(separator)
        }

        let sample = ["五", "吾", "伍", "捂", "梧", "妩", "坞", "晤", "勿"]
        for (index, word) in sample.prefix(RimeBehaviorPrefs.pageSize).enumerated() {
            let text = IMEAppearancePrefs.showIndex ? "\(index + 1). \(word)" : word
            candidates.addArrangedSubview(label(text, bold: false, size: fontSize, height: rowHeight))
        }
    }

    private func label(_ text: String, bold: Bool, size: CGFloat, height: CGFloat) -> NSView {
        let field = NSTextField(labelWithString: text)
        field.font = IMEAppearancePrefs.candidateFont(size: size, bold: bold)
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.required, for: .horizontal)

        let holder = NSView()
        holder.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            holder.heightAnchor.constraint(equalToConstant: height)
        ])
        return holder
    }
}

// MARK: - Control targets

private final class OrientationTarget: NSObject {
    static let shared = OrientationTarget()
    @objc func changed(_ sender: NSSegmentedControl) {
        IMEAppearancePrefs.orientation = sender.selectedSegment == 0 ? .horizontal : .vertical
    }
}

private final class FontTarget: NSObject {
    static let shared = FontTarget()
    @objc func changed(_ sender: NSPopUpButton) {
        IMEAppearancePrefs.fontName = (sender.selectedItem?.representedObject as? String) ?? ""
    }
}

private final class FontSizeTarget: NSObject {
    static let shared = FontSizeTarget()
    weak var valueLabel: NSTextField?
    @objc func changed(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded()
        IMEAppearancePrefs.fontSize = value
        valueLabel?.stringValue = "\(Int(value))"
    }
}

private final class ToggleTarget: NSObject {
    static let shared = ToggleTarget()
    @objc func preeditChanged(_ sender: NSButton) {
        IMEAppearancePrefs.showPreeditInPanel = sender.state == .on
    }
    @objc func indexChanged(_ sender: NSButton) {
        IMEAppearancePrefs.showIndex = sender.state == .on
    }
}

private final class PageTarget: NSObject {
    static let shared = PageTarget()
    weak var valueLabel: NSTextField?
    @objc func changed(_ sender: NSStepper) {
        RimeBehaviorPrefs.pageSize = sender.integerValue
        valueLabel?.stringValue = "\(sender.integerValue)"
    }
}

private final class PagingTarget: NSObject {
    static let shared = PagingTarget()
    @objc func changed(_ sender: NSPopUpButton) {
        let rawValue = (sender.selectedItem?.representedObject as? String) ?? ""
        if let keys = RimeBehaviorPrefs.PagingKeys(rawValue: rawValue) {
            RimeBehaviorPrefs.pagingKeys = keys
        }
    }
}

private final class SecondThirdTarget: NSObject {
    static let shared = SecondThirdTarget()
    @objc func changed(_ sender: NSPopUpButton) {
        let rawValue = (sender.selectedItem?.representedObject as? String) ?? ""
        if let keys = RimeBehaviorPrefs.SecondThirdKeys(rawValue: rawValue) {
            RimeBehaviorPrefs.secondThirdKeys = keys
        }
    }
}

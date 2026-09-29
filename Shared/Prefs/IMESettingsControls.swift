import AppKit

/// App、输入法偏好窗口和系统偏好面板共用的设置界面。
enum IMESettingsControls {
    static let preferredWindowSize = NSSize(width: 900, height: 560)
    static let minWindowSize = NSSize(width: 720, height: 460)

    /// App / IME 注入：词库目录切换、全量部署与复位（Prefs 面板未注入则相关按钮会提示）。
    struct LexiconActions {
        var deploy: () -> (ok: Bool, message: String)
        var reset: () -> (ok: Bool, message: String)
        var changeDataDirectory: (URL?) -> (ok: Bool, message: String)
        var restartIME: () -> Void
    }

    static var lexiconActions: LexiconActions?

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
        let view = SettingsRootView(frame: NSRect(origin: .zero, size: size))
        // 作为窗口 contentView 时要跟着窗口变高，否则用户词表格不会被拉高。
        view.autoresizingMask = [.width, .height]
        return view
    }

    static func makeFormView(width: CGFloat) -> NSView {
        makeFormView(size: NSSize(width: width, height: preferredWindowSize.height))
    }

    // 跟设置代码所在的包走。系统设置里加载的是预置面板，不是主 App。
    static var versionText: String {
        let info = Bundle(for: SettingsRootView.self).infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "v\(version) (\(build))"
    }
}

/// 左侧栏目保持稳定，后续可直接增加登录、同步等设置页。
private final class SettingsRootView: NSView {
    // 用户词和词库目录放最上面。帮助单独钉在侧栏底部，不进这个顺序。
    private enum Section: Int, CaseIterable {
        case userLexicon
        case lexiconDirectory
        case appearance
        case keyboard
        case punctuation
        case account
        case help

        var title: String {
            switch self {
            case .userLexicon: return "用户词"
            case .lexiconDirectory: return "词库目录"
            case .appearance: return "外观配置"
            case .keyboard: return "按键"
            case .punctuation: return "标点"
            case .account: return "账户"
            case .help: return "帮助"
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "paintpalette"
            case .keyboard: return "keyboard"
            case .punctuation: return "command"
            case .userLexicon: return "book"
            case .lexiconDirectory: return "folder"
            case .help: return "questionmark.circle"
            case .account: return "person.crop.circle"
            }
        }
    }

    private let content = NSView()
    private var sectionButtons: [SidebarSectionButton] = []
    private var currentSection = Section.userLexicon
    // 缓存各页，避免每次点侧栏都重建整页导致卡顿。
    private var pageCache: [Section: NSView] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        show(.userLexicon)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // 选中底色是创建时固化的，亮暗切换后按当前强调色重画。
        updateSidebarSelection(currentSection)
    }

    private func build() {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = makeSidebar()
        sidebar.widthAnchor.constraint(equalToConstant: 184).isActive = true
        split.addArrangedSubview(sidebar)
        content.setContentHuggingPriority(.defaultLow, for: .vertical)
        content.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
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

        for section in Section.allCases where section != .help {
            navigation.addArrangedSubview(makeSectionButton(section))
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        // 帮助固定在侧栏底部，不跟前面的栏目挤在一起。
        let helpButton = makeSectionButton(.help)
        let hint = NSTextField(labelWithString: "本地设置自动保存")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        let version = NSTextField(labelWithString: IMESettingsControls.versionText)
        version.font = .systemFont(ofSize: 10)
        version.textColor = .tertiaryLabelColor
        version.isSelectable = true

        let stack = NSStackView(views: [brand, navigation, spacer, helpButton, hint, version])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 16, bottom: 16, right: 16)
        stack.setCustomSpacing(8, after: helpButton)
        stack.setCustomSpacing(2, after: hint)
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

    private func makeSectionButton(_ section: Section) -> NSButton {
        let button = SidebarSectionButton(
            title: section.title,
            image: NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title) ?? NSImage(),
            target: self,
            action: #selector(selectSection(_:))
        )
        button.tag = section.rawValue
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 152).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        sectionButtons.append(button)
        return button
    }

    @objc private func selectSection(_ sender: NSButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        show(section)
    }

    private func show(_ section: Section) {
        guard section != currentSection || pageCache[section] == nil else {
            updateSidebarSelection(section)
            return
        }
        currentSection = section
        updateSidebarSelection(section)

        if pageCache[section] == nil {
            let page: NSView
            switch section {
            case .appearance:
                page = makeAppearancePage()
            case .keyboard:
                page = makeKeyboardPage()
            case .punctuation:
                page = makePunctuationPage()
            case .userLexicon:
                page = makeUserLexiconPage()
            case .lexiconDirectory:
                page = makeLexiconDirectoryPage()
            case .help:
                page = makeHelpPage()
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
            pageCache[section] = page
        }

        for (cached, view) in pageCache {
            view.isHidden = cached != section
        }
    }

    private func updateSidebarSelection(_ section: Section) {
        for button in sectionButtons {
            let selected = button.tag == section.rawValue
            button.state = selected ? .on : .off
            // 使用明确的系统强调色表示当前页面，避免与键盘焦点状态混淆。
            // 在当前外观下取色，避免暗色侧栏仍用浅色强调色底。
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                button.layer?.backgroundColor = selected
                    ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                    : NSColor.clear.cgColor
            }
            button.setSelectedAppearance(selected)
        }
    }

    private func makeAppearancePage() -> NSView {
        // 顶部固定预览；滚动时底部分隔线提示内容已离开。
        let previewHost = AppearancePreviewHost()
        previewHost.translatesAutoresizingMaskIntoConstraints = false

        let regular = makeRegularAppearanceSettings()
        let advanced = CandidateSkinSettingsView()

        let form = NSStackView(views: [regular, advanced])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 10
        form.setContentHuggingPriority(.required, for: .vertical)
        form.setContentCompressionResistancePriority(.required, for: .vertical)
        form.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsBoundsChangedNotifications = true

        let document = TopAlignedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(form)
        scroll.documentView = document

        let root = NSView()
        root.addSubview(previewHost)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            previewHost.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            previewHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            previewHost.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: previewHost.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            form.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            form.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            form.topAnchor.constraint(equalTo: document.topAnchor, constant: 10),
            form.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            regular.widthAnchor.constraint(equalTo: form.widthAnchor),
            advanced.widthAnchor.constraint(equalTo: form.widthAnchor)
        ])
        return root
    }

    private func makeRegularAppearanceSettings() -> NSView {
        let settings = NSStackView()
        settings.orientation = .vertical
        settings.alignment = .leading
        settings.spacing = 10

        // 候选数放第一位，最常用；候选字体放同一行第二列。
        let pageValue = NSTextField(labelWithString: "\(RimeBehaviorPrefs.pageSize)")
        pageValue.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let stepper = NSStepper()
        stepper.minValue = 3
        stepper.maxValue = 9
        // 到 3 / 9 即停，不从最大值绕回最小值。
        stepper.valueWraps = false
        stepper.integerValue = RimeBehaviorPrefs.pageSize
        stepper.target = PageTarget.shared
        stepper.action = #selector(PageTarget.changed(_:))
        PageTarget.shared.valueLabel = pageValue

        let font = NSPopUpButton(frame: .zero, pullsDown: false)
        for item in IMESettingsControls.preferredFonts {
            font.addItem(withTitle: item.title)
            font.lastItem?.representedObject = item.name
        }
        font.selectItem(at: IMESettingsControls.preferredFonts.firstIndex {
            $0.name == IMEAppearancePrefs.fontName
        } ?? 0)
        font.target = FontTarget.shared
        font.action = #selector(FontTarget.changed(_:))
        font.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        let pageFontRow = equalTwoColumns(
            formRow("每页候选数", pageValue, stepper),
            formRow("候选字体", font)
        )
        settings.addArrangedSubview(pageFontRow)
        pageFontRow.widthAnchor.constraint(equalTo: settings.widthAnchor).isActive = true

        let orientation = NSSegmentedControl(
            labels: IMEAppearancePrefs.Orientation.allCases.map(\.title),
            trackingMode: .selectOne,
            target: OrientationTarget.shared,
            action: #selector(OrientationTarget.changed(_:))
        )
        orientation.selectedSegment = IMEAppearancePrefs.orientation == .horizontal ? 0 : 1

        let verticalAlignment = NSSegmentedControl(
            labels: CandidateSkin.VerticalAlignment.allCases.map(\.title),
            trackingMode: .selectOne,
            target: VerticalAlignmentTarget.shared,
            action: #selector(VerticalAlignmentTarget.changed(_:))
        )
        verticalAlignment.selectedSegment = CandidateSkin.VerticalAlignment.allCases.firstIndex(
            of: IMEAppearancePrefs.skin.verticalAlignment
        ) ?? 1

        let layoutRow = equalTwoColumns(
            formRow("排列方向", orientation),
            formRow("纵向对齐", verticalAlignment)
        )
        settings.addArrangedSubview(layoutRow)
        layoutRow.widthAnchor.constraint(equalTo: settings.widthAnchor).isActive = true

        // 序号样式：无 / 1. / 1
        let indexStyle = NSSegmentedControl(
            labels: IMEAppearancePrefs.IndexStyle.allCases.map(\.title),
            trackingMode: .selectOne,
            target: IndexStyleTarget.shared,
            action: #selector(IndexStyleTarget.changed(_:))
        )
        indexStyle.selectedSegment = IMEAppearancePrefs.IndexStyle.allCases.firstIndex(
            of: IMEAppearancePrefs.indexStyle
        ) ?? 1
        indexStyle.toolTip = "无：不显示序号；1.：带点；1：不带点"

        // 候选显示方式三选一：候选框 / 仅数量圆点 / 完全不显示。
        let displayMode = NSSegmentedControl(
            labels: IMEAppearancePrefs.DisplayMode.allCases.map(\.title),
            trackingMode: .selectOne,
            target: DisplayModeTarget.shared,
            action: #selector(DisplayModeTarget.changed(_:))
        )
        displayMode.selectedSegment = IMEAppearancePrefs.displayMode.rawValue
        displayMode.toolTip = "仅圆点：只按候选数量显示小圆点；不显示：只保留编码，数字键等照常选词"

        let displayRow = equalTwoColumns(
            formRow("候选显示", displayMode),
            formRow("序号", indexStyle)
        )
        settings.addArrangedSubview(displayRow)
        displayRow.widthAnchor.constraint(equalTo: settings.widthAnchor).isActive = true

        // 显示编码单独占左列，右列留空，保持两列对齐。
        let preedit = NSButton(
            checkboxWithTitle: "",
            target: ToggleTarget.shared,
            action: #selector(ToggleTarget.preeditChanged(_:))
        )
        preedit.state = IMEAppearancePrefs.showPreeditInPanel ? .on : .off
        preedit.toolTip = "在候选词后面显示五笔编码；反查时显示单字的五笔编码"
        let codeDetail = NSSegmentedControl(
            labels: IMEAppearancePrefs.CodeDetail.allCases.map(\.title),
            trackingMode: .selectOne,
            target: CodeDetailTarget.shared,
            action: #selector(CodeDetailTarget.changed(_:))
        )
        codeDetail.selectedSegment = IMEAppearancePrefs.CodeDetail.allCases.firstIndex(
            of: IMEAppearancePrefs.codeDetail
        ) ?? 0
        codeDetail.toolTip = "补码：只显示还没打出来的字母；完整：显示词条的全部编码"
        let preeditRow = equalTwoColumns(
            formRow("显示编码", preedit),
            formRow("编码范围", codeDetail)
        )
        settings.addArrangedSubview(preeditRow)
        preeditRow.widthAnchor.constraint(equalTo: settings.widthAnchor).isActive = true

        return card(
            title: "常规",
            subtitle: nil,
            content: settings
        )
    }

    // 常规区统一两列均分，避免某一行挤出第三列。
    private func equalTwoColumns(_ left: NSView, _ right: NSView) -> NSView {
        let row = NSStackView(views: [left, right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 24
        row.distribution = .fillEqually
        return row
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

        let caretHint = NSButton(
            checkboxWithTitle: "",
            target: ToggleTarget.shared,
            action: #selector(ToggleTarget.caretModeHintChanged(_:))
        )
        caretHint.state = IMEAppearancePrefs.showCaretModeHint ? .on : .off
        caretHint.toolTip = "输入光标出现时，在旁边显示当前是中文还是英文"
        settings.addArrangedSubview(formRow("光标提示", caretHint))

        let quickAdd = QuickAddHotkeySettingsView(frame: .zero)
        settings.addArrangedSubview(formRow("造词", quickAdd))

        let note = NSTextField(wrappingLabelWithString: "翻页与选词写入 Rime 配置，下次按键时生效。造词快捷键立即作用于输入法。候选出现时，用与造词相同的修饰键加数字（默认 ⌃⌥1）可删除对应候选。")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        note.preferredMaxLayoutWidth = 420
        settings.addArrangedSubview(note)

        return page(
            title: "按键",
            subtitle: "设置翻页、快捷选词和全局造词快捷键。",
            content: card(title: "候选按键", subtitle: nil, content: settings)
        )
    }

    private func makePunctuationPage() -> NSView {
        let body = PunctuationSettingsView(frame: .zero)
        return page(
            title: "标点",
            subtitle: "标点由输入法处理。输出用空格分开多项，可直接修改。直接上屏只输出第一项；候选列表弹出全部符号供选择。",
            content: card(title: "标点输出", subtitle: nil, content: body)
        )
    }

    // 上面只留同步和扩展词库一条，下面整块是分组和词条。
    private func makeUserLexiconPage() -> NSView {
        let lexicon = UserLexiconSettingsView(frame: .zero)
        lexicon.setContentHuggingPriority(.defaultLow, for: .vertical)
        lexicon.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let cloud = UserLexiconCloudBar(frame: .zero)
        cloud.setContentHuggingPriority(.required, for: .vertical)
        cloud.setContentCompressionResistancePriority(.required, for: .vertical)
        let root = NSView()
        for view in [cloud, lexicon] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            cloud.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 23),
            cloud.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            cloud.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            lexicon.leadingAnchor.constraint(equalTo: cloud.leadingAnchor),
            lexicon.trailingAnchor.constraint(equalTo: cloud.trailingAnchor),
            lexicon.topAnchor.constraint(equalTo: cloud.bottomAnchor, constant: 12),
            lexicon.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        return root
    }

    // 词库目录：路径切换、部署与复位。单字字典单独一块。
    private func makeLexiconDirectoryPage() -> NSView {
        let directory = LexiconDirectorySettingsView(frame: .zero)
        directory.translatesAutoresizingMaskIntoConstraints = false
        let charMap = CharMapSettingsView(frame: .zero)
        charMap.translatesAutoresizingMaskIntoConstraints = false
        let directoryCard = card(title: "目录与部署", subtitle: nil, content: directory)
        let charMapCard = card(
            title: "单字字典",
            subtitle: "从参考码表提取单字编码，添加词条和快捷造词时用来自动生成词组编码。",
            content: charMap
        )
        for box in [directoryCard, charMapCard] {
            box.translatesAutoresizingMaskIntoConstraints = false
        }
        let column = NSStackView(views: [directoryCard, charMapCard])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        directoryCard.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        charMapCard.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return page(
            title: "词库目录",
            subtitle: "管理 Rime 用户数据目录，并维护自动编码用的单字字典。",
            content: column
        )
    }

    // 帮助页：预置编码与特殊功能说明。
    private func makeHelpPage() -> NSView {
        let presets = helpList([
            ("date", "当前日期：2026-09-23、2026年9月23日、星期三，翻页可见日期加时间"),
            ("time", "当前时间：11:22:05、11:22、秒级时间戳、11时22分，翻页可见毫秒时间戳"),
            ("week", "星期与周数：星期三、周三、第39周、2026年第39周、Wednesday 等"),
            ("选词与翻页", "与普通候选相同：数字键、空格、; ' 选词，翻页键按「按键」页设置")
        ])
        let lookup = helpList([
            ("z + 拼音", "拼音反查：不会五笔拆字时，以 z 开头输入拼音，候选中选字上屏。单字后面会标出词库里的五笔编码，词组不现造编码"),
            ("'", "反查结束符，拼音输完可按 ' 结束反查")
        ])
        let keys = helpList([
            ("造词快捷键", "默认 ⌃⌥N，可在「按键」页修改。弹出窗口添加自造词，写入用户词当前分组；两分钟内刚上屏的词会自动填入，并列出同编码词来自哪个词库"),
            ("删除候选", "候选出现时，按与造词相同的修饰键加数字（默认 ⌃⌥1–9）。确认框会显示词库、权重、备注和同编码词，确认后从该词库删除"),
            ("单按 Shift", "中 / 英文模式切换；英文模式下按键直接上屏"),
            ("光标提示", "输入框出现光标时，在旁边显示当前是中文还是英文。可在「按键」页关闭"),
            ("空格", "上屏第一个候选"),
            ("1 – 9", "选择对应序号的候选（仅数量圆点模式下同样有效）"),
            ("; '", "选第二、第三候选（需在「按键」页开启）"),
            ("- = / , .", "候选翻页，方式在「按键」页设置"),
            ("Esc", "清空当前编码"),
            ("回车", "直接上屏已输入的编码字母"),
            ("四码唯一", "输入满四码且只有一个候选时自动上屏")
        ])
        let switches = helpList([
            ("Ctrl+Shift+1", "切换输入方案（五笔 / 拼音）"),
            ("Ctrl+Shift+2", "中 / 英文切换"),
            ("Ctrl+Shift+3", "全角 / 半角切换"),
            ("Ctrl+Shift+5", "常用 / 扩展字符集切换"),
            ("Ctrl+A / E / B / F", "编码中移动光标：行首、行尾、左移、右移"),
            ("Ctrl+H / Ctrl+G", "编码中删除一个字母 / 取消输入")
        ])
        let appearance = helpList([
            ("仅圆点", "不展开候选词，只用小圆点表示当前页候选数量，适合熟练盲打"),
            ("不显示", "完全隐藏候选框，只保留编码下划线，数字键、空格等选词照常"),
            ("距光标上 / 左", "在「外观配置 › 布局细节」中调整候选窗与光标的距离"),
            ("皮肤分享", "外观可导出为文件，在其他设备从文件导入")
        ])

        let stack = NSStackView(views: [
            card(title: "预置编码", subtitle: "输入以下编码，候选中会出现基于系统时间的内容。", content: presets),
            card(title: "拼音反查", subtitle: nil, content: lookup),
            card(title: "常用按键", subtitle: nil, content: keys),
            card(title: "快捷开关", subtitle: nil, content: switches),
            card(title: "特殊显示", subtitle: nil, content: appearance),
            card(title: "反馈与联系", subtitle: "使用问题、建议或词库错误，欢迎联系作者。", content: contactHelp())
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return page(
            title: "帮助",
            subtitle: "预置输入功能与特殊按键说明。",
            content: stack
        )
    }

    // 帮助页联系方式：邮箱 / QQ 群均可一键复制。
    private func contactHelp() -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        list.addArrangedSubview(contactRow(label: "邮箱", value: "kylebing@163.com"))
        list.addArrangedSubview(contactRow(label: "QQ 群", value: "878750538"))
        return list
    }

    private func contactRow(label: String, value: String) -> NSView {
        let key = NSTextField(labelWithString: label)
        key.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        key.textColor = .controlAccentColor
        key.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let text = NSTextField(labelWithString: value)
        text.font = .systemFont(ofSize: 12)
        text.isSelectable = true
        let copy = NSButton(title: "复制", target: ContactCopyTarget.shared, action: #selector(ContactCopyTarget.copyValue(_:)))
        copy.controlSize = .small
        copy.identifier = NSUserInterfaceItemIdentifier(value)
        let row = NSStackView(views: [key, text, copy])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    // 两列说明列表：左列按键 / 编码（等宽字体），右列说明文字。
    private func helpList(_ items: [(key: String, text: String)]) -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        for item in items {
            let key = NSTextField(labelWithString: item.key)
            key.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            key.textColor = .controlAccentColor
            key.widthAnchor.constraint(equalToConstant: 140).isActive = true
            let text = NSTextField(wrappingLabelWithString: item.text)
            text.font = .systemFont(ofSize: 12)
            text.preferredMaxLayoutWidth = 420
            // 允许选中复制（如邮箱、群号）。
            text.isSelectable = true
            let row = NSStackView(views: [key, text])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 12
            list.addArrangedSubview(row)
        }
        return list
    }

    private func makeAccountPage() -> NSView {
        let account = AccountSyncSettingsView(frame: .zero)
        account.translatesAutoresizingMaskIntoConstraints = false
        return page(
            title: "账户",
            subtitle: "登录后，到「用户词」页同步用户词并获取扩展词库。",
            content: card(title: nil, subtitle: nil, content: account)
        )
    }

    private func page(title: String, subtitle: String, content body: NSView) -> NSView {
        // 长表单必须保持自身高度，让外层 ScrollView 滚动，不能压缩所有控件。
        body.setContentHuggingPriority(.required, for: .vertical)
        body.setContentCompressionResistancePriority(.required, for: .vertical)
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        let detail = NSTextField(wrappingLabelWithString: subtitle)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor

        // 内容较短时由底部弹性区域吸收剩余高度，表单始终贴在右侧面板顶部。
        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let stack = NSStackView(views: [heading, detail, body, bottomSpacer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        stack.setCustomSpacing(24, after: detail)
        stack.edgeInsets = NSEdgeInsets(top: 26, left: 23, bottom: 26, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        // 内容填满可用宽度，同时保留左右各 28 pt 的窗口边距。
        body.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -51).isActive = true

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
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
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
        box.contentViewMargins = NSSize(width: 14, height: 12)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            stack.addArrangedSubview(label)
        }
        if let subtitle {
            let label = NSTextField(wrappingLabelWithString: subtitle)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
            stack.setCustomSpacing(10, after: label)
        } else if title != nil {
            stack.setCustomSpacing(10, after: stack.arrangedSubviews[0])
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

/// 侧栏按钮使用原生图标和文字，并固定 10pt 左右内边距及 4pt 图文间距。
private final class SidebarSectionButton: NSButton {
    private let itemIcon = NSImageView()
    private let itemTitle = NSTextField(labelWithString: "")

    init(title: String, image: NSImage, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = ""
        self.image = nil
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        // 按下即响应，避免等 mouseUp 才切换带来的迟滞感。
        sendAction(on: .leftMouseDown)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 6

        itemIcon.image = image
        itemIcon.imageScaling = .scaleProportionallyDown
        itemIcon.translatesAutoresizingMaskIntoConstraints = false
        itemTitle.stringValue = title
        itemTitle.font = .systemFont(ofSize: 13, weight: .medium)
        itemTitle.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [itemIcon, itemTitle])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            itemIcon.widthAnchor.constraint(equalToConstant: 16),
            itemIcon.heightAnchor.constraint(equalToConstant: 16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setSelectedAppearance(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // point 位于父视图坐标系；命中子视图时也交由按钮处理点击。
        guard let hit = super.hitTest(point), hit === self || hit.isDescendant(of: self) else {
            return nil
        }
        return self
    }

    func setSelectedAppearance(_ selected: Bool) {
        let color: NSColor = selected ? .controlAccentColor : .labelColor
        itemIcon.contentTintColor = color
        itemTitle.textColor = color
    }
}

/// 滚动区域采用从上向下的坐标系，避免短内容垂直居中或贴底。
private final class TopAlignedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// 固定在外观页顶部的预览容器：左侧候选预览，右侧输入框可直接打字查看实际候选窗；底部常驻分隔线。
private final class AppearancePreviewHost: NSView {
    private let preview = CandidateInlinePreviewView()
    private let testField = NSTextField()
    private let bottomBorder = NSBox()
    // 亮暗切换盖在整块预览（候选窗 + 输入框）的最左上角。
    private let appearanceSwitch = NSSegmentedControl(
        labels: ["亮色", "暗色"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        preview.translatesAutoresizingMaskIntoConstraints = false
        testField.placeholderString = "在此打字，查看实际候选窗"
        testField.font = .systemFont(ofSize: 14)
        testField.bezelStyle = .roundedBezel
        testField.translatesAutoresizingMaskIntoConstraints = false
        testField.setContentCompressionResistancePriority(.required, for: .horizontal)
        bottomBorder.boxType = .separator
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        appearanceSwitch.controlSize = .small
        appearanceSwitch.target = self
        appearanceSwitch.action = #selector(previewAppearanceChanged(_:))
        appearanceSwitch.selectedSegment = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 1 : 0
        appearanceSwitch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)
        addSubview(testField)
        addSubview(bottomBorder)
        // 最后加入，保证压在预览和输入框之上。
        addSubview(appearanceSwitch)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: testField.leadingAnchor, constant: -12),
            preview.topAnchor.constraint(equalTo: topAnchor),
            preview.bottomAnchor.constraint(equalTo: bottomBorder.topAnchor, constant: -10),
            // 输入框固定宽度，垂直居中于预览区。
            testField.trailingAnchor.constraint(equalTo: trailingAnchor),
            testField.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            testField.widthAnchor.constraint(equalToConstant: 190),
            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -20),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 24),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),
            // 贴齐整块预览区的左上角，不跟左侧候选条走。
            appearanceSwitch.topAnchor.constraint(equalTo: topAnchor),
            appearanceSwitch.leadingAnchor.constraint(equalTo: leadingAnchor)
        ])
        preview.setPreviewAppearance(dark: appearanceSwitch.selectedSegment == 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func previewAppearanceChanged(_ sender: NSSegmentedControl) {
        preview.setPreviewAppearance(dark: sender.selectedSegment == 1)
    }
}

/// 嵌入设置页右侧的候选栏预览。候选条在区域内水平垂直居中。
final class CandidateInlinePreviewView: NSView {
    private let chrome = RoundedChromeView(frame: .zero)
    private let candidates = NSStackView()
    private let hiddenHint = NSTextField(labelWithString: "候选框已隐藏，仅显示编码")
    private var heightConstraint: NSLayoutConstraint!
    // 相对 chrome 背景的内边距约束，避免 edgeInsets 只撑开外层容器。
    private var paddingConstraints: (top: NSLayoutConstraint, bottom: NSLayoutConstraint, leading: NSLayoutConstraint, trailing: NSLayoutConstraint)!
    private var observers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 预览区不裁切，避免候选条阴影被切掉。
        clipsToBounds = false
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8

        // 预览也预留阴影外扩，与真实候选窗一致，才能看见阴影。
        chrome.reservesShadowSpace = true
        chrome.clipsToBounds = false
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.setContentHuggingPriority(.required, for: .horizontal)
        chrome.setContentHuggingPriority(.required, for: .vertical)
        chrome.setContentCompressionResistancePriority(.required, for: .horizontal)
        chrome.setContentCompressionResistancePriority(.required, for: .vertical)

        // 与实际候选窗共用同一套内边距约束。
        paddingConstraints = CandidateBarLayout.pin(candidates, in: chrome)

        addSubview(chrome)

        // 「不显示」模式下替代候选条的提示文字。
        hiddenHint.font = .systemFont(ofSize: 12)
        hiddenHint.textColor = .secondaryLabelColor
        hiddenHint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hiddenHint)

        heightConstraint = heightAnchor.constraint(equalToConstant: 88)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 264),
            heightConstraint,
            hiddenHint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hiddenHint.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 底层：候选预览按内容尺寸（含阴影外扩），水平垂直完全居中。
            chrome.centerXAnchor.constraint(equalTo: centerXAnchor),
            chrome.centerYAnchor.constraint(equalTo: centerYAnchor),
            chrome.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            chrome.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            chrome.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
            chrome.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)
        ])

        let center = DistributedNotificationCenter.default()
        for name in [IMEAppearancePrefs.didChangeNotification, RimeBehaviorPrefs.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.reload()
            })
        }
        reload()
    }

    // 由外层预览块的亮暗按钮调用，只改候选条外观。
    func setPreviewAppearance(dark: Bool) {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        chrome.appearance = NSAppearance(named: name)
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
        let skin = IMEAppearancePrefs.skin
        let colors = skin.colors(for: chrome.effectiveAppearance)
        let sample = ["五", "吾", "伍", "捂", "梧", "妩", "坞", "晤", "勿"]
        let fullCodes = ["gghg", "ggg", "wgg", "rgkg", "sgkg", "vntg", "fggy", "jgkg", "qre"]
        let restCodes = ["hg", "g", "gg", "kg", "g", "tg", "gy", "kg", "re"]
        let sampleCodes = IMEAppearancePrefs.codeDetail == .full ? fullCodes : restCodes
        let hidden = IMEAppearancePrefs.hideCandidatePanel
        chrome.isHidden = hidden
        hiddenHint.isHidden = !hidden
        chrome.applySkin()
        // 与实际候选窗走同一套排版，保证所见即所得。
        CandidateBarLayout.populate(
            candidates,
            padding: paddingConstraints,
            candidates: Array(sample.prefix(RimeBehaviorPrefs.pageSize)),
            codes: Array(sampleCodes.prefix(RimeBehaviorPrefs.pageSize)),
            colors: colors,
            onSelect: nil
        )
        // fittingSize 已含阴影外扩；再留一点余量避免贴边。
        chrome.layoutSubtreeIfNeeded()
        heightConstraint.constant = max(72, ceil(chrome.fittingSize.height + 16))
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: heightConstraint.constant)
    }
}

// MARK: - Control targets

private final class VerticalAlignmentTarget: NSObject {
    static let shared = VerticalAlignmentTarget()
    @objc func changed(_ sender: NSSegmentedControl) {
        let choices = CandidateSkin.VerticalAlignment.allCases
        let index = min(max(sender.selectedSegment, 0), choices.count - 1)
        IMEAppearancePrefs.updateSkin { $0.verticalAlignment = choices[index] }
    }
}

private final class OrientationTarget: NSObject {
    static let shared = OrientationTarget()
    @objc func changed(_ sender: NSSegmentedControl) {
        IMEAppearancePrefs.orientation = sender.selectedSegment == 0 ? .horizontal : .vertical
    }
}

private final class FontTarget: NSObject {
    static let shared = FontTarget()
    @objc func changed(_ sender: NSPopUpButton) {
        let value = (sender.selectedItem?.representedObject as? String) ?? ""
        // 换字体后收敛粗细选项，避免高级区仍指向当前字体不支持的字重。
        IMEAppearancePrefs.updateSkin { skin in
            skin.fontName = value
            let choices = CandidateSkin.FontWeight.available(forFontName: value)
            if !choices.contains(skin.candidateWeight) {
                skin.candidateWeight = choices.first ?? .regular
            }
            if !choices.contains(skin.indexWeight) {
                skin.indexWeight = choices.first ?? .regular
            }
        }
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

    @objc func caretModeHintChanged(_ sender: NSButton) {
        IMEAppearancePrefs.showCaretModeHint = sender.state == .on
    }
}

private final class CodeDetailTarget: NSObject {
    static let shared = CodeDetailTarget()
    @objc func changed(_ sender: NSSegmentedControl) {
        let choices = IMEAppearancePrefs.CodeDetail.allCases
        guard choices.indices.contains(sender.selectedSegment) else { return }
        IMEAppearancePrefs.codeDetail = choices[sender.selectedSegment]
    }
}

private final class IndexStyleTarget: NSObject {
    static let shared = IndexStyleTarget()
    @objc func changed(_ sender: NSSegmentedControl) {
        let choices = IMEAppearancePrefs.IndexStyle.allCases
        guard choices.indices.contains(sender.selectedSegment) else { return }
        IMEAppearancePrefs.indexStyle = choices[sender.selectedSegment]
    }
}

private final class DisplayModeTarget: NSObject {
    static let shared = DisplayModeTarget()
    @objc func changed(_ sender: NSSegmentedControl) {
        IMEAppearancePrefs.displayMode = IMEAppearancePrefs.DisplayMode(rawValue: sender.selectedSegment) ?? .panel
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

private final class ContactCopyTarget: NSObject {
    static let shared = ContactCopyTarget()
    @objc func copyValue(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

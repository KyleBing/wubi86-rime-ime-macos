import AppKit

/// 全局快捷键弹出的造词窗口：输入词条后自动填编码，写入当前选中分组。
final class QuickAddWordPanel: NSObject, NSTextFieldDelegate {
    static let shared = QuickAddWordPanel()

    private let panel: NSPanel
    private let wordField = NSTextField(string: "")
    private let codeField = NSTextField(string: "")
    private let groupPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let addButton = NSButton(title: "添加", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let root = NSStackView()
    private var groupIndexes: [Int] = []
    // 内容区宽度；高度按控件贴合，不预留底部空白
    private let contentWidth: CGFloat = 312

    private override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 312, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "添加自造词"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        build()
        installTitleLogo()
    }

    func showPanel() {
        // 标题栏图标在窗口显示后才稳定出现，弹出时再刷一次
        installTitleLogo()
        reloadGroups()
        wordField.stringValue = ""
        codeField.stringValue = ""
        setStatus("", color: .secondaryLabelColor)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(wordField)
        DispatchQueue.main.async { [weak self] in
            self?.installTitleLogo()
        }
    }

    private func build() {
        wordField.placeholderString = "输入后回车添加"
        wordField.delegate = self
        wordField.font = .systemFont(ofSize: 13)
        codeField.placeholderString = "自动生成，可修改"
        codeField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        codeField.delegate = self
        groupPopup.controlSize = .regular
        groupPopup.font = .systemFont(ofSize: 13)

        addButton.target = self
        addButton.action = #selector(addWord)
        addButton.bezelStyle = .rounded
        // 回车键默认按钮，颜色交给系统（不要手写 bezel / 文字色，否则会变成蓝底黑字）
        addButton.keyEquivalent = "\r"
        panel.defaultButtonCell = addButton.cell as? NSButtonCell

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        status.isHidden = true
        // 换行高度按内容区宽度算，避免空提示把窗口撑高。
        status.preferredMaxLayoutWidth = contentWidth - 32
        status.setContentHuggingPriority(.required, for: .vertical)

        let wordRow = labeled("词条", wordField)
        let codeRow = labeled("编码", codeField)
        let groupRow = labeled("分组", groupPopup)
        let form = NSStackView(views: [wordRow, codeRow, groupRow])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8

        // 底栏：按钮水平居中
        let leadingSpacer = NSView()
        let trailingSpacer = NSView()
        leadingSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        trailingSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let footer = NSStackView(views: [leadingSpacer, addButton, trailingSpacer])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        // 没提示时不占位，窗口只包住表单和底栏。
        root.detachesHiddenViews = true
        root.addArrangedSubview(form)
        root.addArrangedSubview(status)
        root.addArrangedSubview(footer)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView?.addSubview(root)
        guard let content = panel.contentView else { return }
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: content.topAnchor),

            form.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: form.widthAnchor),
            leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor),
            wordRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            codeRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            groupRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            codeField.widthAnchor.constraint(equalTo: wordField.widthAnchor),
            groupPopup.widthAnchor.constraint(equalTo: wordField.widthAnchor),
            addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
        fitPanel(anchorTop: false)
    }

    // 标题栏左侧文档图标位换成品牌 Logo（SettingsLogo，不用 AppIcon）。
    private func installTitleLogo() {
        guard let logo = loadBrandLogo() else { return }
        // 指向 Logo 文件以唤出标题栏 proxy 图标按钮
        if let url = brandLogoURL() {
            panel.representedURL = url
        } else {
            panel.representedURL = URL(fileURLWithPath: "/")
        }
        logo.size = NSSize(width: 16, height: 16)
        if let button = panel.standardWindowButton(.documentIconButton) {
            button.image = logo
            // 禁止点图标跳到 Finder
            button.action = nil
            button.target = nil
        }
    }

    private func brandLogoURL() -> URL? {
        let name = BrandIcon.settingsResourceName
        if let resources = Bundle.main.resourceURL {
            let url = resources.appendingPathComponent("\(name).png")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return Bundle.main.url(forResource: name, withExtension: "png")
    }

    // 只用透明枫叶 Logo，不用圆角 App 图标。
    private func loadBrandLogo() -> NSImage? {
        if let url = brandLogoURL(), let img = NSImage(contentsOf: url) {
            return img
        }
        if let img = Bundle.main.image(forResource: BrandIcon.settingsResourceName) {
            return img
        }
        return BrandIcon.settingsImage()
    }

    // 按当前控件高度收缩内容区，顶部保持不动。
    private func fitPanel(anchorTop: Bool) {
        guard panel.contentView != nil else { return }
        let oldMaxY = panel.frame.maxY
        panel.layoutIfNeeded()
        root.layoutSubtreeIfNeeded()
        // 根栈没有被拉满到窗口底部，布局后的高度就是内容高度。
        var height = ceil(root.bounds.height)
        if height < 1 {
            height = ceil(root.fittingSize.height)
        }
        guard height > 1 else { return }
        panel.setContentSize(NSSize(width: contentWidth, height: height))
        guard anchorTop, panel.isVisible else { return }
        var frame = panel.frame
        frame.origin.y += oldMaxY - frame.maxY
        panel.setFrame(frame, display: true)
    }

    private func setStatus(_ message: String, color: NSColor) {
        status.stringValue = message
        status.textColor = color
        status.isHidden = message.isEmpty
        fitPanel(anchorTop: panel.isVisible)
    }

    private func reloadGroups() {
        let document = UserDictWriter.loadActiveDocument()
        groupPopup.removeAllItems()
        groupIndexes = []
        let groups = document.groups.isEmpty ? [UserDictGroup(name: "")] : document.groups
        for (index, group) in groups.enumerated() {
            groupPopup.addItem(withTitle: group.displayName)
            groupIndexes.append(index)
        }
        let selected = min(QuickAddPrefs.selectedGroupIndex, max(0, groupPopup.numberOfItems - 1))
        groupPopup.selectItem(at: selected)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        // 词条或编码里按回车，直接添加
        if (control === wordField || control === codeField),
           commandSelector == #selector(NSResponder.insertNewline(_:)) {
            addWord()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === wordField else { return }
        let word = wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = WubiDictEncoder.encode(word: word)
        if !encoded.isEmpty {
            codeField.stringValue = encoded
        }
    }

    @objc private func addWord() {
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            setStatus("词条不能为空。", color: .systemOrange)
            return
        }
        guard !code.isEmpty, (1...4).contains(code.count) else {
            setStatus(
                code.isEmpty
                    ? "无法自动编码。请到「词库目录」生成单字字典，或手填编码。"
                    : "编码需 1–4 位。",
                color: .systemOrange
            )
            return
        }
        let popupIndex = groupPopup.indexOfSelectedItem
        guard groupIndexes.indices.contains(popupIndex) else {
            setStatus("请选择分组。", color: .systemOrange)
            return
        }
        let groupIndex = groupIndexes[popupIndex]
        do {
            try UserDictWriter.addEntry(UserDictEntry(code: code, text: text, weight: 100_000), toGroupIndex: groupIndex)
            QuickAddPrefs.selectedGroupIndex = groupIndex
            let deploy = RimeConfigDeploy.deployNow()
            _ = RimeSession.shared.ensureStarted()
            switch deploy {
            case .success:
                setStatus("已添加到「\(groupPopup.titleOfSelectedItem ?? "当前分组")」并部署。", color: .secondaryLabelColor)
                wordField.stringValue = ""
                codeField.stringValue = ""
                panel.makeFirstResponder(wordField)
            case .failure(let message):
                setStatus("已写入，但部署失败：\(message)", color: .systemRed)
            }
        } catch {
            setStatus(error.localizedDescription, color: .systemRed)
        }
    }

    private func labeled(_ title: String, _ field: NSView) -> NSView {
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 12)
        caption.alignment = .right
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.widthAnchor.constraint(equalToConstant: 36).isActive = true
        caption.setContentHuggingPriority(.required, for: .horizontal)
        field.translatesAutoresizingMaskIntoConstraints = false
        // 标签固定宽度，输入框占满这一行剩余空间
        field.setContentHuggingPriority(.init(1), for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [caption, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }
}

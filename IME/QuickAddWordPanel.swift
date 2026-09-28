import AppKit
import Carbon

/// 全局快捷键弹出的造词窗口：输入词条后自动填编码，写入当前选中分组。
final class QuickAddWordPanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    static let shared = QuickAddWordPanel()

    private let panel: NSPanel
    private let wordField = NSTextField(string: "")
    private let codeField = NSTextField(string: "")
    private let weightField = NSTextField(string: "")
    private let groupPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let addButton = NSButton(title: "添加", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let sameCodeView = NSTextView()
    private let sameCodeScroll = NSScrollView()
    private let sameCodeTitle = NSTextField(labelWithString: "同编码词条")
    private let root = NSStackView()
    private var groupIndexes: [Int] = []
    // 最近一次上屏的词，短时间内打开造词窗时填进词条框。
    private static var lastCommittedWord = ""
    private static var lastCommittedAt: Date?
    // 内容区宽度；高度按控件贴合，不预留底部空白
    private let contentWidth: CGFloat = 520

    private override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "添加自造词"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 关掉窗口时不要跟着隐藏，否则点一下别的软件造词框就没了。
        panel.hidesOnDeactivate = false
        panel.delegate = self
        build()
        installTitleLogo()
    }

    // 候选上屏后记下来，供接下来打开的造词窗预填。
    static func noteCommittedWord(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: { WubiDictEncoder.isChineseHanzi($0) }) else { return }
        lastCommittedWord = trimmed
        lastCommittedAt = Date()
    }

    // 两分钟内选过的词才自动填入，避免很久以后打开造词窗还带着旧词。
    private static func recentCommittedWord() -> String? {
        guard let at = lastCommittedAt, Date().timeIntervalSince(at) < 120 else { return nil }
        return lastCommittedWord.isEmpty ? nil : lastCommittedWord
    }

    var isOpen: Bool { panel.isVisible }

    // 造词框正在编辑文本（光标在词条或编码里）。
    var isEditingText: Bool {
        panel.isVisible && (panel.isKeyWindow || panel.firstResponder is NSTextView)
    }

    // 词条框需要走 Rime 组字；编码和权重框仍直接接收 ASCII。
    var acceptsComposedText: Bool {
        panel.isVisible && focusedTextField() === wordField
    }

    /// 造词框开着时按键留在词条框里，不送进当前软件，也不把输入法进程变成前台。
    func claimEditingKey(_ event: NSEvent) -> Bool? {
        guard panel.isVisible else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            _ = ensureFieldEditor()
            return performStandardEdit(event)
        }
        if event.keyCode == UInt16(kVK_Escape) {
            panel.performClose(nil)
            return true
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            // 词条仍在组字时先交给 Rime 上屏，下一次回车再添加。
            if acceptsComposedText,
               RimeSession.shared.bridgeEngine.snapshot()?.isComposing == true {
                return nil
            }
            addWord()
            return true
        }
        if event.keyCode == UInt16(kVK_Tab) {
            focusNextField(shift: flags.contains(.shift))
            return true
        }
        guard let editor = ensureFieldEditor() else { return true }
        if acceptsComposedText {
            let composing = RimeSession.shared.bridgeEngine.snapshot()?.isComposing == true
            if !composing, isTextNavigationEvent(event, flags: flags) {
                editor.interpretKeyEvents([event])
                return true
            }
            // 普通文字键和组字期间的编辑键交回输入控制器，再把结果定向写入词条框。
            return nil
        }
        editor.interpretKeyEvents([event])
        return true
    }

    // 输入控制器提交的候选只写入词条框，不写回原来的应用。
    @discardableResult
    func insertComposedText(_ text: String) -> Bool {
        guard acceptsComposedText, let editor = ensureFieldEditor() else { return false }
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    @discardableResult
    func setComposition(_ text: NSAttributedString, selectionRange: NSRange) -> Bool {
        guard acceptsComposedText, let editor = ensureFieldEditor() else { return false }
        editor.setMarkedText(
            text,
            selectedRange: selectionRange,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        return true
    }

    @discardableResult
    func clearComposition() -> Bool {
        guard acceptsComposedText, let editor = ensureFieldEditor() else { return false }
        if editor.hasMarkedText() {
            editor.unmarkText()
        }
        return true
    }

    // 候选窗定位到词条框当前光标，而不是原应用的输入位置。
    func compositionScreenRect() -> NSRect? {
        guard acceptsComposedText, let editor = ensureFieldEditor() else { return nil }
        let range = editor.selectedRange()
        let rect = editor.firstRect(forCharacterRange: range, actualRange: nil)
        return rect.width > 0 || rect.height > 0 ? rect : nil
    }

    // 非激活面板也能拿到字段编辑器，这样不用把输入法进程激活到前台。
    private func ensureFieldEditor() -> NSTextView? {
        if let editor = panel.firstResponder as? NSTextView { return editor }
        if !panel.isKeyWindow {
            panel.makeKey()
        }
        let field = focusedTextField() ?? wordField
        panel.makeFirstResponder(field)
        return panel.firstResponder as? NSTextView
    }

    private func focusedTextField() -> NSTextField? {
        guard let editor = panel.firstResponder as? NSTextView else { return nil }
        if editor === wordField.currentEditor() { return wordField }
        if editor === codeField.currentEditor() { return codeField }
        if editor === weightField.currentEditor() { return weightField }
        return nil
    }

    private func focusNextField(shift: Bool) {
        let fields = [wordField, codeField, weightField]
        let current = focusedTextField() ?? wordField
        let index = fields.firstIndex(where: { $0 === current }) ?? 0
        let next = shift ? (index + fields.count - 1) % fields.count : (index + 1) % fields.count
        panel.makeFirstResponder(fields[next])
    }

    // 没在组字时，光标移动和删除由词条框自己处理。
    private func isTextNavigationEvent(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        if flags.contains(.control) || flags.contains(.option) { return true }
        switch Int(event.keyCode) {
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
             kVK_Delete, kVK_ForwardDelete:
            return true
        default:
            return false
        }
    }

    func showPanel(prefill selectedText: String? = nil) {
        // 标题栏图标在窗口显示后才稳定出现，弹出时再刷一次
        installTitleLogo()
        reloadGroups()
        // 优先使用快捷键触发时读取到的完整选区；不支持读取选区的应用再回退到最近上屏内容。
        let prefill = selectedText ?? Self.recentCommittedWord() ?? ""
        wordField.stringValue = prefill
        if prefill.isEmpty {
            codeField.stringValue = ""
        } else {
            codeField.stringValue = WubiDictEncoder.encode(word: prefill)
        }
        refreshSameCode()
        weightField.stringValue = ""
        setStatus("", color: .secondaryLabelColor)
        panel.center()
        // 不调用 activate。输入法进程一旦变成前台，别的软件就挂不上状态栏菜单。
        panel.orderFrontRegardless()
        panel.makeKey()
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
        weightField.placeholderString = "可空"
        weightField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        weightField.delegate = self
        weightField.cell?.isScrollable = true
        // 允许选择、复制；长词条可在框内滚动
        for field in [wordField, codeField, weightField] {
            field.isEditable = true
            field.isSelectable = true
            field.cell?.isScrollable = true
        }
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

        sameCodeTitle.font = .systemFont(ofSize: 12, weight: .medium)
        sameCodeView.isEditable = false
        sameCodeView.isSelectable = true
        sameCodeView.drawsBackground = false
        sameCodeView.textContainerInset = NSSize(width: 4, height: 4)
        sameCodeView.configureAsLexiconTable()
        sameCodeScroll.documentView = sameCodeView
        sameCodeScroll.hasVerticalScroller = true
        sameCodeScroll.hasHorizontalScroller = true
        sameCodeScroll.autohidesScrollers = true
        sameCodeScroll.borderType = .bezelBorder
        sameCodeScroll.drawsBackground = false

        let wordRow = labeled("词条", wordField)
        let codeRow = labeled("编码", codeField)
        let weightRow = labeled("权重", weightControls())
        let groupRow = labeled("分组", groupPopup)
        let form = NSStackView(views: [wordRow, codeRow, weightRow, groupRow])
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
        root.addArrangedSubview(sameCodeTitle)
        root.addArrangedSubview(sameCodeScroll)
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
            sameCodeTitle.widthAnchor.constraint(equalTo: form.widthAnchor),
            sameCodeScroll.widthAnchor.constraint(equalTo: form.widthAnchor),
            sameCodeScroll.heightAnchor.constraint(equalToConstant: 140),
            footer.widthAnchor.constraint(equalTo: form.widthAnchor),
            leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor),
            wordRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            codeRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            weightRow.widthAnchor.constraint(equalTo: form.widthAnchor),
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
        if (control === wordField || control === codeField || control === weightField),
           commandSelector == #selector(NSResponder.insertNewline(_:)) {
            addWord()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        let field = obj.object as? NSTextField
        if field === wordField {
            let word = wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let encoded = WubiDictEncoder.encode(word: word)
            if !encoded.isEmpty {
                codeField.stringValue = encoded
            }
            refreshSameCode()
        } else if field === codeField {
            refreshSameCode()
        }
    }

    // 按当前编码列出各词库里已有的同码词。
    private func refreshSameCode() {
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let show = !code.isEmpty
        sameCodeTitle.isHidden = !show
        sameCodeScroll.isHidden = !show
        guard show else {
            fitPanel(anchorTop: panel.isVisible)
            return
        }
        sameCodeTitle.stringValue = "同编码词条"
        sameCodeView.setLexiconTable(DictLexiconHit.message("正在查找…"))
        fitPanel(anchorTop: panel.isVisible)
        let requested = code
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hits = DictLexiconIndex.shared.hits(code: requested)
            DispatchQueue.main.async {
                guard let self else { return }
                let current = self.codeField.stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard current == requested else { return }
                self.sameCodeTitle.stringValue = hits.isEmpty ? "同编码词条" : "同编码词条（\(hits.count)）"
                let table = hits.isEmpty
                    ? DictLexiconHit.message("当前词库里没有这个编码。")
                    : DictLexiconHit.alignedTable(hits)
                self.sameCodeView.setLexiconTable(table)
                self.fitPanel(anchorTop: self.panel.isVisible)
            }
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
        let weightText = weightField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let weight: Int?
        if weightText.isEmpty {
            weight = nil
        } else if let value = Int(weightText) {
            weight = value
        } else {
            setStatus("权重需为整数，或留空。", color: .systemOrange)
            return
        }
        do {
            // 留空的权重不写进 yaml；有值才写出第三列。
            try UserDictWriter.addEntry(
                UserDictEntry(code: code, text: text, weight: weight),
                toGroupIndex: groupIndex,
                boostWeight: false
            )
            QuickAddPrefs.selectedGroupIndex = groupIndex
            // 不要走 deployNow：它会 finalize 正在用的 librime，菜单还在但按键全部失效
            DictLexiconIndex.shared.invalidate()
            let reloaded = RimeSession.shared.reloadUserDictionary()
            if reloaded {
                setStatus("已添加到「\(groupPopup.titleOfSelectedItem ?? "当前分组")」。", color: .secondaryLabelColor)
                wordField.stringValue = ""
                codeField.stringValue = ""
                weightField.stringValue = ""
                refreshSameCode()
                panel.makeFirstResponder(wordField)
            } else {
                setStatus("已写入，但词库重载失败。", color: .systemRed)
            }
        } catch {
            setStatus(error.localizedDescription, color: .systemRed)
        }
    }

    // 当前编码里已有词的最大权重，没有权重时按 0。
    @objc private func applyWeightStep(_ sender: NSButton) {
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = DictLexiconIndex.shared.hits(code: code).compactMap(\.entry.weight).max() ?? 0
        weightField.stringValue = String(base + sender.tag)
    }

    private func weightControls() -> NSView {
        let steps = NSStackView()
        steps.orientation = .horizontal
        steps.spacing = 4
        steps.alignment = .centerY
        // 顺序按使用习惯：先加 5、再加 10、再加 1。
        for (title, delta) in [("n+5", 5), ("n+10", 10), ("n+1", 1)] {
            let button = NSButton(title: title, target: self, action: #selector(applyWeightStep(_:)))
            button.tag = delta
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            button.setContentHuggingPriority(.required, for: .horizontal)
            steps.addArrangedSubview(button)
        }
        weightField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        weightField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [weightField, steps])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        steps.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    // Command+A / C / V / X / Z。输入法进程没有编辑菜单时，这些快捷键不会自动生效。
    private func performStandardEdit(_ event: NSEvent) -> Bool {
        guard let editor = panel.firstResponder as? NSTextView,
              let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "a":
            editor.selectAll(nil)
        case "c":
            editor.copy(nil)
        case "x":
            editor.cut(nil)
        case "v":
            editor.paste(nil)
        case "z":
            if event.modifierFlags.contains(.shift) {
                editor.undoManager?.redo()
            } else {
                editor.undoManager?.undo()
            }
        default:
            return false
        }
        return true
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

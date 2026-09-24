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
    private var groupIndexes: [Int] = []

    private override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 196),
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
    }

    func showPanel() {
        reloadGroups()
        status.stringValue = ""
        wordField.stringValue = ""
        codeField.stringValue = ""
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(wordField)
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
        // 提示文字不要抢垂直空间，否则会把按钮顶离表单。
        status.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let wordRow = labeled("词条", wordField)
        let codeRow = labeled("编码", codeField)
        let groupRow = labeled("分组", groupPopup)
        let form = NSStackView(views: [wordRow, codeRow, groupRow])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 10

        // 左右弹性空白等宽，按钮水平居中。
        let leadingSpacer = NSView()
        let trailingSpacer = NSView()
        leadingSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        trailingSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttonRow = NSStackView(views: [leadingSpacer, addButton, trailingSpacer])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY

        // 多余高度留在底部，按钮紧跟表单。
        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.init(1), for: .vertical)

        let root = NSStackView(views: [form, buttonRow, status, bottomSpacer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView?.addSubview(root)
        guard let content = panel.contentView else { return }
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            form.widthAnchor.constraint(equalTo: root.widthAnchor),
            status.widthAnchor.constraint(equalTo: form.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor),
            wordRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            codeRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            groupRow.widthAnchor.constraint(equalTo: form.widthAnchor),
            codeField.widthAnchor.constraint(equalTo: wordField.widthAnchor),
            groupPopup.widthAnchor.constraint(equalTo: wordField.widthAnchor),
            addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
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
            status.textColor = .systemOrange
            status.stringValue = "词条不能为空。"
            return
        }
        guard !code.isEmpty, (1...4).contains(code.count) else {
            status.textColor = .systemOrange
            status.stringValue = code.isEmpty
                ? "无法自动编码。请到「词库目录」生成单字字典，或手填编码。"
                : "编码需 1–4 位。"
            return
        }
        let popupIndex = groupPopup.indexOfSelectedItem
        guard groupIndexes.indices.contains(popupIndex) else {
            status.textColor = .systemOrange
            status.stringValue = "请选择分组。"
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
                status.textColor = .secondaryLabelColor
                status.stringValue = "已添加到「\(groupPopup.titleOfSelectedItem ?? "当前分组")」并部署。"
                wordField.stringValue = ""
                codeField.stringValue = ""
                panel.makeFirstResponder(wordField)
            case .failure(let message):
                status.textColor = .systemRed
                status.stringValue = "已写入，但部署失败：\(message)"
            }
        } catch {
            status.textColor = .systemRed
            status.stringValue = error.localizedDescription
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

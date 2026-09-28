import AppKit
import Carbon

/// 删除候选前先说明来源、权重和同编码词，确认后再从对应码表删掉。
final class DeleteCandidatePanel: NSObject, NSWindowDelegate {
    static let shared = DeleteCandidatePanel()

    private let panel: NSPanel
    private let wordLabel = NSTextField(labelWithString: "")
    private let codeLabel = NSTextField(labelWithString: "")
    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let weightLabel = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let extraLabel = NSTextField(wrappingLabelWithString: "")
    private let sameCodeView = NSTextView()
    private let sameCodeScroll = NSScrollView()
    private let deleteButton = NSButton(title: "删除", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let root = NSStackView()
    private let contentWidth: CGFloat = 560

    private var sourceHits: [DictLexiconHit] = []
    private var preedit = ""
    private var onDeleted: ((String) -> Void)?
    private var lookupGeneration = 0

    var isOpen: Bool { panel.isVisible }

    private override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "删除候选"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.delegate = self
        build()
    }

    /// 候选框出现时，用造词修饰键 + 数字打开。删完后把原来的编码交回去重输。
    func present(candidate: String, preedit: String, onDeleted: @escaping (String) -> Void) {
        self.preedit = preedit
        self.onDeleted = onDeleted
        lookupGeneration += 1
        let generation = lookupGeneration
        sourceHits = []
        fill(candidate: candidate, code: "", otherCodes: [], loadPeers: false)
        sameCodeView.setLexiconTable(DictLexiconHit.message("正在查找词库…"))
        setStatus("正在查找这个词来自哪个词库。", color: .secondaryLabelColor)
        deleteButton.isEnabled = false
        show()
        // 主词库很大，放到后台读，避免卡住正在输入的按键。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let match = DictLexiconIndex.shared.match(text: candidate, preedit: preedit)
            DispatchQueue.main.async {
                guard let self, generation == self.lookupGeneration, self.isOpen else { return }
                self.sourceHits = match.hits.sorted { self.sourceRank($0) < self.sourceRank($1) }
                let code = self.sourceHits.first?.entry.code ?? ""
                self.fill(candidate: candidate, code: code, otherCodes: match.otherCodes, loadPeers: true)
                if self.sourceHits.isEmpty {
                    self.setStatus("没有在词库里找到「\(candidate)」。它可能是标点或临时候选，不能删除。", color: .systemOrange)
                    self.deleteButton.isEnabled = false
                } else {
                    self.setStatus("确认后会从所选词库删掉这一条，并重新加载词库。", color: .secondaryLabelColor)
                    self.deleteButton.isEnabled = true
                }
            }
        }
    }

    func presentUnavailable(_ reason: String) {
        lookupGeneration += 1
        sourceHits = []
        preedit = ""
        onDeleted = nil
        fill(candidate: "—", code: "—", otherCodes: [], loadPeers: false)
        sameCodeView.setLexiconTable(DictLexiconHit.message(""))
        setStatus(reason, color: .systemOrange)
        deleteButton.isEnabled = false
        show()
    }

    // 输入法先接到按键时，在这里关掉窗口或确认删除，避免把编码改掉。
    func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            closePanel()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if deleteButton.isEnabled { confirmDelete() }
        default:
            break
        }
        return true
    }

    private func show() {
        // 不激活输入法进程，避免其它软件的状态栏菜单消失。
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func fill(candidate: String, code: String, otherCodes: [String], loadPeers: Bool) {
        wordLabel.stringValue = candidate
        codeLabel.stringValue = code.isEmpty ? "—" : code
        sourcePopup.removeAllItems()
        if sourceHits.isEmpty {
            sourcePopup.addItem(withTitle: "未找到")
            sourcePopup.isEnabled = false
            weightLabel.stringValue = "—"
            noteLabel.stringValue = "—"
        } else {
            for hit in sourceHits {
                sourcePopup.addItem(withTitle: hit.sourceTitle)
            }
            sourcePopup.isEnabled = sourceHits.count > 1
            sourcePopup.selectItem(at: 0)
            applySelectedSource()
        }
        if otherCodes.isEmpty {
            extraLabel.stringValue = ""
            extraLabel.isHidden = true
        } else {
            extraLabel.stringValue = "该词还有编码 \(otherCodes.joined(separator: "、"))"
            extraLabel.isHidden = false
        }
        if loadPeers {
            let peers = code.isEmpty ? [] : DictLexiconIndex.shared.hits(code: code)
            let table = peers.isEmpty
                ? DictLexiconHit.message("没有同编码词条。")
                : DictLexiconHit.alignedTable(peers)
            sameCodeView.setLexiconTable(table)
        }
        sameCodeScroll.isHidden = false
    }

    private func applySelectedSource() {
        let index = sourcePopup.indexOfSelectedItem
        guard sourceHits.indices.contains(index) else { return }
        let hit = sourceHits[index]
        codeLabel.stringValue = hit.entry.code
        weightLabel.stringValue = hit.entry.weight.map(String.init) ?? "无"
        let note = hit.entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        noteLabel.stringValue = note.isEmpty ? "无" : note
        let peers = DictLexiconIndex.shared.hits(code: hit.entry.code)
        let table = peers.isEmpty
            ? DictLexiconHit.message("没有同编码词条。")
            : DictLexiconHit.alignedTable(peers)
        sameCodeView.setLexiconTable(table)
    }

    @objc private func sourceChanged() {
        applySelectedSource()
    }

    @objc private func confirmDelete() {
        let index = sourcePopup.indexOfSelectedItem
        guard sourceHits.indices.contains(index) else { return }
        let hit = sourceHits[index]
        let code = preedit
        deleteButton.isEnabled = false
        setStatus("正在从「\(hit.sourceTitle)」删除并重新加载…", color: .secondaryLabelColor)
        do {
            try DictLexiconIndex.shared.remove(hit)
            let reloaded = RimeSession.shared.reloadUserDictionary()
            let finish = onDeleted
            onDeleted = nil
            closePanel()
            if reloaded {
                DispatchQueue.main.async {
                    finish?(code)
                }
            }
        } catch {
            deleteButton.isEnabled = true
            setStatus(error.localizedDescription, color: .systemRed)
        }
    }

    @objc private func cancel() {
        closePanel()
    }

    private func closePanel() {
        panel.orderOut(nil)
    }

    // 用户词优先于扩展、Hamster 和主词库，方便先删自己加的那条。
    private func sourceRank(_ hit: DictLexiconHit) -> Int {
        let name = hit.fileURL.lastPathComponent
        if name == "wubi86_jidian_user.dict.yaml" { return 0 }
        if name == "wubi86_jidian_extra.dict.yaml" { return 1 }
        if name == "wubi86_jidian_user_hamster.dict.yaml" { return 2 }
        if name == "wubi86_jidian.dict.yaml" { return 3 }
        return 4
    }

    private func build() {
        wordLabel.font = .systemFont(ofSize: 13, weight: .medium)
        codeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        weightLabel.font = .systemFont(ofSize: 13)
        noteLabel.font = .systemFont(ofSize: 13)
        noteLabel.maximumNumberOfLines = 2
        extraLabel.font = .systemFont(ofSize: 11)
        extraLabel.textColor = .secondaryLabelColor
        extraLabel.maximumNumberOfLines = 2
        sourcePopup.font = .systemFont(ofSize: 13)
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged)

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

        deleteButton.target = self
        deleteButton.action = #selector(confirmDelete)
        deleteButton.bezelStyle = .rounded
        deleteButton.keyEquivalent = "\r"
        panel.defaultButtonCell = deleteButton.cell as? NSButtonCell
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.preferredMaxLayoutWidth = contentWidth - 32

        let form = NSStackView(views: [
            labeled("词条", wordLabel),
            labeled("编码", codeLabel),
            labeled("词库", sourcePopup),
            labeled("权重", weightLabel),
            labeled("备注", noteLabel)
        ])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8

        let peersTitle = NSTextField(labelWithString: "同编码词条")
        peersTitle.font = .systemFont(ofSize: 12, weight: .medium)

        let leading = NSView()
        let trailing = NSView()
        leading.setContentHuggingPriority(.init(1), for: .horizontal)
        trailing.setContentHuggingPriority(.init(1), for: .horizontal)
        let footer = NSStackView(views: [leading, cancelButton, deleteButton, trailing])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        root.detachesHiddenViews = true
        root.addArrangedSubview(form)
        root.addArrangedSubview(extraLabel)
        root.addArrangedSubview(peersTitle)
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
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            form.widthAnchor.constraint(equalTo: root.widthAnchor),
            extraLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            peersTitle.widthAnchor.constraint(equalTo: root.widthAnchor),
            sameCodeScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            sameCodeScroll.heightAnchor.constraint(equalToConstant: 168),
            status.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            leading.widthAnchor.constraint(equalTo: trailing.widthAnchor),
            sourcePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        panel.setContentSize(NSSize(width: contentWidth, height: 420))
    }

    private func setStatus(_ message: String, color: NSColor) {
        status.stringValue = message
        status.textColor = color
    }

    private func labeled(_ title: String, _ field: NSView) -> NSView {
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 12)
        caption.alignment = .right
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.widthAnchor.constraint(equalToConstant: 36).isActive = true
        field.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [caption, field])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }
}

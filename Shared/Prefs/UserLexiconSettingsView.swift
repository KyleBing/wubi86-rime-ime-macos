import AppKit

/// 用户词管理：左分组 / 右词条，按当前选中分组保存。
final class UserLexiconSettingsView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let tipLabel = NSTextField(labelWithString: "")
    private let textField = NSTextField(string: "")
    private let codeField = NSTextField(string: "")
    private let groupTitleLabel = NSTextField(labelWithString: "分组")
    private let entriesTitleLabel = NSTextField(labelWithString: "词条")
    private let groupsTable = NSTableView()
    private let entriesTable = NSTableView()
    private let groupsScroll = NSScrollView()
    private let entriesScroll = NSScrollView()

    private var document = UserDictDocument.empty
    private var selectedGroupIndex = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        textField.placeholderString = "词条"
        textField.delegate = self
        textField.font = .systemFont(ofSize: 12)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        codeField.placeholderString = "编码"
        codeField.delegate = self
        codeField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        codeField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let add = smallButton("添加", #selector(addEntry))
        let reloadBtn = smallButton("重新加载", #selector(reload))
        let form = NSStackView(views: [textField, codeField, add, reloadBtn])
        form.orientation = .horizontal
        form.alignment = .centerY
        form.spacing = 6
        form.translatesAutoresizingMaskIntoConstraints = false

        tipLabel.font = .systemFont(ofSize: 11)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.maximumNumberOfLines = 2
        tipLabel.translatesAutoresizingMaskIntoConstraints = false

        groupTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        groupTitleLabel.textColor = .secondaryLabelColor
        entriesTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        entriesTitleLabel.textColor = .secondaryLabelColor

        let addGroup = textButton("添加分组", #selector(promptAddGroup))
        let renameGroup = textButton("重命名", #selector(promptRenameGroup))
        let deleteGroup = textButton("删除分组", #selector(deleteSelectedGroup))
        deleteGroup.contentTintColor = .systemRed
        let groupTools = NSStackView(views: [addGroup, renameGroup, deleteGroup])
        groupTools.orientation = .horizontal
        groupTools.spacing = 8
        groupTools.alignment = .centerY

        configureGroupsTable()
        configureEntriesTable()

        // 左栏：标题行 + 分组表
        let leftHeader = NSStackView(views: [groupTitleLabel, groupTools])
        leftHeader.orientation = .horizontal
        leftHeader.alignment = .centerY
        leftHeader.spacing = 8
        leftHeader.translatesAutoresizingMaskIntoConstraints = false
        groupTitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let leftPane = NSView()
        leftPane.translatesAutoresizingMaskIntoConstraints = false
        leftPane.addSubview(leftHeader)
        leftPane.addSubview(groupsScroll)

        // 右栏：标题 + 词条表
        let rightPane = NSView()
        rightPane.translatesAutoresizingMaskIntoConstraints = false
        entriesTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        rightPane.addSubview(entriesTitleLabel)
        rightPane.addSubview(entriesScroll)

        let split = NSView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.addSubview(leftPane)
        split.addSubview(rightPane)

        addSubview(form)
        addSubview(tipLabel)
        addSubview(split)

        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: leadingAnchor),
            form.trailingAnchor.constraint(equalTo: trailingAnchor),
            form.topAnchor.constraint(equalTo: topAnchor),

            tipLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            tipLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            tipLabel.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 6),

            split.leadingAnchor.constraint(equalTo: leadingAnchor),
            split.trailingAnchor.constraint(equalTo: trailingAnchor),
            split.topAnchor.constraint(equalTo: tipLabel.bottomAnchor, constant: 8),
            split.bottomAnchor.constraint(equalTo: bottomAnchor),
            split.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),

            // 左约 36%、右约 64%，中间 10pt 间隙
            leftPane.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            leftPane.topAnchor.constraint(equalTo: split.topAnchor),
            leftPane.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            leftPane.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.36),

            rightPane.leadingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: 10),
            rightPane.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            rightPane.topAnchor.constraint(equalTo: split.topAnchor),
            rightPane.bottomAnchor.constraint(equalTo: split.bottomAnchor),

            leftHeader.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftHeader.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            leftHeader.topAnchor.constraint(equalTo: leftPane.topAnchor),
            leftHeader.heightAnchor.constraint(equalToConstant: 22),

            groupsScroll.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            groupsScroll.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            groupsScroll.topAnchor.constraint(equalTo: leftHeader.bottomAnchor, constant: 4),
            groupsScroll.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            entriesTitleLabel.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            entriesTitleLabel.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            entriesTitleLabel.topAnchor.constraint(equalTo: rightPane.topAnchor),
            entriesTitleLabel.heightAnchor.constraint(equalToConstant: 22),

            entriesScroll.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            entriesScroll.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            entriesScroll.topAnchor.constraint(equalTo: entriesTitleLabel.bottomAnchor, constant: 4),
            entriesScroll.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor)
        ])
    }

    private func configureGroupsTable() {
        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.title = "名称"
        nameCol.minWidth = 80
        nameCol.resizingMask = .autoresizingMask
        let countCol = NSTableColumn(identifier: .init("count"))
        countCol.title = "数"
        countCol.width = 40
        countCol.minWidth = 36
        countCol.maxWidth = 48
        groupsTable.addTableColumn(nameCol)
        groupsTable.addTableColumn(countCol)
        styleCompact(groupsTable)
        groupsTable.delegate = self
        groupsTable.dataSource = self
        groupsTable.action = #selector(groupSelectionChanged)
        groupsScroll.documentView = groupsTable
        styleScroll(groupsScroll)
    }

    private func configureEntriesTable() {
        let textCol = NSTableColumn(identifier: .init("text"))
        textCol.title = "词条"
        textCol.minWidth = 80
        textCol.resizingMask = .autoresizingMask
        let codeCol = NSTableColumn(identifier: .init("code"))
        codeCol.title = "编码"
        codeCol.width = 64
        codeCol.minWidth = 52
        let actionCol = NSTableColumn(identifier: .init("action"))
        actionCol.title = ""
        actionCol.width = 48
        actionCol.minWidth = 48
        actionCol.maxWidth = 56
        entriesTable.addTableColumn(textCol)
        entriesTable.addTableColumn(codeCol)
        entriesTable.addTableColumn(actionCol)
        styleCompact(entriesTable)
        entriesTable.delegate = self
        entriesTable.dataSource = self
        entriesScroll.documentView = entriesTable
        styleScroll(entriesScroll)
    }

    private func styleCompact(_ table: NSTableView) {
        table.headerView = NSTableHeaderView()
        table.allowsMultipleSelection = false
        table.usesAlternatingRowBackgroundColors = false
        table.rowHeight = 26
        table.intercellSpacing = NSSize(width: 6, height: 0)
        table.style = .plain
        table.gridStyleMask = []
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    }

    private func styleScroll(_ scroll: NSScrollView) {
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private func smallButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .small
        return button
    }

    // 文字按钮：无边框，仅文字
    private func textButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        return button
    }

    // MARK: - Reload

    @objc func reload() {
        document = UserDictWriter.loadActiveDocument()
        if document.groups.isEmpty {
            document.groups = [UserDictGroup(name: "")]
        }
        // 始终按分组落盘，保证 ## 行保留
        if !document.isGroupMode {
            document.isGroupMode = true
        }
        if selectedGroupIndex >= document.groups.count {
            selectedGroupIndex = max(0, document.groups.count - 1)
        }
        groupsTable.reloadData()
        entriesTable.reloadData()
        if document.groups.indices.contains(selectedGroupIndex) {
            groupsTable.selectRowIndexes(IndexSet(integer: selectedGroupIndex), byExtendingSelection: false)
        }
        refreshEntriesTitle()
        if tipLabel.stringValue.isEmpty
            || tipLabel.stringValue.hasPrefix("共")
            || tipLabel.stringValue.hasPrefix("暂无")
            || tipLabel.stringValue.hasPrefix("分组") {
            tipLabel.textColor = .secondaryLabelColor
            tipLabel.stringValue = summaryText()
        }
    }

    private func summaryText() -> String {
        let n = document.entryCount
        let g = document.groups.count
        if n == 0 {
            return "暂无用户词。选中左侧分组后添加词条。"
        }
        return "分组 \(g) · 词条 \(n)"
    }

    private func refreshEntriesTitle() {
        guard document.groups.indices.contains(selectedGroupIndex) else {
            entriesTitleLabel.stringValue = "词条"
            return
        }
        let group = document.groups[selectedGroupIndex]
        entriesTitleLabel.stringValue = "\(group.displayName) · \(group.entries.count)"
    }

    @objc private func groupSelectionChanged() {
        let row = groupsTable.selectedRow
        guard document.groups.indices.contains(row) else { return }
        selectedGroupIndex = row
        refreshEntriesTitle()
        entriesTable.reloadData()
    }

    // MARK: - Group actions

    @objc private func promptAddGroup() {
        let alert = NSAlert()
        alert.messageText = "添加分组"
        alert.informativeText = "空名称会显示为「- 未命名 -」。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: "")
        field.placeholderString = "分组名（可空）"
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var doc = document
        var group = doc.insertEmptyGroup(before: doc.groups.count)
        group.name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = doc.groups.firstIndex(where: { $0.id == group.id }) {
            doc.groups[idx] = group
        }
        doc.isGroupMode = true
        do {
            try UserDictWriter.saveActiveDocument(doc)
            selectedGroupIndex = max(0, doc.groups.count - 1)
            tipLabel.textColor = .secondaryLabelColor
            tipLabel.stringValue = "已添加分组「\(group.displayName)」"
            reload()
            maybeDeploy(successHint: tipLabel.stringValue)
        } catch {
            tipLabel.textColor = .systemRed
            tipLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func promptRenameGroup() {
        guard document.groups.indices.contains(selectedGroupIndex) else { return }
        let group = document.groups[selectedGroupIndex]
        let alert = NSAlert()
        alert.messageText = "重命名分组"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: group.name)
        field.placeholderString = "分组名（可空）"
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var doc = document
        doc.groups[selectedGroupIndex].name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        doc.isGroupMode = true
        do {
            try UserDictWriter.saveActiveDocument(doc)
            tipLabel.textColor = .secondaryLabelColor
            tipLabel.stringValue = "已重命名为「\(doc.groups[selectedGroupIndex].displayName)」"
            reload()
        } catch {
            tipLabel.textColor = .systemRed
            tipLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func deleteSelectedGroup() {
        guard document.groups.indices.contains(selectedGroupIndex) else { return }
        let group = document.groups[selectedGroupIndex]
        let alert = NSAlert()
        alert.messageText = "删除分组「\(group.displayName)」？"
        alert.informativeText = group.entries.isEmpty
            ? "将删除该空分组。"
            : "组内 \(group.entries.count) 条词也会一并删除。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var doc = document
        doc.groups.remove(at: selectedGroupIndex)
        if doc.groups.isEmpty {
            doc.groups = [UserDictGroup(name: "")]
        }
        doc.isGroupMode = true
        do {
            try UserDictWriter.saveActiveDocument(doc)
            UserDictWriter.markNeedsDeploy()
            selectedGroupIndex = min(selectedGroupIndex, max(0, doc.groups.count - 1))
            tipLabel.textColor = .secondaryLabelColor
            tipLabel.stringValue = "已删除分组"
            reload()
            maybeDeploy(successHint: tipLabel.stringValue)
        } catch {
            tipLabel.textColor = .systemRed
            tipLabel.stringValue = error.localizedDescription
        }
    }

    // MARK: - Entry actions

    @objc private func addEntry() {
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !text.isEmpty, (1...4).contains(code.count) else {
            tipLabel.stringValue = "编码需 1–4 位，词条非空。"
            tipLabel.textColor = .systemOrange
            return
        }
        guard document.groups.indices.contains(selectedGroupIndex) else {
            tipLabel.stringValue = "请先选择左侧分组。"
            tipLabel.textColor = .systemOrange
            return
        }
        let index = selectedGroupIndex
        do {
            try UserDictWriter.addEntry(UserDictEntry(code: code, text: text, weight: 100_000), toGroupIndex: index)
            UserDictWriter.markNeedsDeploy()
            codeField.stringValue = ""
            textField.stringValue = ""
            let name = document.groups[index].displayName
            tipLabel.textColor = .secondaryLabelColor
            tipLabel.stringValue = "已添加到「\(name)」"
            reload()
            maybeDeploy(successHint: tipLabel.stringValue)
        } catch {
            tipLabel.textColor = .systemRed
            tipLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func deleteEntryRow(_ sender: NSButton) {
        let row = sender.tag
        guard document.groups.indices.contains(selectedGroupIndex) else { return }
        let entries = document.groups[selectedGroupIndex].entries
        guard entries.indices.contains(row) else { return }
        let entry = entries[row]
        do {
            try UserDictWriter.removeEntry(entry, fromGroupIndex: selectedGroupIndex)
            UserDictWriter.markNeedsDeploy()
            tipLabel.textColor = .secondaryLabelColor
            tipLabel.stringValue = "已删除「\(entry.text)」"
            reload()
            maybeDeploy(successHint: tipLabel.stringValue)
        } catch {
            tipLabel.textColor = .systemRed
            tipLabel.stringValue = error.localizedDescription
        }
    }

    private func maybeDeploy(successHint: String) {
        if let actions = IMESettingsControls.lexiconActions, actions.deploy().ok {
            tipLabel.stringValue = "\(successHint)，已部署。"
        } else {
            tipLabel.stringValue = "\(successHint)。请到「词库目录」部署生效。"
        }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === groupsTable {
            return document.groups.count
        }
        guard document.groups.indices.contains(selectedGroupIndex) else { return 0 }
        return document.groups[selectedGroupIndex].entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        if tableView === groupsTable {
            return groupsCell(id: id, row: row)
        }
        return entriesCell(id: id, row: row)
    }

    private func groupsCell(id: String, row: Int) -> NSView? {
        guard document.groups.indices.contains(row) else { return nil }
        let group = document.groups[row]
        if id == "count" {
            return centeredLabelCell(
                "\(group.entries.count)",
                mono: false,
                secondary: true,
                alignment: .center
            )
        }
        return centeredLabelCell(group.displayName, mono: false, secondary: false, alignment: .left)
    }

    private func entriesCell(id: String, row: Int) -> NSView? {
        guard document.groups.indices.contains(selectedGroupIndex) else { return nil }
        let entries = document.groups[selectedGroupIndex].entries
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        if id == "action" {
            return centeredButtonCell(title: "删除", tag: row, action: #selector(deleteEntryRow(_:)))
        }
        if id == "code" {
            return centeredLabelCell(entry.code, mono: true, secondary: true, alignment: .left)
        }
        return centeredLabelCell(entry.text, mono: false, secondary: false, alignment: .left)
    }

    // 用 NSTableCellView 包一层，文字在行内纵向居中
    private func centeredLabelCell(
        _ text: String,
        mono: Bool,
        secondary: Bool,
        alignment: NSTextAlignment
    ) -> NSTableCellView {
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.font = mono
            ? .monospacedSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 12)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func centeredButtonCell(title: String, tag: Int, action: Selector) -> NSView {
        let cell = NSTableCellView()
        let button = textButton(title, action)
        button.contentTintColor = .systemRed
        button.tag = tag
        button.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    // MARK: - Text field

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === textField else { return }
        let word = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = WubiDictEncoder.encode(word: word)
        if !encoded.isEmpty {
            codeField.stringValue = encoded
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if (control === textField || control === codeField),
           commandSelector == #selector(NSResponder.insertNewline(_:)) {
            addEntry()
            return true
        }
        return false
    }
}

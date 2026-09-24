import AppKit

/// 用户词：左分组 / 右词条，按当前选中分组保存。
final class UserLexiconSettingsView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let tipLabel = NSTextField(labelWithString: "")
    private let textField = NSTextField(string: "")
    private let codeField = NSTextField(string: "")
    private let groupTitleLabel = NSTextField(labelWithString: "分组")
    private let entriesTitleLabel = NSTextField(labelWithString: "词条")
    private let groupsTable = ReorderTableView()
    private let entriesTable = ReorderTableView()
    // 拖动排序：正在拖动的表格、跟随鼠标的行快照浮层、被拖动的原行、当前目标行
    private weak var dragTable: ReorderTableView?
    private var dragOverlay: NSView?
    private var dragSourceRow: Int?
    private var dragTargetRow: Int?
    private var dragGrabOffsetY: CGFloat = 0
    private let groupsScroll = NSScrollView()
    private let entriesScroll = NSScrollView()

    private var document = UserDictDocument.empty
    // 与全局造词窗口共用，默认加到这里选中的分组
    private var selectedGroupIndex = QuickAddPrefs.selectedGroupIndex

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 高度交给父窗口，不按表格内容把页面撑成固定高度。
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    private func build() {
        textField.placeholderString = "词条"
        textField.delegate = self
        textField.font = .systemFont(ofSize: 12)
        textField.setContentHuggingPriority(.required, for: .horizontal)
        codeField.placeholderString = "编码"
        codeField.delegate = self
        codeField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        codeField.setContentHuggingPriority(.required, for: .horizontal)
        let add = smallButton("添加", #selector(addEntry))
        let reloadBtn = smallButton("重新加载", #selector(reload))
        let form = NSStackView(views: [textField, codeField, add, reloadBtn])
        form.orientation = .horizontal
        form.alignment = .centerY
        form.spacing = 6
        form.translatesAutoresizingMaskIntoConstraints = false
        // 两个输入框先放进同一父视图，再设倍数宽度，否则约束激活时会抛异常把页面卡死。
        codeField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        textField.widthAnchor.constraint(equalTo: codeField.widthAnchor, multiplier: 3).isActive = true

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

        let leftHeader = NSStackView(views: [groupTitleLabel, groupTools])
        leftHeader.orientation = .vertical
        leftHeader.alignment = .leading
        leftHeader.spacing = 4
        leftHeader.translatesAutoresizingMaskIntoConstraints = false

        let leftPane = NSView()
        leftPane.translatesAutoresizingMaskIntoConstraints = false
        leftPane.clipsToBounds = true
        leftPane.addSubview(leftHeader)
        leftPane.addSubview(groupsScroll)

        let rightPane = NSView()
        rightPane.translatesAutoresizingMaskIntoConstraints = false
        rightPane.clipsToBounds = true
        entriesTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        rightPane.addSubview(entriesTitleLabel)
        rightPane.addSubview(entriesScroll)

        let split = NSView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
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

            leftPane.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            leftPane.topAnchor.constraint(equalTo: split.topAnchor),
            leftPane.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            leftPane.widthAnchor.constraint(equalToConstant: 196),

            rightPane.leadingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: 12),
            rightPane.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            rightPane.topAnchor.constraint(equalTo: split.topAnchor),
            rightPane.bottomAnchor.constraint(equalTo: split.bottomAnchor),

            leftHeader.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftHeader.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            leftHeader.topAnchor.constraint(equalTo: leftPane.topAnchor),

            groupsScroll.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            groupsScroll.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            groupsScroll.topAnchor.constraint(equalTo: leftHeader.bottomAnchor, constant: 4),
            groupsScroll.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            entriesTitleLabel.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            entriesTitleLabel.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            entriesTitleLabel.topAnchor.constraint(equalTo: rightPane.topAnchor),
            entriesTitleLabel.heightAnchor.constraint(equalToConstant: 16),

            entriesScroll.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            entriesScroll.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            entriesScroll.topAnchor.constraint(equalTo: groupsScroll.topAnchor),
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
        // 最后一列是「数」且有 maxWidth。lastColumnOnly 会为了撑满宽度反复改它，布局死循环。
        // 只让第一列（名称）吸收多余宽度。
        groupsTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        groupsTable.delegate = self
        groupsTable.dataSource = self
        groupsTable.action = #selector(groupSelectionChanged)
        configureReorder(groupsTable)
        groupsScroll.documentView = groupsTable
        styleScroll(groupsScroll)
    }

    private func configureEntriesTable() {
        // 最小宽度之和必须小于窗口最窄时的表格宽度，否则 NSTableView 会直接断言退出
        let textCol = NSTableColumn(identifier: .init("text"))
        textCol.title = "词条"
        textCol.minWidth = 36
        textCol.width = 96
        textCol.resizingMask = .autoresizingMask
        let codeCol = NSTableColumn(identifier: .init("code"))
        codeCol.title = "编码"
        codeCol.width = 52
        codeCol.minWidth = 36
        codeCol.maxWidth = 72
        codeCol.resizingMask = []
        let weightCol = NSTableColumn(identifier: .init("weight"))
        weightCol.title = "权重"
        weightCol.width = 52
        weightCol.minWidth = 36
        weightCol.maxWidth = 72
        weightCol.resizingMask = []
        let noteCol = NSTableColumn(identifier: .init("note"))
        noteCol.title = "备注"
        noteCol.minWidth = 36
        noteCol.width = 80
        noteCol.resizingMask = .autoresizingMask
        let actionCol = NSTableColumn(identifier: .init("action"))
        actionCol.title = ""
        actionCol.width = 48
        actionCol.minWidth = 44
        actionCol.maxWidth = 56
        actionCol.resizingMask = []
        entriesTable.addTableColumn(textCol)
        entriesTable.addTableColumn(codeCol)
        entriesTable.addTableColumn(weightCol)
        entriesTable.addTableColumn(noteCol)
        entriesTable.addTableColumn(actionCol)
        styleCompact(entriesTable)
        // 操作列有 maxWidth，不能用 lastColumnOnly / sequential 去撑满，否则会卡在列宽计算里。
        entriesTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        entriesTable.delegate = self
        entriesTable.dataSource = self
        configureReorder(entriesTable)
        entriesScroll.documentView = entriesTable
        styleScroll(entriesScroll)
    }

    private func styleCompact(_ table: NSTableView) {
        table.headerView = NSTableHeaderView()
        table.allowsMultipleSelection = false
        table.usesAlternatingRowBackgroundColors = false
        table.rowHeight = table === entriesTable ? 28 : 26
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
        scroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        scroll.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        // 滚动时修正悬停残留
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tableScrolled(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
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
        QuickAddPrefs.selectedGroupIndex = selectedGroupIndex
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
        QuickAddPrefs.selectedGroupIndex = row
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
            try UserDictWriter.addEntry(UserDictEntry(code: code, text: text), toGroupIndex: index, boostWeight: false)
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("lexiconHoverRow")
        let rowView = (tableView.makeView(withIdentifier: identifier, owner: self) as? LexiconHoverRowView)
            ?? LexiconHoverRowView()
        rowView.identifier = identifier
        rowView.clearHover()
        return rowView
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
            return entryActionsCell(row: row)
        }
        if id == "code" {
            return centeredLabelCell(entry.code, mono: true, secondary: true, alignment: .left)
        }
        if id == "weight" {
            return centeredLabelCell(entry.weight.map(String.init) ?? "", mono: true, secondary: true, alignment: .right)
        }
        if id == "note" {
            let cell = centeredLabelCell(
                entry.note.isEmpty ? "—" : entry.note,
                mono: false,
                secondary: true,
                alignment: .left
            )
            cell.textField?.toolTip = entry.note.isEmpty ? nil : entry.note
            return cell
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

    // 顺序用拖动调整，行内只留编辑和删除
    private func entryActionsCell(row: Int) -> NSView {
        let cell = NSTableCellView()
        let buttons: [(NSImage, String, Selector)] = [
            (DictEditorIcons.edit, "编辑", #selector(editEntryRow(_:))),
            (DictEditorIcons.delete, "删除", #selector(deleteEntryRow(_:)))
        ]
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (image, tip, action) in buttons {
            stack.addArrangedSubview(iconButton(image: image, tip: tip, tag: row, action: action))
        }
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func iconButton(image: NSImage, tip: String, tag: Int, action: Selector) -> NSButton {
        let button = LexiconIconButton()
        button.image = image
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tip
        button.tag = tag
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 18).isActive = true
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return button
    }

    private var editingTextField: NSTextField?
    private var editingCodeField: NSTextField?

    @objc private func editEntryRow(_ sender: NSButton) {
        let row = sender.tag
        guard document.groups.indices.contains(selectedGroupIndex) else { return }
        let entries = document.groups[selectedGroupIndex].entries
        guard entries.indices.contains(row) else { return }
        let entry = entries[row]

        let alert = NSAlert()
        alert.messageText = "编辑词条"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let text = labeledField("词条", entry.text)
        let code = labeledField("编码", entry.code)
        let weight = labeledField("权重", entry.weight.map(String.init) ?? "")
        weight.field.placeholderString = "可空"
        let note = labeledField("备注", entry.note)
        code.field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        weight.field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        editingTextField = text.field
        editingCodeField = code.field
        text.field.delegate = self
        let form = NSStackView(views: [text.row, code.row, weight.row, note.row])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.frame = NSRect(x: 0, y: 0, width: 280, height: 148)
        alert.accessoryView = form
        let response = alert.runModal()
        editingTextField = nil
        editingCodeField = nil
        guard response == .alertFirstButtonReturn else { return }

        let newText = text.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCode = code.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let newNote = note.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty, !newCode.isEmpty, (1...4).contains(newCode.count) else {
            tipLabel.stringValue = "编码需 1–4 位，词条非空。"
            tipLabel.textColor = .systemOrange
            return
        }
        let weightText = weight.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newWeight: Int?
        if weightText.isEmpty {
            newWeight = nil
        } else if let value = Int(weightText) {
            newWeight = value
        } else {
            tipLabel.stringValue = "权重需要是整数，或留空。"
            tipLabel.textColor = .systemOrange
            return
        }
        let duplicate = entries.enumerated().contains { index, item in
            index != row && item.text == newText && item.code == newCode
        }
        guard !duplicate else {
            tipLabel.stringValue = "本组已有相同词条和编码。"
            tipLabel.textColor = .systemOrange
            return
        }
        var doc = document
        doc.groups[selectedGroupIndex].entries[row] = UserDictEntry(
            code: newCode,
            text: newText,
            weight: newWeight,
            note: newNote
        )
        saveDocument(doc, success: "已更新「\(newText)」")
    }

    private func labeledField(_ title: String, _ value: String) -> (row: NSView, field: NSTextField) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let field = NSTextField(string: value)
        field.font = .systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return (row, field)
    }

    // MARK: - 拖动排序
    // 系统拖放会话在输入法进程的浮动窗口里不可靠（拖动图从屏幕外飞入、会话立即结束），
    // 因此由 ReorderTableView 自己跟踪鼠标，这里负责绘制浮层和落盘

    // 分组表与词条表共用同一套拖动逻辑，区别只在数据源和落盘
    private func configureReorder(_ table: ReorderTableView) {
        table.onReorderBegin = { [weak self, weak table] row, point in
            guard let self, let table else { return }
            self.beginReorder(in: table, row: row, at: point)
        }
        table.onReorderMove = { [weak self] point in
            self?.updateReorder(at: point)
        }
        table.onReorderEnd = { [weak self] _, cancelled in
            self?.endReorder(cancelled: cancelled)
        }
    }

    // 开始拖动：快照浮层从原行位置悬起，原行隐藏留出空位
    private func beginReorder(in table: ReorderTableView, row: Int, at point: NSPoint) {
        guard row >= 0, row < table.numberOfRows else { return }
        // 词条表拖动时顺带选中该行；分组表保持当前选中分组不变
        if table === entriesTable {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        clearHover(in: table)
        let rowRect = table.rect(ofRow: row)

        let rowView = table.rowView(atRow: row, makeIfNecessary: false)
        var image = rowView.flatMap(snapshot(of:))
        if image == nil, table === entriesTable,
           document.groups.indices.contains(selectedGroupIndex),
           document.groups[selectedGroupIndex].entries.indices.contains(row) {
            image = dragImage(for: document.groups[selectedGroupIndex].entries[row],
                              width: rowRect.width, height: rowRect.height)
        }
        let overlay = PassthroughView(frame: rowRect)
        overlay.wantsLayer = true
        overlay.layer?.contents = image
        overlay.layer?.contentsGravity = .resize
        overlay.layer?.zPosition = 1000
        overlay.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        overlay.layer?.cornerRadius = 6
        overlay.layer?.borderWidth = 1
        overlay.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        overlay.layer?.masksToBounds = false
        overlay.layer?.shadowColor = NSColor.black.cgColor
        overlay.layer?.shadowOpacity = 0
        overlay.layer?.shadowRadius = 8
        overlay.layer?.shadowOffset = CGSize(width: 0, height: -3)
        table.addSubview(overlay)
        dragOverlay = overlay

        dragTable = table
        dragSourceRow = row
        dragTargetRow = row
        // 记录鼠标在行内的纵向偏移，拖动时保持抓取点不变
        dragGrabOffsetY = point.y - rowRect.minY

        // 悬起动画：阴影出现；原行隐藏，由浮层代表它，原位置留出空位
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            overlay.layer?.shadowOpacity = 0.25
        }
        rowView?.alphaValue = 0
        updateReorder(at: point)
    }

    // 浮层纵向跟随鼠标（限制在表格内）；目标位置变化时其它行让位
    private func updateReorder(at point: NSPoint) {
        guard let table = dragTable, let overlay = dragOverlay else { return }
        var frame = overlay.frame
        let maxY = max(0, table.bounds.height - frame.height)
        frame.origin.y = min(max(0, point.y - dragGrabOffsetY), maxY)
        overlay.frame = frame

        // 以浮层中心所在的行槽作为目标位置
        let count = table.numberOfRows
        guard count > 0 else { return }
        let slot = reorderRowHeight(table)
        let target = min(max(0, Int(frame.midY / slot)), count - 1)
        if target != dragTargetRow {
            dragTargetRow = target
            layoutReorderGap(animated: true)
        } else {
            // 自动滚动后新出现的行视图补上偏移
            layoutReorderGap(animated: false)
        }
    }

    // 每行固定高度（行高 + 行间距）
    private func reorderRowHeight(_ table: NSTableView) -> CGFloat {
        table.rowHeight + table.intercellSpacing.height
    }

    // 位于原行与目标位置之间的行上移 / 下移一格，空出目标位置
    private func layoutReorderGap(animated: Bool) {
        guard let table = dragTable, let source = dragSourceRow, let target = dragTargetRow else { return }
        let slot = reorderRowHeight(table)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.18 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            table.enumerateAvailableRowViews { rowView, row in
                var y = table.rect(ofRow: row).minY
                if source < row && row <= target {
                    y -= slot
                } else if target <= row && row < source {
                    y += slot
                }
                guard rowView.frame.origin.y != y else { return }
                let origin = NSPoint(x: rowView.frame.minX, y: y)
                if animated {
                    rowView.animator().setFrameOrigin(origin)
                } else {
                    rowView.setFrameOrigin(origin)
                }
            }
        }
    }

    // 行视图回到表格给定的标准位置并恢复显示
    private func resetReorderRows(_ table: NSTableView) {
        table.enumerateAvailableRowViews { rowView, row in
            rowView.setFrameOrigin(NSPoint(x: rowView.frame.minX, y: table.rect(ofRow: row).minY))
            rowView.alphaValue = 1
        }
    }

    // 松手：浮层落入空位后再落盘；按 Esc：浮层回到原位，其它行复原
    private func endReorder(cancelled: Bool) {
        guard let table = dragTable, let source = dragSourceRow, let overlay = dragOverlay else { return }
        let target = cancelled ? source : (dragTargetRow ?? source)
        if cancelled {
            dragTargetRow = source
            layoutReorderGap(animated: true)
        }
        var landing = overlay.frame
        landing.origin.y = CGFloat(target) * reorderRowHeight(table)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            overlay.animator().frame = landing
            overlay.layer?.shadowOpacity = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            overlay.removeFromSuperview()
            self.dragOverlay = nil
            self.dragTable = nil
            self.dragSourceRow = nil
            self.dragTargetRow = nil
            self.resetReorderRows(table)
            if target != source {
                // 插入下标指原列表中的缝隙位置，下移时要跳过原行自身
                let insertion = target > source ? target + 1 : target
                if table === self.groupsTable {
                    self.moveGroup(from: source, toInsertionIndex: insertion)
                } else {
                    self.moveEntry(from: source, toInsertionIndex: insertion)
                }
            }
            // 拖动期间行在鼠标下移动不会触发进出事件，结束后按真实鼠标位置重算悬停
            self.refreshHover(in: table)
        })
    }

    // 截取行视图当前外观作为浮层图片
    private func snapshot(of view: NSView) -> NSImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func dragImage(for entry: UserDictEntry, width: CGFloat, height: CGFloat) -> NSImage {
        let width = max(160, width)
        let height = max(20, height)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let rect = NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        NSColor.controlAccentColor.withAlphaComponent(0.45).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        // 文字按实际行高垂直居中
        let textY = (height - 16) / 2
        let metaY = (height - 14) / 2
        (entry.text as NSString).draw(at: NSPoint(x: 10, y: textY), withAttributes: textAttrs)
        (entry.code as NSString).draw(at: NSPoint(x: min(width * 0.42, 180), y: metaY), withAttributes: metaAttrs)
        let weight = entry.weight.map(String.init) ?? ""
        (weight as NSString).draw(at: NSPoint(x: min(width * 0.42, 180) + 64, y: metaY), withAttributes: metaAttrs)
        image.unlockFocus()
        return image
    }

    // 把 from 行移到插入下标 row（插入下标指原列表中的缝隙位置）
    @discardableResult
    private func moveEntry(from: Int, toInsertionIndex row: Int) -> Bool {
        guard document.groups.indices.contains(selectedGroupIndex) else { return false }
        var entries = document.groups[selectedGroupIndex].entries
        guard entries.indices.contains(from) else { return false }
        var insertAt = row
        if row > from { insertAt -= 1 }
        insertAt = min(max(0, insertAt), entries.count - 1)
        guard insertAt != from else { return true }
        let entry = entries.remove(at: from)
        entries.insert(entry, at: insertAt)
        var doc = document
        doc.groups[selectedGroupIndex].entries = entries
        saveDocument(doc, success: "已调整顺序") {
            self.entriesTable.selectRowIndexes(IndexSet(integer: insertAt), byExtendingSelection: false)
            self.entriesTable.scrollRowToVisible(insertAt)
        }
        return true
    }

    // 调整分组顺序；当前选中的分组跟着移动，保持选中不变
    private func moveGroup(from: Int, toInsertionIndex row: Int) {
        var groups = document.groups
        guard groups.indices.contains(from) else { return }
        var insertAt = row
        if row > from { insertAt -= 1 }
        insertAt = min(max(0, insertAt), groups.count - 1)
        guard insertAt != from else { return }
        let selectedId = document.groups.indices.contains(selectedGroupIndex)
            ? document.groups[selectedGroupIndex].id : nil
        let group = groups.remove(at: from)
        groups.insert(group, at: insertAt)
        if let selectedId, let idx = groups.firstIndex(where: { $0.id == selectedId }) {
            selectedGroupIndex = idx
            QuickAddPrefs.selectedGroupIndex = idx
        }
        var doc = document
        doc.groups = groups
        saveDocument(doc, success: "已调整分组顺序") {
            self.groupsTable.scrollRowToVisible(insertAt)
        }
    }

    // MARK: - 悬停修正

    // 滚动或行位置变化时不会产生鼠标进出事件，按真实鼠标位置重算表格内所有悬停状态
    private func refreshHover(in table: NSTableView) {
        table.enumerateAvailableRowViews { rowView, _ in
            (rowView as? LexiconHoverRowView)?.syncHover()
            Self.iconButtons(in: rowView).forEach { $0.syncHover() }
        }
    }

    // 拖动开始时清掉所有悬停，避免让位的行带着悬停底色移动
    private func clearHover(in table: NSTableView) {
        table.enumerateAvailableRowViews { rowView, _ in
            (rowView as? LexiconHoverRowView)?.clearHover()
            Self.iconButtons(in: rowView).forEach { $0.setHovered(false) }
        }
    }

    private static func iconButtons(in view: NSView) -> [LexiconIconButton] {
        view.subviews.flatMap { sub -> [LexiconIconButton] in
            if let button = sub as? LexiconIconButton { return [button] }
            return iconButtons(in: sub)
        }
    }

    @objc private func tableScrolled(_ note: Notification) {
        guard let clip = note.object as? NSClipView else { return }
        if clip === groupsScroll.contentView {
            refreshHover(in: groupsTable)
        } else if clip === entriesScroll.contentView {
            refreshHover(in: entriesTable)
        }
    }

    private func saveDocument(_ doc: UserDictDocument, success: String, after: (() -> Void)? = nil) {
        do {
            try UserDictWriter.saveActiveDocument(doc)
            UserDictWriter.markNeedsDeploy()
            tipLabel.textColor = .secondaryLabelColor
            tipLabel.stringValue = success
            reload()
            after?()
            maybeDeploy(successHint: success)
        } catch {
            tipLabel.textColor = .systemRed
            tipLabel.stringValue = error.localizedDescription
        }
    }

    // MARK: - Text field

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === textField {
            applyEncodedCode(for: textField.stringValue, to: codeField)
        } else if field === editingTextField, let editingCodeField {
            applyEncodedCode(for: field.stringValue, to: editingCodeField)
        }
    }

    // 词条变化时按单字码表重填编码
    private func applyEncodedCode(for word: String, to field: NSTextField) {
        let encoded = WubiDictEncoder.encode(word: word.trimmingCharacters(in: .whitespacesAndNewlines))
        if !encoded.isEmpty {
            field.stringValue = encoded
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

// 行悬停时铺一层淡色，选中行仍用系统高亮
private final class LexiconHoverRowView: NSTableRowView {
    private var hovered = false
    private var tracking: NSTrackingArea?
    private var updatingTracking = false

    func clearHover() {
        hovered = false
        needsDisplay = true
    }

    // 按真实鼠标位置重算悬停（只算可见部分）
    func syncHover() {
        let inside = isMouseInsideVisibleRect(self)
        guard inside != hovered else { return }
        hovered = inside
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // add/remove 会同步再进一次，不挡住就会在表格第一次铺行时栈溢出。
        guard !updatingTracking else { return }
        updatingTracking = true
        defer { updatingTracking = false }
        if let tracking { removeTrackingArea(tracking) }
        guard bounds.width > 0, bounds.height > 0 else {
            self.tracking = nil
            return
        }
        // 不要加 .inVisibleRect：和这里的移除/重建叠在一起会让 updateTrackingAreas 递归，一点进用户词就卡死。
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if hovered && !isSelected {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).setFill()
            bounds.fill()
        } else {
            super.drawBackground(in: dirtyRect)
        }
    }
}

// 图标悬停：手型、底色和更深的图标色
private final class LexiconIconButton: NSButton {
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var updatingTracking = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard !updatingTracking else { return }
        updatingTracking = true
        defer { updatingTracking = false }
        if let tracking { removeTrackingArea(tracking) }
        guard bounds.width > 0, bounds.height > 0 else {
            self.tracking = nil
            return
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    func setHovered(_ value: Bool) {
        hovered = value
        contentTintColor = value ? .labelColor : .secondaryLabelColor
        layer?.backgroundColor = value ? NSColor.labelColor.withAlphaComponent(0.12).cgColor : nil
    }

    // 按真实鼠标位置重算悬停（只算可见部分）
    func syncHover() {
        let inside = isMouseInsideVisibleRect(self)
        if inside != hovered { setHovered(inside) }
    }
}

// 鼠标当前是否落在视图的可见区域内
private func isMouseInsideVisibleRect(_ view: NSView) -> Bool {
    guard let window = view.window, !view.isHiddenOrHasHiddenAncestor else { return false }
    let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    return view.visibleRect.contains(point)
}

/// 拖动浮层：不参与点击与拖放命中，事件全部落到下面的表格
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 词条表：自己跟踪鼠标实现拖动排序，坐标均为表格坐标系
private final class ReorderTableView: NSTableView {
    var onReorderBegin: ((Int, NSPoint) -> Void)?
    var onReorderMove: ((NSPoint) -> Void)?
    var onReorderEnd: ((NSPoint, Bool) -> Void)?

    // 按下后移动超过阈值才算拖动；未拖动就松手时交还给系统，保持原有点击选中行为
    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        let row = row(at: start)
        guard row >= 0, event.clickCount == 1, onReorderBegin != nil, let window else {
            super.mouseDown(with: event)
            return
        }
        var dragging = false
        var last = start
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            switch next.type {
            case .leftMouseDragged:
                let point = convert(next.locationInWindow, from: nil)
                if !dragging {
                    guard hypot(point.x - start.x, point.y - start.y) >= 4 else { continue }
                    dragging = true
                    onReorderBegin?(row, start)
                }
                // 拖到边缘时自动滚动，滚动后重新换算坐标
                autoscroll(with: next)
                last = convert(next.locationInWindow, from: nil)
                onReorderMove?(last)
            case .leftMouseUp:
                if dragging {
                    onReorderEnd?(convert(next.locationInWindow, from: nil), false)
                } else {
                    window.postEvent(next, atStart: true)
                    super.mouseDown(with: event)
                }
                return
            case .keyDown where dragging && next.keyCode == 53:
                // Esc 取消拖动
                onReorderEnd?(last, true)
                return
            default:
                break
            }
        }
    }
}

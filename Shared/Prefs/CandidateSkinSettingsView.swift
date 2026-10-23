import AppKit
import UniformTypeIdentifiers

/// 外观页的皮肤编辑区；布局、配色与分享始终展开，修改立即写入共享偏好。
final class CandidateSkinSettingsView: NSView, NSTextFieldDelegate {
    private enum NumberField: Int {
        case paddingTop, paddingBottom, paddingLeft, paddingRight
        case offsetTop, offsetLeft
        case cornerRadius, spacing, indexSpacing
        case candidateSize, indexSize, codeSize, commentSize, borderWidth
        case shadowRadius, shadowX, shadowY
        case highlightRadius
        case highlightTop, highlightBottom, highlightLeft, highlightRight
    }

    private var root = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var numberInputs: [NumberField: NSTextField] = [:]
    // 示意图里的紧凑步进器，与输入框同步显示。
    private var steppers: [NumberField: NSStepper] = [:]
    // 主题卡片（内置 + 存储位），皮肤变化时刷新「当前」标记。
    private var themeCells: [ThemeSlotCell] = []
    private let themeStatusLabel = NSTextField(labelWithString: "")
    private var appearanceObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: IMEAppearancePrefs.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshThemeSelection()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    private func build() {
        numberInputs.removeAll()
        steppers.removeAll()
        root.removeFromSuperview()
        root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .fill
        root.spacing = 10
        root.setContentHuggingPriority(.required, for: .vertical)
        root.setContentCompressionResistancePriority(.required, for: .vertical)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let skin = IMEAppearancePrefs.skin

        root.addArrangedSubview(card(title: "主题", content: themeForm()))

        // 内边距与光标偏移用示意图呈现，数值控件摆在对应的边上。
        let diagram = CandidateSpacingDiagramView(
            paddingTop: compactNumber("上", value: skin.paddingTop, field: .paddingTop),
            paddingBottom: compactNumber("下", value: skin.paddingBottom, field: .paddingBottom),
            paddingLeft: compactNumber("左", value: skin.paddingLeft, field: .paddingLeft),
            paddingRight: compactNumber("右", value: skin.paddingRight, field: .paddingRight),
            offsetTop: compactNumber("距光标上", value: skin.offsetTop, field: .offsetTop),
            offsetLeft: compactNumber("距光标左", value: skin.offsetLeft, field: .offsetLeft),
            cornerRadius: compactNumber("圆角", value: skin.cornerRadius, field: .cornerRadius)
        )
        root.addArrangedSubview(card(title: "边距与位置", content: diagram))

        // 两列均分：间距一对、字号一对、粗细一对，避免序号间距被挤到窄列里看不见。
        let spacingCol = form([
            numberRow("候选间距", value: skin.itemSpacing, field: .spacing),
            numberRow("序号间距", value: skin.indexSpacing, field: .indexSpacing)
        ])
        let sizeCol = form([
            numberRow("候选字号", value: skin.candidateFontSize, field: .candidateSize),
            numberRow("序号字号", value: skin.indexFontSize, field: .indexSize),
            numberRow("编码字号", value: skin.codeFontSize, field: .codeSize)
        ])
        let weightCol = form([
            weightRow("候选粗细", fontName: skin.fontName, value: skin.candidateWeight, tag: 200),
            weightRow("序号粗细", fontName: skin.fontName, value: skin.indexWeight, tag: 201)
        ])
        let layoutBody = NSStackView(views: [
            twoColumns(spacingCol, sizeCol),
            weightCol
        ])
        layoutBody.orientation = .vertical
        layoutBody.alignment = .leading
        layoutBody.spacing = 8
        weightCol.widthAnchor.constraint(equalTo: layoutBody.widthAnchor).isActive = true
        root.addArrangedSubview(card(
            title: "布局细节",
            content: layoutBody
        ))

        // 备注：开关放在这里，字号、粗细和配色跟随皮肤一起保存与分享。
        root.addArrangedSubview(card(
            title: "备注",
            content: commentForm(skin)
        ))

        let colorCard = card(
            title: "明暗配色",
            content: pairedColorForm(light: skin.light, dark: skin.dark)
        )
        root.addArrangedSubview(colorCard)
        root.addArrangedSubview(card(
            title: "边框与阴影",
            content: shadowForm(skin)
        ))

        root.addArrangedSubview(card(
            title: "首选候选",
            content: twoColumns(highlightForm(skin), highlightColorForm(skin))
        ))

        let info = form([
            textRow("皮肤名称", value: skin.name, tag: 100),
            textRow("作者", value: skin.author, tag: 101)
        ])
        let shareBody = NSStackView(views: [info, sharingForm()])
        shareBody.orientation = .vertical
        shareBody.alignment = .leading
        shareBody.spacing = 10
        root.addArrangedSubview(card(
            title: "皮肤信息与分享",
            content: shareBody
        ))

        for view in root.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
    }

    // 主题：内置主题一行，下方 8 个存储位（2 行 × 4 列）；点击卡片即应用。
    private func themeForm() -> NSView {
        themeCells.removeAll()
        let presetCells = CandidateSkin.presets.enumerated().map { index, preset -> NSView in
            let cell = ThemeSlotCell(skin: preset, title: preset.name, caption: "内置", isSlot: false)
            cell.onApply = { [weak self] in self?.applyPreset(index) }
            themeCells.append(cell)
            return cell
        }
        let slotCells = IMEAppearancePrefs.skinSlots.enumerated().map { index, saved -> NSView in
            let cell = ThemeSlotCell(
                skin: saved,
                title: saved.map { $0.name.isEmpty ? "未命名" : $0.name } ?? "空位",
                caption: "\(index + 1)",
                isSlot: true
            )
            cell.onApply = { [weak self] in self?.applySlot(index) }
            cell.onSave = { [weak self] in self?.saveSlot(index) }
            cell.onClear = { [weak self] in self?.clearSlot(index) }
            themeCells.append(cell)
            return cell
        }

        let hint = NSTextField(labelWithString: "点击主题即可应用；「存入当前」把正在使用的外观保存到该位置。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        themeStatusLabel.stringValue = ""
        themeStatusLabel.font = .systemFont(ofSize: 11)
        themeStatusLabel.textColor = .secondaryLabelColor

        let presetGrid = grid(presetCells, columns: 4)
        let slotGrid = grid(slotCells, columns: 4)
        let stack = NSStackView(views: [
            sectionCaption("内置主题"),
            presetGrid,
            sectionCaption("我的主题"),
            slotGrid,
            hint,
            themeStatusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: presetGrid)
        presetGrid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        slotGrid.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        refreshThemeSelection()
        return stack
    }

    // 等宽网格：不足一行时用空视图补位，保证每格宽度一致。
    private func grid(_ items: [NSView], columns: Int) -> NSView {
        var rows: [NSView] = []
        var index = 0
        while index < items.count {
            var rowItems = Array(items[index..<min(index + columns, items.count)])
            while rowItems.count < columns {
                rowItems.append(NSView())
            }
            let row = NSStackView(views: rowItems)
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = 8
            rows.append(row)
            index += columns
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func sectionCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    // 与当前皮肤外观一致的卡片加强调色描边。
    private func refreshThemeSelection() {
        let current = IMEAppearancePrefs.skin
        for cell in themeCells {
            cell.isCurrent = cell.skin?.looksSame(as: current) ?? false
        }
    }

    private func applyPreset(_ index: Int) {
        guard CandidateSkin.presets.indices.contains(index) else { return }
        let preset = CandidateSkin.presets[index]
        IMEAppearancePrefs.applyPreset(preset)
        build()
        themeStatusLabel.stringValue = "已应用内置主题「\(preset.name)」。"
    }

    private func applySlot(_ index: Int) {
        guard let saved = IMEAppearancePrefs.skinSlots[index] else { return }
        IMEAppearancePrefs.applySkinSlot(index)
        build()
        themeStatusLabel.stringValue = "已应用位置 \(index + 1) 的主题「\(saved.name)」。"
    }

    private func saveSlot(_ index: Int) {
        // 已有内容时确认覆盖，避免误点丢失。
        if let existing = IMEAppearancePrefs.skinSlots[index] {
            let alert = NSAlert()
            alert.messageText = "覆盖位置 \(index + 1)？"
            alert.informativeText = "「\(existing.name)」会被当前外观替换。"
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        IMEAppearancePrefs.saveCurrentSkin(toSlot: index)
        build()
        themeStatusLabel.stringValue = "已保存到位置 \(index + 1)。"
    }

    private func clearSlot(_ index: Int) {
        guard let existing = IMEAppearancePrefs.skinSlots[index] else { return }
        let alert = NSAlert()
        alert.messageText = "清空位置 \(index + 1)？"
        alert.informativeText = "「\(existing.name)」将被删除，当前正在使用的外观不受影响。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        IMEAppearancePrefs.clearSkinSlot(index)
        build()
        themeStatusLabel.stringValue = "已清空位置 \(index + 1)。"
    }

    private func twoColumns(_ left: NSView, _ right: NSView) -> NSView {
        let columns = NSStackView(views: [left, right])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 12
        return columns
    }

    private func card(title: String, content: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let stack = NSStackView(views: [titleLabel, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // 背景和描边跟系统亮暗走，避免暗色下浅底配浅字。
        let container = AppearanceCardView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        container.setContentHuggingPriority(.required, for: .vertical)
        container.setContentCompressionResistancePriority(.required, for: .vertical)
        return container
    }

    private func form(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        return stack
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        // 加宽标签栏，避免「序号间距」等被截断。
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func textRow(_ title: String, value: String, tag: Int) -> NSView {
        let field = NSTextField(string: value)
        field.tag = tag
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return row(title, field)
    }

    // 数值输入框：回车提交，上下方向键步进。
    private func makeInput(value: Double, field: NumberField, width: CGFloat) -> NSTextField {
        let input = NSTextField(string: Self.numberString(value))
        input.tag = field.rawValue
        input.target = self
        input.action = #selector(numberChanged(_:))
        input.delegate = self
        input.alignment = .right
        input.widthAnchor.constraint(equalToConstant: width).isActive = true
        numberInputs[field] = input
        return input
    }

    // 示意图用的紧凑控件：说明文字在上，输入框 + 系统步进器在下。
    private func compactNumber(_ caption: String, value: Double, field: NumberField) -> NSView {
        let input = makeInput(value: value, field: field, width: 38)
        input.controlSize = .small
        input.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let stepper = NSStepper()
        stepper.controlSize = .small
        let range = Self.range(for: field)
        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = stepAmount(for: field)
        stepper.valueWraps = false
        stepper.doubleValue = value
        stepper.tag = field.rawValue
        stepper.target = self
        stepper.action = #selector(stepperChanged(_:))
        steppers[field] = stepper

        let controls = NSStackView(views: [input, stepper])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 1

        let label = NSTextField(labelWithString: caption)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, controls])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func numberRow(_ title: String, value: Double, field: NumberField) -> NSView {
        let input = makeInput(value: value, field: field, width: 44)

        let decrement = stepButton("−", field: field, increment: false)
        let increment = stepButton("+", field: field, increment: true)
        let controls = NSStackView(views: [decrement, input, increment])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 2
        return row(title, controls)
    }

    private func stepButton(
        _ title: String,
        field: NumberField,
        increment: Bool
    ) -> NSButton {
        let button = NSButton(
            title: title,
            target: self,
            action: #selector(stepNumber(_:))
        )
        button.tag = field.rawValue * 2 + (increment ? 1 : 0)
        button.bezelStyle = .roundRect
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        button.toolTip = increment ? "增加" : "减少"
        return button
    }

    private func weightRow(
        _ title: String,
        fontName: String,
        value: CandidateSkin.FontWeight,
        tag: Int
    ) -> NSView {
        let popup = NSPopUpButton()
        for weight in CandidateSkin.FontWeight.available(forFontName: fontName) {
            popup.addItem(withTitle: weight.title)
            popup.lastItem?.representedObject = weight.rawValue
        }
        let choices = CandidateSkin.FontWeight.available(forFontName: fontName)
        let shown = choices.contains(value) ? value : (choices.first ?? .regular)
        popup.selectItem(withTitle: shown.title)
        popup.tag = tag
        popup.target = self
        popup.action = #selector(weightChanged(_:))
        popup.widthAnchor.constraint(equalToConstant: 110).isActive = true
        return row(title, popup)
    }

    // 备注卡片：开关、字号、粗细与明暗配色。
    private func commentForm(_ skin: CandidateSkin) -> NSView {
        let enabled = NSButton(
            checkboxWithTitle: "显示候选备注",
            target: self,
            action: #selector(commentShownChanged(_:))
        )
        enabled.state = IMEAppearancePrefs.showCommentInPanel ? .on : .off
        enabled.toolTip = "显示 Rime 候选项自带的备注（comment 字段）"
        let hint = NSTextField(wrappingLabelWithString: "备注优先取 Rime 候选的 comment；没有时显示码表第四列的备注（云端扩展词库的备注写在这一列）。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 240
        let settings = form([
            enabled,
            numberRow("备注字号", value: skin.commentFontSize, field: .commentSize),
            weightRow("备注粗细", fontName: skin.fontName, value: skin.commentWeight, tag: 203),
            hint
        ])
        return twoColumns(settings, commentColorForm(skin))
    }

    // 备注配色：普通行与首选高亮行各一列。
    private func commentColorForm(_ skin: CandidateSkin) -> NSView {
        colorColumns([
            ("备注", skin.light.commentText, skin.dark.commentText, 10),
            ("首选备注", skin.light.highlightCommentText, skin.dark.highlightCommentText, 11)
        ])
    }

    private func pairedColorForm(
        light: CandidateSkin.Colors,
        dark: CandidateSkin.Colors
    ) -> NSView {
        // 横排均分：每列一项配色，上行亮色、下行暗色。
        colorColumns([
            ("背景", light.background, dark.background, 0),
            ("候选词", light.candidateText, dark.candidateText, 1),
            ("序号", light.indexText, dark.indexText, 2),
            ("编码", light.codeText, dark.codeText, 8),
            ("边框", light.border, dark.border, 3),
            ("阴影", light.shadow, dark.shadow, 4)
        ])
    }

    // 首选配色：颜色槽位 5–7，暗色为 +100。
    private func highlightColorForm(_ skin: CandidateSkin) -> NSView {
        colorColumns([
            ("高亮背景", skin.light.highlightBackground, skin.dark.highlightBackground, 5),
            ("首选文字", skin.light.highlightText, skin.dark.highlightText, 6),
            ("首选序号", skin.light.highlightIndexText, skin.dark.highlightIndexText, 7),
            ("首选编码", skin.light.highlightCodeText, skin.dark.highlightCodeText, 9)
        ])
    }

    // 配色表：左列亮/暗标签，右侧各色横排均分。
    private func colorColumns(
        _ entries: [(String, CandidateSkin.RGBAColor, CandidateSkin.RGBAColor, Int)]
    ) -> NSView {
        let titleSpacer = centeredLabel(" ")
        let lightLegend = centeredLabel("亮色")
        let darkLegend = centeredLabel("暗色")
        // 与右侧色块同高，保证「亮色/暗色」垂直对齐。
        lightLegend.heightAnchor.constraint(equalToConstant: 22).isActive = true
        darkLegend.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let legend = NSStackView(views: [titleSpacer, lightLegend, darkLegend])
        legend.orientation = .vertical
        legend.alignment = .trailing
        legend.spacing = 8
        legend.setContentHuggingPriority(.required, for: .horizontal)

        let columns = entries.map { title, lightColor, darkColor, tag -> NSView in
            let titleLabel = centeredLabel(title)
            let lightWell = colorWell(lightColor, tag: tag)
            let darkWell = colorWell(darkColor, tag: tag + 100)
            let col = NSStackView(views: [titleLabel, lightWell, darkWell])
            col.orientation = .vertical
            col.alignment = .centerX
            col.spacing = 8
            col.distribution = .fill
            // 色块随列宽拉伸，横排时更整齐。
            lightWell.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
            darkWell.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
            return col
        }

        let colors = NSStackView(views: columns)
        colors.orientation = .horizontal
        colors.alignment = .top
        colors.distribution = .fillEqually
        colors.spacing = 12

        let row = NSStackView(views: [legend, colors])
        row.orientation = .horizontal
        row.alignment = .top
        // 默认 gravityAreas 不会拉伸子视图，改为 fill 让色块区占满剩余宽度后均分
        row.distribution = .fill
        row.spacing = 10
        colors.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func colorWell(_ color: CandidateSkin.RGBAColor, tag: Int) -> NSView {
        let swatch = ColorSwatchButton(color: color.nsColor)
        swatch.tag = tag
        swatch.target = self
        swatch.action = #selector(colorChanged(_:))
        swatch.setContentHuggingPriority(.defaultLow, for: .horizontal)
        swatch.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return swatch
    }

    private func centeredLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 11, weight: .medium)
        return label
    }

    private func shadowForm(_ skin: CandidateSkin) -> NSView {
        let enabled = NSButton(
            checkboxWithTitle: "自定义阴影",
            target: self,
            action: #selector(shadowEnabledChanged(_:))
        )
        enabled.state = skin.shadowEnabled ? .on : .off
        return form([
            enabled,
            numberRow("边框宽度", value: skin.borderWidth, field: .borderWidth),
            numberRow("阴影模糊", value: skin.shadowRadius, field: .shadowRadius),
            numberRow("阴影 X", value: skin.shadowOffsetX, field: .shadowX),
            numberRow("阴影 Y", value: skin.shadowOffsetY, field: .shadowY)
        ])
    }

    // 首选候选开关、圆角、留白与字重。
    private func highlightForm(_ skin: CandidateSkin) -> NSView {
        let enabled = NSButton(
            checkboxWithTitle: "首选使用高亮样式",
            target: self,
            action: #selector(highlightEnabledChanged(_:))
        )
        enabled.state = skin.highlightEnabled ? .on : .off
        let hint = NSTextField(wrappingLabelWithString: "首位候选（空格上屏）单独着色；留白对所有候选生效，保证间距与行高一致。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 240
        // 四边留白用示意图摆放，与「边距与位置」一致。
        let padding = HighlightPaddingDiagramView(
            top: compactNumber("上", value: skin.highlightPaddingTop, field: .highlightTop),
            bottom: compactNumber("下", value: skin.highlightPaddingBottom, field: .highlightBottom),
            left: compactNumber("左", value: skin.highlightPaddingLeft, field: .highlightLeft),
            right: compactNumber("右", value: skin.highlightPaddingRight, field: .highlightRight)
        )
        return form([
            enabled,
            numberRow("高亮圆角", value: skin.highlightCornerRadius, field: .highlightRadius),
            weightRow("首选粗细", fontName: skin.fontName, value: skin.highlightWeight, tag: 202),
            padding,
            hint
        ])
    }

    private func sharingForm() -> NSView {
        let exportFile = NSButton(title: "导出到文件", target: self, action: #selector(exportToFile))
        let importFile = NSButton(title: "从文件导入", target: self, action: #selector(importFromFile))
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetConfig))
        let fileRow = NSStackView(views: [exportFile, importFile, reset])
        fileRow.orientation = .horizontal
        fileRow.spacing = 8
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        let stack = NSStackView(views: [fileRow, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        IMEAppearancePrefs.updateSkin {
            if field.tag == 100 {
                $0.name = field.stringValue
            } else if field.tag == 101 {
                $0.author = field.stringValue
            }
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard let input = control as? NSTextField,
              let field = NumberField(rawValue: input.tag),
              commandSelector == #selector(NSResponder.moveUp(_:))
                || commandSelector == #selector(NSResponder.moveDown(_:))
        else {
            return false
        }
        let current = Double(input.stringValue) ?? numberValue(for: field)
        let direction = commandSelector == #selector(NSResponder.moveUp(_:)) ? 1.0 : -1.0
        setNumber(field, value: current + direction * stepAmount(for: field))
        syncInputs(field)
        input.selectText(nil)
        return true
    }

    // 按已保存（已收敛）的值刷新输入框与步进器。
    private func syncInputs(_ field: NumberField) {
        let value = numberValue(for: field)
        numberInputs[field]?.stringValue = Self.numberString(value)
        steppers[field]?.doubleValue = value
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        guard let field = NumberField(rawValue: sender.tag) else { return }
        setNumber(field, value: sender.doubleValue)
        syncInputs(field)
    }

    @objc private func highlightEnabledChanged(_ sender: NSButton) {
        IMEAppearancePrefs.updateSkin { $0.highlightEnabled = sender.state == .on }
    }

    // 备注显示开关单独存偏好，切换后候选条立即重排。
    @objc private func commentShownChanged(_ sender: NSButton) {
        IMEAppearancePrefs.showCommentInPanel = sender.state == .on
    }

    // 与 CandidateSkin.normalized 的取值范围保持一致，供步进器限位。
    private static func range(for field: NumberField) -> ClosedRange<Double> {
        switch field {
        case .paddingTop, .paddingBottom: return 0...30
        case .paddingLeft, .paddingRight: return 0...40
        case .offsetTop: return -40...80
        case .offsetLeft: return -80...80
        case .cornerRadius: return 0...30
        case .indexSpacing: return 0...20
        case .codeSize: return 8...32
        case .commentSize: return 8...32
        case .highlightRadius, .highlightTop, .highlightBottom, .highlightLeft, .highlightRight:
            return 0...20
        default: return 0...100
        }
    }

    @objc private func weightChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let weight = CandidateSkin.FontWeight(rawValue: raw) else { return }
        IMEAppearancePrefs.updateSkin {
            switch sender.tag {
            case 200: $0.candidateWeight = weight
            case 202: $0.highlightWeight = weight
            case 203: $0.commentWeight = weight
            default: $0.indexWeight = weight
            }
        }
    }

    @objc private func numberChanged(_ sender: NSTextField) {
        guard let field = NumberField(rawValue: sender.tag),
              let value = Double(sender.stringValue) else {
            NSSound.beep()
            return
        }
        setNumber(field, value: value)
        syncInputs(field)
    }

    @objc private func stepNumber(_ sender: NSButton) {
        guard let field = NumberField(rawValue: sender.tag / 2) else { return }
        let direction = sender.tag.isMultiple(of: 2) ? -1.0 : 1.0
        setNumber(
            field,
            value: numberValue(for: field) + direction * stepAmount(for: field)
        )
        syncInputs(field)
    }

    private func stepAmount(for field: NumberField) -> Double {
        field == .borderWidth ? 0.5 : 1
    }

    private func setNumber(_ field: NumberField, value: Double) {
        IMEAppearancePrefs.updateSkin {
            switch field {
            case .paddingTop: $0.paddingTop = value
            case .paddingBottom: $0.paddingBottom = value
            case .paddingLeft: $0.paddingLeft = value
            case .paddingRight: $0.paddingRight = value
            case .offsetTop: $0.offsetTop = value
            case .offsetLeft: $0.offsetLeft = value
            case .cornerRadius: $0.cornerRadius = value
            case .spacing: $0.itemSpacing = value
            case .indexSpacing: $0.indexSpacing = value
            case .candidateSize: $0.candidateFontSize = value
            case .indexSize: $0.indexFontSize = value
            case .codeSize: $0.codeFontSize = value
            case .commentSize: $0.commentFontSize = value
            case .borderWidth: $0.borderWidth = value
            case .shadowRadius: $0.shadowRadius = value
            case .shadowX: $0.shadowOffsetX = value
            case .shadowY: $0.shadowOffsetY = value
            case .highlightRadius: $0.highlightCornerRadius = value
            case .highlightTop: $0.highlightPaddingTop = value
            case .highlightBottom: $0.highlightPaddingBottom = value
            case .highlightLeft: $0.highlightPaddingLeft = value
            case .highlightRight: $0.highlightPaddingRight = value
            }
        }
    }

    @objc private func shadowEnabledChanged(_ sender: NSButton) {
        IMEAppearancePrefs.updateSkin { $0.shadowEnabled = sender.state == .on }
    }

    @objc private func colorChanged(_ sender: ColorSwatchButton) {
        let color = CandidateSkin.RGBAColor(sender.color)
        // 暗色槽位统一加 100，槽位号用余数取回，便于继续扩充颜色项。
        let dark = sender.tag >= 100
        let slot = sender.tag % 100
        IMEAppearancePrefs.updateSkin {
            if dark {
                Self.setColor(color, slot: slot, colors: &$0.dark)
            } else {
                Self.setColor(color, slot: slot, colors: &$0.light)
            }
        }
    }

    @objc private func exportToFile() {
        do {
            let json = try IMEAppearancePrefs.exportedSkinJSON()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            let skinName = IMEAppearancePrefs.skin.name
            let safeName = skinName.isEmpty ? "meifeng-skin" : skinName
            panel.nameFieldStringValue = "\(safeName).json"
            panel.title = "导出皮肤配置"
            let finish: (NSApplication.ModalResponse) -> Void = { [weak self] result in
                guard result == .OK, let url = panel.url else { return }
                do {
                    try json.write(to: url, atomically: true, encoding: .utf8)
                    self?.statusLabel.stringValue = "已导出到 \(url.lastPathComponent)"
                } catch {
                    self?.show(error.localizedDescription)
                }
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        } catch {
            show(error.localizedDescription)
        }
    }

    @objc private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "导入皮肤配置"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let json = try String(contentsOf: url, encoding: .utf8)
                try IMEAppearancePrefs.importSkinJSON(json)
                self?.build()
                self?.statusLabel.stringValue = "已从 \(url.lastPathComponent) 导入。"
            } catch {
                self?.show(error.localizedDescription)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    @objc private func resetConfig() {
        let alert = NSAlert()
        alert.messageText = "恢复默认皮肤？"
        alert.informativeText = "当前皮肤的名称、作者和所有外观参数都会被替换。"
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        IMEAppearancePrefs.restoreDefaultSkin()
        build()
        statusLabel.stringValue = "已恢复默认皮肤。"
    }

    private func numberValue(for field: NumberField) -> Double {
        let skin = IMEAppearancePrefs.skin
        switch field {
        case .paddingTop: return skin.paddingTop
        case .paddingBottom: return skin.paddingBottom
        case .paddingLeft: return skin.paddingLeft
        case .paddingRight: return skin.paddingRight
        case .offsetTop: return skin.offsetTop
        case .offsetLeft: return skin.offsetLeft
        case .cornerRadius: return skin.cornerRadius
        case .spacing: return skin.itemSpacing
        case .indexSpacing: return skin.indexSpacing
        case .candidateSize: return skin.candidateFontSize
        case .indexSize: return skin.indexFontSize
        case .codeSize: return skin.codeFontSize
        case .commentSize: return skin.commentFontSize
        case .borderWidth: return skin.borderWidth
        case .shadowRadius: return skin.shadowRadius
        case .shadowX: return skin.shadowOffsetX
        case .shadowY: return skin.shadowOffsetY
        case .highlightRadius: return skin.highlightCornerRadius
        case .highlightTop: return skin.highlightPaddingTop
        case .highlightBottom: return skin.highlightPaddingBottom
        case .highlightLeft: return skin.highlightPaddingLeft
        case .highlightRight: return skin.highlightPaddingRight
        }
    }

    private static func setColor(
        _ value: CandidateSkin.RGBAColor,
        slot: Int,
        colors: inout CandidateSkin.Colors
    ) {
        switch slot {
        case 0: colors.background = value
        case 1: colors.candidateText = value
        case 2: colors.indexText = value
        case 3: colors.border = value
        case 4: colors.shadow = value
        case 5: colors.highlightBackground = value
        case 6: colors.highlightText = value
        case 7: colors.highlightIndexText = value
        case 8: colors.codeText = value
        case 9: colors.highlightCodeText = value
        case 10: colors.commentText = value
        case 11: colors.highlightCommentText = value
        default: break
        }
    }

    private func show(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "皮肤配置"
        alert.informativeText = message
        alert.runModal()
    }

    private static func numberString(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// 外观页卡片：图层颜色在创建时会按当时的外观固化，亮暗切换后必须重绘。
private final class AppearanceCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        refreshChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    // 在当前外观下解析动态色，再写进图层。
    private func refreshChrome() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
}

/// 边距示意图：左上角为光标，箭头标出候选条相对光标的偏移；
/// 候选条内侧着色区域为内边距，四个数值控件分别摆在对应的边上。
private final class CandidateSpacingDiagramView: NSView {
    private static let caretX: CGFloat = 22
    private static let caretTop: CGFloat = 12
    private static let caretHeight: CGFloat = 20

    private let barGuide = NSLayoutGuide()
    private let contentGuide = NSLayoutGuide()
    private let offsetLeftControl: NSView

    override var isFlipped: Bool { true }

    init(
        paddingTop: NSView,
        paddingBottom: NSView,
        paddingLeft: NSView,
        paddingRight: NSView,
        offsetTop: NSView,
        offsetLeft: NSView,
        cornerRadius: NSView
    ) {
        offsetLeftControl = offsetLeft
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addLayoutGuide(barGuide)
        addLayoutGuide(contentGuide)
        for control in [paddingTop, paddingBottom, paddingLeft, paddingRight, offsetTop, offsetLeft, cornerRadius] {
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
        }

        let caretBottom = Self.caretTop + Self.caretHeight
        NSLayoutConstraint.activate([
            // 光标偏移：上方控件夹在光标与候选条之间，左侧控件夹在光标竖线与候选条左边之间。
            offsetTop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.caretX + 10),
            offsetTop.topAnchor.constraint(equalTo: topAnchor, constant: caretBottom + 8),
            barGuide.topAnchor.constraint(equalTo: offsetTop.bottomAnchor, constant: 10),
            offsetLeft.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.caretX + 10),
            offsetLeft.centerYAnchor.constraint(equalTo: barGuide.centerYAnchor, constant: 12),
            barGuide.leadingAnchor.constraint(equalTo: offsetLeft.trailingAnchor, constant: 12),
            barGuide.leadingAnchor.constraint(greaterThanOrEqualTo: offsetTop.trailingAnchor, constant: 8),
            barGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            barGuide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            // 内边距：四个控件贴着候选条四边，中间留出内容区。
            paddingTop.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor),
            paddingTop.topAnchor.constraint(equalTo: barGuide.topAnchor, constant: 6),
            contentGuide.topAnchor.constraint(equalTo: paddingTop.bottomAnchor, constant: 6),
            paddingBottom.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor),
            paddingBottom.bottomAnchor.constraint(equalTo: barGuide.bottomAnchor, constant: -6),
            contentGuide.bottomAnchor.constraint(equalTo: paddingBottom.topAnchor, constant: -6),
            paddingLeft.leadingAnchor.constraint(equalTo: barGuide.leadingAnchor, constant: 8),
            paddingLeft.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            contentGuide.leadingAnchor.constraint(equalTo: paddingLeft.trailingAnchor, constant: 8),
            paddingRight.trailingAnchor.constraint(equalTo: barGuide.trailingAnchor, constant: -8),
            paddingRight.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
            contentGuide.trailingAnchor.constraint(equalTo: paddingRight.leadingAnchor, constant: -8),
            // 圆角：放在候选条右上角。
            cornerRadius.trailingAnchor.constraint(equalTo: barGuide.trailingAnchor, constant: -10),
            cornerRadius.topAnchor.constraint(equalTo: barGuide.topAnchor, constant: 6),
            contentGuide.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            contentGuide.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
        setContentHuggingPriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let bar = barGuide.frame
        let content = contentGuide.frame
        let caretX = Self.caretX
        let caretTop = Self.caretTop
        let caretBottom = caretTop + Self.caretHeight

        // 候选条：着色部分即内边距区域。
        let barPath = NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10)
        accent.withAlphaComponent(0.10).setFill()
        barPath.fill()
        accent.withAlphaComponent(0.55).setStroke()
        barPath.lineWidth = 1
        barPath.stroke()
        drawCaption("内边距", at: NSPoint(x: bar.minX + 8, y: bar.minY + 5), color: accent)

        // 右上角加粗圆弧，提示旁边的数值对应候选条圆角。
        let corner = NSBezierPath()
        corner.appendArc(
            withCenter: NSPoint(x: bar.maxX - 10, y: bar.minY + 10),
            radius: 10,
            startAngle: 270,
            endAngle: 0,
            clockwise: false
        )
        corner.lineWidth = 2.5
        accent.setStroke()
        corner.stroke()

        // 内容区：虚线框 + 说明文字。
        let contentPath = NSBezierPath(roundedRect: content, xRadius: 5, yRadius: 5)
        NSColor.controlBackgroundColor.setFill()
        contentPath.fill()
        NSColor.tertiaryLabelColor.setStroke()
        contentPath.setLineDash([4, 3], count: 2, phase: 0)
        contentPath.stroke()
        let text = NSAttributedString(string: "候选内容", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: content.midX - size.width / 2, y: content.midY - size.height / 2))

        // 光标：I 形竖线。
        let caret = NSBezierPath()
        caret.move(to: NSPoint(x: caretX, y: caretTop))
        caret.line(to: NSPoint(x: caretX, y: caretBottom))
        caret.move(to: NSPoint(x: caretX - 3, y: caretTop))
        caret.line(to: NSPoint(x: caretX + 3, y: caretTop))
        caret.move(to: NSPoint(x: caretX - 3, y: caretBottom))
        caret.line(to: NSPoint(x: caretX + 3, y: caretBottom))
        caret.lineWidth = 1.5
        NSColor.labelColor.setStroke()
        caret.stroke()
        drawCaption("光标", at: NSPoint(x: caretX + 8, y: caretTop + 3), color: .secondaryLabelColor)

        // 虚线延长线：候选条顶边向左延伸到光标竖线，光标竖线向下延伸到水平箭头。
        let arrowY = offsetLeftControl.frame.minY - 6
        let guides = NSBezierPath()
        guides.move(to: NSPoint(x: caretX, y: bar.minY))
        guides.line(to: NSPoint(x: bar.minX, y: bar.minY))
        guides.move(to: NSPoint(x: caretX, y: bar.minY))
        guides.line(to: NSPoint(x: caretX, y: arrowY))
        guides.setLineDash([3, 3], count: 2, phase: 0)
        guides.lineWidth = 1
        NSColor.tertiaryLabelColor.setStroke()
        guides.stroke()

        // 尺寸箭头：竖向为距光标上，横向为距光标左。
        accent.setStroke()
        accent.setFill()
        drawDimension(from: NSPoint(x: caretX, y: caretBottom + 2), to: NSPoint(x: caretX, y: bar.minY - 1))
        drawDimension(from: NSPoint(x: caretX + 1, y: arrowY), to: NSPoint(x: bar.minX - 1, y: arrowY))
    }

    private func drawCaption(_ string: String, at point: NSPoint, color: NSColor) {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: color
        ]).draw(at: point)
    }

    // 两端带箭头的尺寸线。
    private func drawDimension(from start: NSPoint, to end: NSPoint) {
        let line = NSBezierPath()
        line.move(to: start)
        line.line(to: end)
        line.lineWidth = 1
        line.stroke()
        drawArrowHead(at: end, from: start)
        drawArrowHead(at: start, from: end)
    }

    private func drawArrowHead(at tip: NSPoint, from tail: NSPoint) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length: CGFloat = 5
        let spread: CGFloat = .pi / 7
        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: NSPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)))
        head.line(to: NSPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
        head.close()
        head.fill()
    }
}

/// 首选留白示意图：着色圆角块代表首选高亮背景，四个数值控件摆在对应的边上。
private final class HighlightPaddingDiagramView: NSView {
    private let pillGuide = NSLayoutGuide()
    private let textGuide = NSLayoutGuide()

    override var isFlipped: Bool { true }

    init(top: NSView, bottom: NSView, left: NSView, right: NSView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addLayoutGuide(pillGuide)
        addLayoutGuide(textGuide)
        for control in [top, bottom, left, right] {
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 240),
            pillGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            pillGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            pillGuide.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            pillGuide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            top.centerXAnchor.constraint(equalTo: textGuide.centerXAnchor),
            top.topAnchor.constraint(equalTo: pillGuide.topAnchor, constant: 5),
            textGuide.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 5),
            bottom.centerXAnchor.constraint(equalTo: textGuide.centerXAnchor),
            bottom.bottomAnchor.constraint(equalTo: pillGuide.bottomAnchor, constant: -5),
            textGuide.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -5),
            left.leadingAnchor.constraint(equalTo: pillGuide.leadingAnchor, constant: 8),
            left.centerYAnchor.constraint(equalTo: textGuide.centerYAnchor),
            textGuide.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 8),
            right.trailingAnchor.constraint(equalTo: pillGuide.trailingAnchor, constant: -8),
            right.centerYAnchor.constraint(equalTo: textGuide.centerYAnchor),
            textGuide.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -8),
            textGuide.heightAnchor.constraint(greaterThanOrEqualToConstant: 26)
        ])
        setContentHuggingPriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let pill = NSBezierPath(roundedRect: pillGuide.frame, xRadius: 8, yRadius: 8)
        accent.withAlphaComponent(0.16).setFill()
        pill.fill()
        accent.withAlphaComponent(0.6).setStroke()
        pill.lineWidth = 1
        pill.stroke()

        // 中间虚线框代表首选文字。
        let rect = textGuide.frame
        let box = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.controlBackgroundColor.setFill()
        box.fill()
        NSColor.tertiaryLabelColor.setStroke()
        box.setLineDash([4, 3], count: 2, phase: 0)
        box.stroke()
        let text = NSAttributedString(string: "1.五", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}

/// 颜色色块：点击后直接驱动系统颜色面板回调，不依赖 NSColorWell 的激活机制；
/// 颜色按 RGB(A) 存储，半透明时底部显示棋盘格便于辨认。
private final class ColorSwatchButton: NSControl {
    var color: NSColor {
        didSet { needsDisplay = true }
    }
    private var isEditing = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 22))
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = "点击选择颜色"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        // 宽度交给外层均分列决定，高度保持色块观感。
        NSSize(width: NSView.noIntrinsicMetric, height: 22)
    }

    override func mouseDown(with event: NSEvent) {
        ColorPanelCoordinator.shared.begin(editing: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // 面板选中时高亮描边，面板关闭或切到其他色块时取消。
    func setEditing(_ editing: Bool) {
        isEditing = editing
    }

    // 面板颜色变化：更新色块并按普通控件方式发送 action。
    func applyPanelColor(_ newColor: NSColor) {
        color = newColor
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor.white.setFill()
        rect.fill()
        NSColor(white: 0.8, alpha: 1).setFill()
        let cell: CGFloat = 5
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : cell)
            while x < rect.maxX {
                NSRect(x: x, y: y, width: cell, height: cell).fill()
                x += cell * 2
            }
            y += cell
            row += 1
        }
        color.setFill()
        rect.fill(using: .sourceOver)
        NSGraphicsContext.restoreGraphicsState()

        if isEditing {
            NSColor.controlAccentColor.setStroke()
            shape.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            shape.lineWidth = 1
        }
        shape.stroke()
    }
}

/// 统一管理系统颜色面板：记录当前编辑的色块，面板颜色变化时回写。
private final class ColorPanelCoordinator: NSObject {
    static let shared = ColorPanelCoordinator()

    private weak var swatch: ColorSwatchButton?
    private var closeObserver: NSObjectProtocol?

    func begin(editing target: ColorSwatchButton) {
        swatch?.setEditing(false)
        swatch = target
        target.setEditing(true)
        // 结束输入框编辑，避免颜色面板把 changeColor: 发给字段编辑器改了文字颜色。
        target.window?.makeFirstResponder(nil)

        let panel = NSColorPanel.shared
        // 先断开回调再设初始色，防止把新色块的颜色写回上一个色块。
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = true
        panel.mode = .HSB
        panel.isContinuous = true
        panel.color = target.color
        panel.setTarget(self)
        panel.setAction(#selector(panelColorChanged(_:)))
        // 设置窗口是浮动层级，颜色面板需要再高一级才不会被挡住。
        let base = max(target.window?.level.rawValue ?? 0, NSWindow.Level.floating.rawValue)
        panel.level = NSWindow.Level(rawValue: base + 1)
        panel.orderFront(nil)

        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                self?.swatch?.setEditing(false)
                self?.swatch = nil
            }
        }
    }

    @objc private func panelColorChanged(_ sender: NSColorPanel) {
        swatch?.applyPanelColor(sender.color)
    }
}

/// 主题卡片：缩略图 + 名称；点击卡片应用，存储位额外带「存入当前」与清空按钮。
private final class ThemeSlotCell: NSView {
    let skin: CandidateSkin?
    var onApply: (() -> Void)?
    var onSave: (() -> Void)?
    var onClear: (() -> Void)?
    var isCurrent = false {
        didSet { updateChrome() }
    }

    init(skin: CandidateSkin?, title: String, caption: String, isSlot: Bool) {
        self.skin = skin
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        let thumbnail = SkinThumbnailView(skin: skin)
        thumbnail.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = skin == nil ? .tertiaryLabelColor : .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = .systemFont(ofSize: 10, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.setContentHuggingPriority(.required, for: .horizontal)
        var headerViews: [NSView] = [titleLabel, captionLabel]
        // 已保存的存储位才显示清空按钮。
        if isSlot, skin != nil {
            let clear = NSButton(
                image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "清空") ?? NSImage(),
                target: self,
                action: #selector(clearTapped)
            )
            clear.isBordered = false
            clear.contentTintColor = .tertiaryLabelColor
            clear.toolTip = "清空此位置"
            clear.setContentHuggingPriority(.required, for: .horizontal)
            headerViews.append(clear)
        }
        let header = NSStackView(views: headerViews)
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 4

        var views: [NSView] = [thumbnail, header]
        var saveButton: NSButton?
        if isSlot {
            let save = NSButton(title: "存入当前", target: self, action: #selector(saveTapped))
            save.controlSize = .small
            save.font = .systemFont(ofSize: 11)
            views.append(save)
            saveButton = save
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            thumbnail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        saveButton?.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        toolTip = skin == nil ? "空位：点击「存入当前」保存正在使用的外观" : "点击应用「\(title)」"
        updateChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func mouseDown(with event: NSEvent) {
        guard skin != nil else { return }
        onApply?()
    }

    override func resetCursorRects() {
        if skin != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    // 当前使用中的主题用强调色描边，其余为分隔线色。
    private func updateChrome() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderWidth = isCurrent ? 2 : 1
            layer?.borderColor = (isCurrent ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
    }

    @objc private func saveTapped() {
        onSave?()
    }

    @objc private func clearTapped() {
        onClear?()
    }
}

/// 主题缩略图：按主题配色画一条迷你候选条（跟随系统亮暗），空位画虚线框。
private final class SkinThumbnailView: NSView {
    private let skin: CandidateSkin?

    init(skin: CandidateSkin?) {
        self.skin = skin
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 3)
        guard let skin else {
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.lineWidth = 1
            NSColor.tertiaryLabelColor.setStroke()
            path.stroke()
            let text = NSAttributedString(string: "未保存", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return
        }

        let colors = skin.colors(for: effectiveAppearance)
        let radius = min(CGFloat(skin.cornerRadius), rect.height / 2)
        let bar = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        colors.background.nsColor.setFill()
        bar.fill()
        if skin.borderWidth > 0 {
            colors.border.nsColor.setStroke()
            bar.lineWidth = CGFloat(min(skin.borderWidth, 2))
            bar.stroke()
        }

        // 固定缩略字号，只体现配色、高亮与字重。
        let samples = ["五", "吾", "伍", "捂"]
        var x = rect.minX + 5
        for (i, word) in samples.enumerated() {
            let highlighted = skin.highlightEnabled && i == 0
            let index = NSAttributedString(string: "\(i + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: skin.indexWeight.nsWeight),
                .foregroundColor: (highlighted ? colors.highlightIndexText : colors.indexText).nsColor
            ])
            let text = NSAttributedString(string: word, attributes: [
                .font: NSFont.systemFont(
                    ofSize: 12,
                    weight: (highlighted ? skin.highlightWeight : skin.candidateWeight).nsWeight
                ),
                .foregroundColor: (highlighted ? colors.highlightText : colors.candidateText).nsColor
            ])
            let indexSize = index.size()
            let textSize = text.size()
            let itemWidth = indexSize.width + 2 + textSize.width + 8
            guard x + itemWidth <= rect.maxX - 3 else { break }
            if highlighted {
                let pillRect = NSRect(x: x, y: rect.midY - 9, width: itemWidth, height: 18)
                let pillRadius = min(CGFloat(skin.highlightCornerRadius), 9)
                colors.highlightBackground.nsColor.setFill()
                NSBezierPath(roundedRect: pillRect, xRadius: pillRadius, yRadius: pillRadius).fill()
            }
            index.draw(at: NSPoint(x: x + 4, y: rect.midY - indexSize.height / 2))
            text.draw(at: NSPoint(x: x + 4 + indexSize.width + 2, y: rect.midY - textSize.height / 2))
            x += itemWidth + 2
        }
    }
}

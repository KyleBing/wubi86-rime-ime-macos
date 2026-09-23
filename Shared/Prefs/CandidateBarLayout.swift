import AppKit

/// 候选条内容排版：实际候选窗与设置页预览共用同一套代码，保证两边尺寸、内边距完全一致。
enum CandidateBarLayout {
    // 把 stack 以皮肤内边距贴进 chrome 背景内侧，返回四边约束供后续更新。
    static func pin(
        _ stack: NSStackView,
        in chrome: RoundedChromeView
    ) -> (top: NSLayoutConstraint, bottom: NSLayoutConstraint, leading: NSLayoutConstraint, trailing: NSLayoutConstraint) {
        stack.translatesAutoresizingMaskIntoConstraints = false
        chrome.effectView.addSubview(stack)
        let host = chrome.effectView
        let constraints = (
            top: stack.topAnchor.constraint(equalTo: host.topAnchor),
            bottom: stack.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            leading: stack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailing: stack.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        )
        NSLayoutConstraint.activate([constraints.top, constraints.bottom, constraints.leading, constraints.trailing])
        return constraints
    }

    // 按当前皮肤重建候选条内容；onSelect 为 nil 时（预览）行不可点击。
    static func populate(
        _ stack: NSStackView,
        padding: (top: NSLayoutConstraint, bottom: NSLayoutConstraint, leading: NSLayoutConstraint, trailing: NSLayoutConstraint),
        candidates: [String],
        preedit: String,
        colors: CandidateSkin.Colors,
        onSelect: ((Int) -> Void)?
    ) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let skin = IMEAppearancePrefs.skin
        let dotsOnly = IMEAppearancePrefs.showCountDotsOnly
        let vertical = IMEAppearancePrefs.orientation == .vertical && !dotsOnly
        let fontSize = CGFloat(skin.candidateFontSize)
        let rowHeight = ceil(max(fontSize, CGFloat(skin.indexFontSize)) * 1.35)

        stack.edgeInsets = .init()
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = dotsOnly ? dotSpacing : CGFloat(skin.itemSpacing)

        if dotsOnly {
            // 圆点条整体高 8pt：4pt 圆点 + 上下各 2pt。
            let inset = (dotBarHeight - dotDiameter) / 2
            padding.top.constant = inset
            padding.bottom.constant = -inset
            padding.leading.constant = dotBarHeight / 2
            padding.trailing.constant = -dotBarHeight / 2
            for i in candidates.indices {
                let highlighted = skin.highlightEnabled && i == 0
                let dot = countDot(
                    index: i,
                    color: highlighted ? colors.highlightBackground.nsColor : colors.candidateText.nsColor,
                    onSelect: onSelect
                )
                dot.isHighlighted = highlighted
                stack.addArrangedSubview(dot)
            }
            return
        }

        padding.top.constant = CGFloat(skin.paddingTop)
        padding.bottom.constant = -CGFloat(skin.paddingBottom)
        padding.leading.constant = CGFloat(skin.paddingLeft)
        padding.trailing.constant = -CGFloat(skin.paddingRight)

        if IMEAppearancePrefs.showPreeditInPanel, !preedit.isEmpty {
            let field = textField(preedit, size: fontSize, weight: .semibold, color: colors.candidateText.nsColor, tag: 2)
            stack.addArrangedSubview(row([field], height: rowHeight, index: -1, onSelect: nil, alignment: skin.verticalAlignment))
            let sep = NSBox()
            sep.boxType = .separator
            sep.translatesAutoresizingMaskIntoConstraints = false
            if vertical {
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                sep.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
            } else {
                sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
                sep.heightAnchor.constraint(equalToConstant: max(12, rowHeight - 4)).isActive = true
            }
            stack.addArrangedSubview(sep)
        }

        let indexStyle = IMEAppearancePrefs.indexStyle
        let highlightOn = skin.highlightEnabled
        let inset = skin.highlightInsets
        for (i, text) in candidates.enumerated() {
            let highlighted = highlightOn && i == 0
            var fields: [NSTextField] = []
            if let indexLabel = indexStyle.label(forOneBased: i + 1) {
                fields.append(textField(
                    indexLabel,
                    size: CGFloat(skin.indexFontSize),
                    weight: skin.indexWeight,
                    color: highlighted ? colors.highlightIndexText.nsColor : colors.indexText.nsColor,
                    tag: highlighted ? 3 : 1
                ))
            }
            fields.append(textField(
                text,
                size: fontSize,
                weight: highlighted ? skin.highlightWeight : skin.candidateWeight,
                color: highlighted ? colors.highlightText.nsColor : colors.candidateText.nsColor,
                tag: highlighted ? 4 : 2
            ))
            let box = row(
                fields,
                height: rowHeight,
                index: i,
                onSelect: onSelect,
                alignment: skin.verticalAlignment,
                indexSpacing: CGFloat(skin.indexSpacing),
                inset: inset,
                fillsWidth: vertical && highlightOn
            )
            if highlighted {
                box.isHighlighted = true
                box.wantsLayer = true
                box.layer?.cornerRadius = CGFloat(skin.highlightCornerRadius)
                box.layer?.backgroundColor = colors.highlightBackground.nsColor.cgColor
            }
            stack.addArrangedSubview(box)
            // 纵向排列时高亮背景铺满整行宽度。
            if vertical && highlightOn {
                box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
    }

    // 切换亮暗外观时只刷新颜色：tag 1/2 为普通序号/候选词，tag 3/4 为首选序号/候选词。
    static func updateTextColors(in view: NSView, colors: CandidateSkin.Colors) {
        for child in view.subviews {
            if let field = child as? NSTextField {
                switch field.tag {
                case 1: field.textColor = colors.indexText.nsColor
                case 3: field.textColor = colors.highlightIndexText.nsColor
                case 4: field.textColor = colors.highlightText.nsColor
                default: field.textColor = colors.candidateText.nsColor
                }
            } else if let box = child as? CandidateHitView, box.isHighlighted {
                box.layer?.backgroundColor = colors.highlightBackground.nsColor.cgColor
            }
            updateTextColors(in: child, colors: colors)
        }
    }

    // 单个候选行：序号与候选词按皮肤的纵向对齐排列，行高固定，整行可点击。
    // inset 为四边留白（行高 = 文字行高 + 上下留白）；fillsWidth 时行宽由外部约束决定，文字靠左。
    private static func row(
        _ fields: [NSTextField],
        height: CGFloat,
        index: Int,
        onSelect: ((Int) -> Void)?,
        alignment: CandidateSkin.VerticalAlignment,
        indexSpacing: CGFloat = 3,
        inset: NSEdgeInsets = NSEdgeInsets(),
        fillsWidth: Bool = false
    ) -> CandidateHitView {
        let textStack = NSStackView(views: fields)
        textStack.orientation = .horizontal
        textStack.alignment = alignment.textAlignment
        // 有序号时使用皮肤配置的序号–候选间距。
        textStack.spacing = fields.count > 1 ? indexSpacing : 0
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let box = CandidateHitView(frame: .zero)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(textStack)
        let trailing: NSLayoutConstraint
        if fillsWidth {
            // 必需约束只保证不裁切，低优先级贴合让整列宽度取最宽的一行。
            trailing = textStack.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -inset.right)
            let hug = textStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -inset.right)
            hug.priority = .defaultLow
            hug.isActive = true
        } else {
            trailing = textStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -inset.right)
        }
        // 文字在行内的纵向位置：靠上/靠下贴住对应留白；居中时汉字光学中心略偏上，下移 0.5pt 视觉上更居中。
        let vertical: NSLayoutConstraint
        switch alignment {
        case .top:
            vertical = textStack.topAnchor.constraint(equalTo: box.topAnchor, constant: inset.top)
        case .center:
            vertical = textStack.centerYAnchor.constraint(
                equalTo: box.centerYAnchor,
                constant: 0.5 + (inset.top - inset.bottom) / 2
            )
        case .bottom:
            vertical = textStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -inset.bottom)
        }
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: inset.left),
            trailing,
            vertical,
            box.heightAnchor.constraint(equalToConstant: height + inset.top + inset.bottom)
        ])
        if let onSelect, index >= 0 {
            box.candidateIndex = index
            box.onClick = onSelect
        }
        return box
    }

    private static func textField(
        _ text: String,
        size: CGFloat,
        weight: CandidateSkin.FontWeight,
        color: NSColor,
        tag: Int
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.tag = tag
        field.font = IMEAppearancePrefs.candidateFont(size: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byClipping
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        return field
    }

    // 圆点模式尺寸：圆点直径、间距与整条高度。
    static let dotDiameter: CGFloat = 4
    static let dotSpacing: CGFloat = 2.5
    static let dotBarHeight: CGFloat = 8

    // 数量圆点：直径 4pt，占位与圆点等大，保持整条尽量小；可点击选中对应候选。
    private static func countDot(index: Int, color: NSColor, onSelect: ((Int) -> Void)?) -> CandidateHitView {
        let box = CandidateHitView(frame: .zero)
        box.wantsLayer = true
        box.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        box.layer?.cornerRadius = dotDiameter / 2
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: dotDiameter),
            box.heightAnchor.constraint(equalToConstant: dotDiameter)
        ])
        if let onSelect {
            box.candidateIndex = index
            box.onClick = onSelect
        }
        return box
    }
}

/// 可点击候选行（NSTextField 本身不好点选）
final class CandidateHitView: NSView {
    var candidateIndex: Int = -1
    var onClick: ((Int) -> Void)?
    /// 首选高亮行（或圆点），切换亮暗外观时需要刷新背景色。
    var isHighlighted = false

    override func mouseDown(with event: NSEvent) {
        if candidateIndex >= 0 {
            onClick?(candidateIndex)
        }
    }

    override func resetCursorRects() {
        if candidateIndex >= 0 {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

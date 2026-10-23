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
        codes: [String],
        comments: [String] = [],
        colors: CandidateSkin.Colors,
        onSelect: ((Int) -> Void)?
    ) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let skin = IMEAppearancePrefs.skin
        let dotsOnly = IMEAppearancePrefs.showCountDotsOnly
        let vertical = IMEAppearancePrefs.orientation == .vertical && !dotsOnly
        let fontSize = CGFloat(skin.candidateFontSize)
        let showCode = IMEAppearancePrefs.showPreeditInPanel
        let codeSize = CGFloat(skin.codeFontSize)
        let showComment = IMEAppearancePrefs.showCommentInPanel
        let commentSize = CGFloat(skin.commentFontSize)
        // 行高取所有可见字号的较大者，备注开关切换时不会跳高低。
        let rowHeight = ceil(max(
            fontSize,
            CGFloat(skin.indexFontSize),
            showCode ? codeSize : 0,
            showComment ? commentSize : 0
        ) * 1.35)

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
                // 第一个圆点用珊瑚红，其余跟候选文字色并略透明。
                let color: NSColor = i == 0
                    ? firstDotColor
                    : colors.candidateText.nsColor.withAlphaComponent(0.85)
                let dot = countDot(index: i, color: color, onSelect: onSelect)
                stack.addArrangedSubview(dot)
            }
            return
        }

        padding.top.constant = CGFloat(skin.paddingTop)
        padding.bottom.constant = -CGFloat(skin.paddingBottom)
        padding.leading.constant = CGFloat(skin.paddingLeft)
        padding.trailing.constant = -CGFloat(skin.paddingRight)

        let indexStyle = IMEAppearancePrefs.indexStyle
        let highlightOn = skin.highlightEnabled
        let inset = skin.highlightInsets
        for (i, text) in candidates.enumerated() {
            let highlighted = highlightOn && i == 0
            var fields: [NSView] = []
            if let indexLabel = indexStyle.label(forOneBased: i + 1) {
                fields.append(textField(
                    indexLabel,
                    size: CGFloat(skin.indexFontSize),
                    weight: skin.indexWeight,
                    color: highlighted ? colors.highlightIndexText.nsColor : colors.indexText.nsColor,
                    tag: highlighted ? 3 : 1
                ))
            }
            let word = textField(
                text,
                size: fontSize,
                weight: highlighted ? skin.highlightWeight : skin.candidateWeight,
                color: highlighted ? colors.highlightText.nsColor : colors.candidateText.nsColor,
                tag: highlighted ? 4 : 2
            )
            let code = codes.indices.contains(i) ? codes[i] : ""
            let comment = comments.indices.contains(i) ? comments[i] : ""
            // 词条后面紧跟编码与备注，两者都用固定 4pt 间距，不跟序号间距走。
            var trailing: [NSView] = [word]
            if showCode, !code.isEmpty {
                trailing.append(textField(
                    code,
                    size: codeSize,
                    weight: .regular,
                    color: highlighted ? colors.highlightCodeText.nsColor : colors.codeText.nsColor,
                    tag: highlighted ? 6 : 5
                ))
            }
            if showComment, !comment.isEmpty {
                trailing.append(textField(
                    comment,
                    size: commentSize,
                    weight: skin.commentWeight,
                    color: highlighted ? colors.highlightCommentText.nsColor : colors.commentText.nsColor,
                    tag: highlighted ? 8 : 7
                ))
            }
            if trailing.count > 1 {
                let pair = NSStackView(views: trailing)
                pair.orientation = .horizontal
                pair.alignment = skin.verticalAlignment.textAlignment
                pair.spacing = 4
                pair.setContentHuggingPriority(.required, for: .horizontal)
                pair.setContentCompressionResistancePriority(.required, for: .horizontal)
                fields.append(pair)
            } else {
                fields.append(word)
            }
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

    // 切换亮暗外观时只刷新颜色：1/2 普通序号和词，3/4 首选序号和词，5/6 普通和首选编码，7/8 普通和首选备注。
    static func updateTextColors(in view: NSView, colors: CandidateSkin.Colors) {
        for child in view.subviews {
            if let field = child as? NSTextField {
                switch field.tag {
                case 1: field.textColor = colors.indexText.nsColor
                case 3: field.textColor = colors.highlightIndexText.nsColor
                case 4: field.textColor = colors.highlightText.nsColor
                case 5: field.textColor = colors.codeText.nsColor
                case 6: field.textColor = colors.highlightCodeText.nsColor
                case 7: field.textColor = colors.commentText.nsColor
                case 8: field.textColor = colors.highlightCommentText.nsColor
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
        _ fields: [NSView],
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
    // 仅圆点时第一个点固定珊瑚红，与珊瑚红主题高亮同一色。
    static let firstDotColor = NSColor(srgbRed: 0.96, green: 0.377, blue: 0.377, alpha: 1)

    // 数量圆点：直径 4pt，占位与圆点等大，保持整条尽量小；可点击选中对应候选。
    private static func countDot(index: Int, color: NSColor, onSelect: ((Int) -> Void)?) -> CandidateHitView {
        let box = CandidateHitView(frame: .zero)
        box.wantsLayer = true
        box.layer?.backgroundColor = color.cgColor
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

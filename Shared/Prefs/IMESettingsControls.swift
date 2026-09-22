import AppKit

/// AppKit 设置表单：系统「输入法」设置页 / IMK 偏好窗口共用
enum IMESettingsControls {
    static let preferredFonts: [(name: String, title: String)] = [
        ("", "系统默认"),
        ("PingFang SC", "苹方"),
        ("Heiti SC", "黑体"),
        ("Songti SC", "宋体"),
        ("Kaiti SC", "楷体"),
        ("STSong", "华文宋体"),
        ("Hiragino Sans GB", "冬青黑体")
    ]

    /// 构建类似系统拼音输入法的选项面板
    static func makeFormView(width: CGFloat = 468) -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 360))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.widthAnchor.constraint(equalToConstant: width)
        ])

        // 标题
        let title = NSTextField(labelWithString: "候选窗口")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)

        // 方向
        let orientLabel = NSTextField(labelWithString: "方向：")
        let orient = NSSegmentedControl(
            labels: IMEAppearancePrefs.Orientation.allCases.map(\.title),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        orient.selectedSegment = IMEAppearancePrefs.orientation == .horizontal ? 0 : 1
        orient.target = OrientationTarget.shared
        orient.action = #selector(OrientationTarget.changed(_:))
        OrientationTarget.shared.control = orient
        stack.addArrangedSubview(row(orientLabel, orient))

        // 字体
        let fontLabel = NSTextField(labelWithString: "字体：")
        let fontPop = NSPopUpButton(frame: .zero, pullsDown: false)
        for item in preferredFonts {
            fontPop.addItem(withTitle: item.title)
            fontPop.lastItem?.representedObject = item.name
        }
        let currentFont = IMEAppearancePrefs.fontName
        if let idx = preferredFonts.firstIndex(where: { $0.name == currentFont }) {
            fontPop.selectItem(at: idx)
        } else {
            fontPop.selectItem(at: 0)
        }
        fontPop.target = FontTarget.shared
        fontPop.action = #selector(FontTarget.changed(_:))
        FontTarget.shared.control = fontPop
        fontPop.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        stack.addArrangedSubview(row(fontLabel, fontPop))

        // 字号
        let sizeLabel = NSTextField(labelWithString: "字体大小：")
        let slider = NSSlider(value: IMEAppearancePrefs.fontSize, minValue: 11, maxValue: 24, target: nil, action: nil)
        slider.isContinuous = true
        slider.target = FontSizeTarget.shared
        slider.action = #selector(FontSizeTarget.changed(_:))
        FontSizeTarget.shared.slider = slider
        let sizeValue = NSTextField(labelWithString: "\(Int(IMEAppearancePrefs.fontSize))")
        sizeValue.alignment = .right
        sizeValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sizeValue.widthAnchor.constraint(equalToConstant: 28).isActive = true
        FontSizeTarget.shared.valueLabel = sizeValue
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        stack.addArrangedSubview(row(sizeLabel, slider, sizeValue))

        // 开关
        let preedit = NSButton(
            checkboxWithTitle: "在候选条内显示编码",
            target: ToggleTarget.shared,
            action: #selector(ToggleTarget.preeditChanged(_:))
        )
        preedit.state = IMEAppearancePrefs.showPreeditInPanel ? .on : .off
        stack.addArrangedSubview(preedit)

        let index = NSButton(
            checkboxWithTitle: "显示候选序号",
            target: ToggleTarget.shared,
            action: #selector(ToggleTarget.indexChanged(_:))
        )
        index.state = IMEAppearancePrefs.showIndex ? .on : .off
        stack.addArrangedSubview(index)

        // 每页数量
        let pageLabel = NSTextField(labelWithString: "每页候选数：")
        let stepper = NSStepper()
        stepper.minValue = 3
        stepper.maxValue = 9
        stepper.increment = 1
        stepper.integerValue = IMEAppearancePrefs.pageSize
        stepper.target = PageTarget.shared
        stepper.action = #selector(PageTarget.changed(_:))
        let pageValue = NSTextField(labelWithString: "\(IMEAppearancePrefs.pageSize)")
        pageValue.widthAnchor.constraint(equalToConstant: 20).isActive = true
        PageTarget.shared.stepper = stepper
        PageTarget.shared.valueLabel = pageValue
        stack.addArrangedSubview(row(pageLabel, pageValue, stepper))

        let tip = NSTextField(wrappingLabelWithString: "修改后立即生效。也可在菜单栏输入法图标菜单中打开本设置。")
        tip.textColor = .secondaryLabelColor
        tip.font = .systemFont(ofSize: 11)
        tip.preferredMaxLayoutWidth = width - 36
        stack.addArrangedSubview(tip)

        root.frame.size.height = stack.fittingSize.height + 8
        return root
    }

    private static func row(_ views: NSView...) -> NSView {
        let h = NSStackView(views: views)
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 8
        return h
    }
}

// MARK: - Targets（避免闭包，方便 PreferencePane / WindowController 共用）

private final class OrientationTarget: NSObject {
    static let shared = OrientationTarget()
    weak var control: NSSegmentedControl?
    @objc func changed(_ sender: NSSegmentedControl) {
        IMEAppearancePrefs.orientation = sender.selectedSegment == 0 ? .horizontal : .vertical
    }
}

private final class FontTarget: NSObject {
    static let shared = FontTarget()
    weak var control: NSPopUpButton?
    @objc func changed(_ sender: NSPopUpButton) {
        let name = (sender.selectedItem?.representedObject as? String) ?? ""
        IMEAppearancePrefs.fontName = name
    }
}

private final class FontSizeTarget: NSObject {
    static let shared = FontSizeTarget()
    weak var slider: NSSlider?
    weak var valueLabel: NSTextField?
    @objc func changed(_ sender: NSSlider) {
        let v = sender.doubleValue.rounded()
        IMEAppearancePrefs.fontSize = v
        valueLabel?.stringValue = "\(Int(v))"
    }
}

private final class ToggleTarget: NSObject {
    static let shared = ToggleTarget()
    @objc func preeditChanged(_ sender: NSButton) {
        IMEAppearancePrefs.showPreeditInPanel = sender.state == .on
    }
    @objc func indexChanged(_ sender: NSButton) {
        IMEAppearancePrefs.showIndex = sender.state == .on
    }
}

private final class PageTarget: NSObject {
    static let shared = PageTarget()
    weak var stepper: NSStepper?
    weak var valueLabel: NSTextField?
    @objc func changed(_ sender: NSStepper) {
        IMEAppearancePrefs.pageSize = sender.integerValue
        valueLabel?.stringValue = "\(sender.integerValue)"
    }
}

import AppKit

/// 标点页：可改输出内容，并选择直接上屏或弹出候选列表。
final class PunctuationSettingsView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let restore = NSButton(title: "恢复默认", target: self, action: #selector(restoreDefaults))
        restore.bezelStyle = .rounded
        restore.controlSize = .small
        stack.addArrangedSubview(restore)

        let header = NSStackView(views: [
            label("按键", width: 36, secondary: true),
            label("输出", width: 280, secondary: true),
            label("方式", width: 196, secondary: true)
        ])
        header.orientation = .horizontal
        header.spacing = 12
        stack.addArrangedSubview(header)

        for (index, item) in PunctuationPrefs.items.enumerated() {
            let key = NSTextField(labelWithString: item.key)
            key.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            key.frame.size.width = 36
            key.widthAnchor.constraint(equalToConstant: 36).isActive = true

            let symbols = NSTextField(string: PunctuationPrefs.symbols(for: item.key).joined(separator: " "))
            symbols.font = .systemFont(ofSize: 13)
            symbols.isEditable = true
            symbols.isSelectable = true
            symbols.isBezeled = true
            symbols.bezelStyle = .roundedBezel
            symbols.controlSize = .small
            symbols.lineBreakMode = .byTruncatingTail
            symbols.tag = index
            symbols.target = self
            symbols.action = #selector(symbolsChanged(_:))
            (symbols.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
            symbols.widthAnchor.constraint(equalToConstant: 280).isActive = true

            // 每行单独成组，点一下另一项就切换，不用下拉。
            let modes = modeRadios(index: index, mode: PunctuationPrefs.mode(for: item.key))

            let row = NSStackView(views: [key, symbols, modes])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            stack.addArrangedSubview(row)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func label(_ text: String, width: CGFloat, secondary: Bool) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    @objc private func restoreDefaults() {
        let alert = NSAlert()
        alert.messageText = "恢复默认标点？"
        alert.informativeText = "输出内容和输出方式都会回到半角默认方案。"
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        PunctuationPrefs.restoreDefaults()
        build()
    }

    @objc private func symbolsChanged(_ sender: NSTextField) {
        let index = sender.tag
        guard PunctuationPrefs.items.indices.contains(index) else { return }
        let key = PunctuationPrefs.items[index].key
        PunctuationPrefs.setSymbols(PunctuationPrefs.parseSymbols(sender.stringValue), for: key)
        // 空内容会回到默认符号，把输入框同步成实际保存的结果。
        sender.stringValue = PunctuationPrefs.symbols(for: key).joined(separator: " ")
    }

    // 同一行的两个单选共用这个容器，避免和其它行串成一组。
    private func modeRadios(index: Int, mode: PunctuationPrefs.Mode) -> NSView {
        let group = NSStackView()
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = 10
        for item in PunctuationPrefs.Mode.allCases {
            let button = NSButton(
                radioButtonWithTitle: item.title,
                target: self,
                action: #selector(modeChanged(_:))
            )
            button.controlSize = .small
            button.font = .systemFont(ofSize: 12)
            button.tag = index
            button.identifier = NSUserInterfaceItemIdentifier(item.rawValue)
            button.state = item == mode ? .on : .off
            group.addArrangedSubview(button)
        }
        return group
    }

    @objc private func modeChanged(_ sender: NSButton) {
        let index = sender.tag
        guard PunctuationPrefs.items.indices.contains(index),
              let raw = sender.identifier?.rawValue,
              let mode = PunctuationPrefs.Mode(rawValue: raw) else { return }
        sender.state = .on
        if let group = sender.superview as? NSStackView {
            for case let button as NSButton in group.arrangedSubviews where button !== sender {
                button.state = .off
            }
        }
        PunctuationPrefs.setMode(mode, for: PunctuationPrefs.items[index].key)
    }
}

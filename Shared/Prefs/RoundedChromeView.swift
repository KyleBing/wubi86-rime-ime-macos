import AppKit

/// 系统候选窗风格的圆角毛玻璃；窗口阴影交给 NSPanel 绘制
final class RoundedChromeView: NSView {
    let effectView = NSVisualEffectView()
    private let radius: CGFloat = 9

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        layer?.cornerRadius = radius
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }

        // 使用系统菜单材质，候选窗和预览面板保持原生、明亮的自适应背景
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = radius
        effectView.layer?.masksToBounds = true
        if #available(macOS 10.15, *) {
            effectView.layer?.cornerCurve = .continuous
        }
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateBorderColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        // 系统浮窗有一圈很淡的描边，浅色背景下也能保持边界清晰
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }
}

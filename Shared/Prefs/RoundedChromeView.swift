import AppKit

/// 候选窗圆角背景；外层负责可配置阴影，内层纯色圆角底保证背景色可调。
final class RoundedChromeView: NSView {
    /// 内容宿主（候选文字叠在此视图上）；曾用毛玻璃，但材质会盖住自定义背景色。
    let effectView = NSView()
    var onAppearanceChange: (() -> Void)?
    /// 实际候选窗需要把阴影计入窗口尺寸；嵌入式预览也可预留以便看见阴影。
    var reservesShadowSpace = true {
        didSet { applySkin() }
    }
    private let shadowView = NSView()
    private var edgeConstraints: [NSLayoutConstraint] = []

    var shadowOutset: CGFloat {
        guard reservesShadowSpace, !IMEAppearancePrefs.showCountDotsOnly else { return 0 }
        let skin = IMEAppearancePrefs.skin
        guard skin.shadowEnabled else { return 0 }
        let offset = max(abs(skin.shadowOffsetX), abs(skin.shadowOffsetY))
        // 高斯模糊的衰减范围约为模糊半径的 2 倍，只留 1 倍会在窗口边缘被硬裁切。
        return ceil(CGFloat(skin.shadowRadius * 2 + offset + 2))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 阴影画在 shadowView 外侧，宿主不能裁切。
        clipsToBounds = false
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor

        shadowView.wantsLayer = true
        shadowView.clipsToBounds = false
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shadowView)

        effectView.wantsLayer = true
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor)
        ])
        applySkin()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySkin()
        onAppearanceChange?()
    }

    func applySkin() {
        let skin = IMEAppearancePrefs.skin
        let colors = skin.colors(for: effectiveAppearance)
        // 圆点模式：胶囊形、无边框无阴影，整体尽量小。
        let dotsOnly = IMEAppearancePrefs.showCountDotsOnly
        let radius = dotsOnly ? CandidateBarLayout.dotBarHeight / 2 : CGFloat(skin.cornerRadius)
        let showShadow = skin.shadowEnabled && !dotsOnly
        let borderWidth = dotsOnly ? 0 : CGFloat(skin.borderWidth)
        let inset = shadowOutset
        let background = colors.background.nsColor.cgColor

        NSLayoutConstraint.deactivate(edgeConstraints)
        edgeConstraints = [
            shadowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            shadowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            shadowView.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            shadowView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ]
        NSLayoutConstraint.activate(edgeConstraints)

        // shadowView 同色铺底，保证阴影投影形状与面板一致。
        shadowView.layer?.cornerRadius = radius
        shadowView.layer?.backgroundColor = background
        // 图层由 AppKit 托管，直接改 layer.shadow* 会被 NSView.shadow（nil）覆盖，必须经 NSShadow 设置。
        if showShadow {
            let shadow = NSShadow()
            shadow.shadowColor = colors.shadow.nsColor
            shadow.shadowBlurRadius = CGFloat(skin.shadowRadius)
            shadow.shadowOffset = NSSize(
                width: CGFloat(skin.shadowOffsetX),
                height: CGFloat(skin.shadowOffsetY)
            )
            shadowView.shadow = shadow
        } else {
            shadowView.shadow = nil
        }

        // 纯色圆角底，背景色即时反映皮肤设置。
        effectView.layer?.cornerRadius = radius
        effectView.layer?.backgroundColor = background
        effectView.layer?.borderWidth = borderWidth
        effectView.layer?.borderColor = colors.border.nsColor.cgColor
        if #available(macOS 10.15, *) {
            shadowView.layer?.cornerCurve = .continuous
            effectView.layer?.cornerCurve = .continuous
        }
    }
}

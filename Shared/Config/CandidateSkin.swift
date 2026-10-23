import AppKit
import Foundation

/// 可复制分享的候选栏皮肤。尺寸配置共用，颜色按浅色和深色分别保存。
struct CandidateSkin: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var name: String
    var author: String
    var fontName: String
    var paddingTop: Double
    var paddingBottom: Double
    var paddingLeft: Double
    var paddingRight: Double
    /// 候选条相对光标的垂直间距（面板在光标下方时为上边距）。
    var offsetTop: Double
    /// 候选条相对光标的水平偏移（正值向右）。
    var offsetLeft: Double
    var cornerRadius: Double
    var verticalAlignment: VerticalAlignment
    var itemSpacing: Double
    /// 序号与候选词之间的水平间距。
    var indexSpacing: Double
    var candidateFontSize: Double
    var candidateWeight: FontWeight
    var indexFontSize: Double
    var indexWeight: FontWeight
    /// 词条后面的五笔编码字号。
    var codeFontSize: Double
    /// 候选备注（Rime comment，缺失时用码表备注）字号与粗细。
    var commentFontSize: Double
    var commentWeight: FontWeight
    var borderWidth: Double
    var shadowEnabled: Bool
    var shadowRadius: Double
    var shadowOffsetX: Double
    var shadowOffsetY: Double
    /// 首位候选（空格上屏）是否使用单独的高亮样式。
    var highlightEnabled: Bool
    var highlightCornerRadius: Double
    /// 高亮背景四边留白；开启后所有候选统一留白，保证间距与行高一致。
    var highlightPaddingTop: Double
    var highlightPaddingBottom: Double
    var highlightPaddingLeft: Double
    var highlightPaddingRight: Double
    var highlightWeight: FontWeight
    var light: Colors
    var dark: Colors

    enum FontWeight: String, Codable, CaseIterable {
        case ultraLight
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black

        var title: String {
            switch self {
            case .ultraLight: return "极细"
            case .thin: return "纤细"
            case .light: return "细体"
            case .regular: return "常规"
            case .medium: return "中等"
            case .semibold: return "半粗"
            case .bold: return "粗体"
            case .heavy: return "特粗"
            case .black: return "黑体"
            }
        }

        var nsWeight: NSFont.Weight {
            switch self {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            }
        }

        /// AppKit 字体家族成员里的字重档位（约 0–15）。
        var memberWeight: Int {
            switch self {
            case .ultraLight: return 2
            case .thin: return 3
            case .light: return 4
            case .regular: return 5
            case .medium: return 6
            case .semibold: return 8
            case .bold: return 9
            case .heavy: return 11
            case .black: return 12
            }
        }

        /// 当前字体实际提供的字重；系统字体支持全部档位。
        static func available(forFontName name: String) -> [FontWeight] {
            guard !name.isEmpty, let font = NSFont(name: name, size: 14),
                  let family = font.familyName,
                  let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  !members.isEmpty
            else {
                return allCases
            }
            let provided = Set(members.compactMap { ($0[2] as? NSNumber)?.intValue })
            let matched = allCases.filter { weight in
                provided.contains { abs($0 - weight.memberWeight) <= 1 }
            }
            return matched.isEmpty ? [.regular] : matched
        }
    }

    enum VerticalAlignment: String, Codable, CaseIterable {
        case top
        case center
        case bottom

        var title: String {
            switch self {
            case .top: return "靠上"
            case .center: return "居中"
            case .bottom: return "靠下"
            }
        }

        // 行内序号与候选词的对齐方式；靠下按基线对齐，避免不同字号的下行高度造成错位。
        var textAlignment: NSLayoutConstraint.Attribute {
            switch self {
            case .top: return .top
            case .center: return .centerY
            case .bottom: return .firstBaseline
            }
        }
    }

    struct Colors: Codable, Equatable {
        var background: RGBAColor
        var candidateText: RGBAColor
        var indexText: RGBAColor
        var border: RGBAColor
        var shadow: RGBAColor
        var highlightBackground: RGBAColor
        var highlightText: RGBAColor
        var highlightIndexText: RGBAColor
        /// 普通候选后面的编码颜色。
        var codeText: RGBAColor
        /// 首选高亮行里的编码颜色。
        var highlightCodeText: RGBAColor
        /// 普通候选后面的备注颜色。
        var commentText: RGBAColor
        /// 首选高亮行里的备注颜色。
        var highlightCommentText: RGBAColor
    }

    struct RGBAColor: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        init(_ color: NSColor) {
            let rgb = color.usingColorSpace(.sRGB) ?? color
            red = Double(rgb.redComponent)
            green = Double(rgb.greenComponent)
            blue = Double(rgb.blueComponent)
            alpha = Double(rgb.alphaComponent)
        }

        var nsColor: NSColor {
            NSColor(
                srgbRed: CGFloat(red),
                green: CGFloat(green),
                blue: CGFloat(blue),
                alpha: CGFloat(alpha)
            )
        }

        func normalized() -> Self {
            .init(
                red: red.clamped(to: 0...1),
                green: green.clamped(to: 0...1),
                blue: blue.clamped(to: 0...1),
                alpha: alpha.clamped(to: 0...1)
            )
        }
    }

    static var defaultSkin: CandidateSkin {
        CandidateSkin(
            version: currentVersion,
            name: "玫枫默认",
            author: "玫枫五笔",
            fontName: "",
            paddingTop: 5,
            paddingBottom: 5,
            paddingLeft: 10,
            paddingRight: 10,
            offsetTop: 6,
            offsetLeft: 0,
            cornerRadius: 9,
            verticalAlignment: .center,
            itemSpacing: 6,
            indexSpacing: 3,
            candidateFontSize: 14,
            candidateWeight: .regular,
            indexFontSize: 11,
            indexWeight: .regular,
            codeFontSize: 11,
            commentFontSize: 11,
            commentWeight: .regular,
            borderWidth: 0.5,
            shadowEnabled: true,
            shadowRadius: 10,
            shadowOffsetX: 0,
            shadowOffsetY: -2,
            highlightEnabled: true,
            highlightCornerRadius: 5,
            highlightPaddingTop: 2,
            highlightPaddingBottom: 2,
            highlightPaddingLeft: 5,
            highlightPaddingRight: 5,
            highlightWeight: .medium,
            light: Colors(
                background: .init(red: 0.98, green: 0.98, blue: 0.99, alpha: 0.92),
                candidateText: .init(red: 0.08, green: 0.08, blue: 0.09),
                indexText: .init(red: 0.38, green: 0.38, blue: 0.42),
                border: .init(red: 0, green: 0, blue: 0, alpha: 0.16),
                shadow: .init(red: 0, green: 0, blue: 0, alpha: 0.28),
                highlightBackground: .init(red: 0.20, green: 0.47, blue: 0.96),
                highlightText: .init(red: 1, green: 1, blue: 1),
                highlightIndexText: .init(red: 1, green: 1, blue: 1, alpha: 0.78),
                codeText: .init(red: 0.614888698630137, green: 0.614888698630137, blue: 0.614888698630137),
                highlightCodeText: .init(red: 0.3245130565068493, green: 0.3245130565068493, blue: 0.3245130565068493),
                commentText: .init(red: 0.52, green: 0.52, blue: 0.55),
                highlightCommentText: .init(red: 1, green: 1, blue: 1, alpha: 0.9)
            ),
            dark: Colors(
                background: .init(red: 0.13, green: 0.13, blue: 0.15, alpha: 0.94),
                candidateText: .init(red: 0.95, green: 0.95, blue: 0.97),
                indexText: .init(red: 0.68, green: 0.68, blue: 0.72),
                border: .init(red: 1, green: 1, blue: 1, alpha: 0.18),
                shadow: .init(red: 0, green: 0, blue: 0, alpha: 0.58),
                highlightBackground: .init(red: 0.26, green: 0.53, blue: 0.98),
                highlightText: .init(red: 1, green: 1, blue: 1),
                highlightIndexText: .init(red: 1, green: 1, blue: 1, alpha: 0.78),
                codeText: .init(red: 0.7359364297945206, green: 0.7359364297945206, blue: 0.7359364297945206),
                highlightCodeText: .init(red: 0.7462810359589042, green: 0.7462810359589042, blue: 0.7462810359589042),
                commentText: .init(red: 0.70, green: 0.70, blue: 0.73),
                highlightCommentText: .init(red: 1, green: 1, blue: 1, alpha: 0.9)
            )
        )
    }

    /// 内置主题：只读，应用时保留用户当前字体。
    static var presets: [CandidateSkin] {
        [coralPreset, monochromePreset]
    }

    // 珊瑚红：浅色白底、深色近黑底，首选珊瑚红高亮。
    private static var coralPreset: CandidateSkin {
        let coral = RGBAColor(red: 0.96, green: 0.377, blue: 0.377)
        return CandidateSkin(
            version: currentVersion,
            name: "珊瑚红",
            author: "玫枫五笔",
            fontName: "",
            paddingTop: 4,
            paddingBottom: 4,
            paddingLeft: 5,
            paddingRight: 5,
            offsetTop: 4,
            offsetLeft: 0,
            cornerRadius: 7,
            verticalAlignment: .center,
            itemSpacing: 3,
            indexSpacing: 6,
            candidateFontSize: 18,
            candidateWeight: .regular,
            indexFontSize: 11,
            indexWeight: .light,
            codeFontSize: 12,
            commentFontSize: 11,
            commentWeight: .regular,
            borderWidth: 0.5,
            shadowEnabled: true,
            shadowRadius: 4,
            shadowOffsetX: 2,
            shadowOffsetY: -2,
            highlightEnabled: true,
            highlightCornerRadius: 5,
            highlightPaddingTop: 1,
            highlightPaddingBottom: 1,
            highlightPaddingLeft: 3,
            highlightPaddingRight: 3,
            highlightWeight: .regular,
            light: Colors(
                background: .init(red: 1, green: 1, blue: 1),
                candidateText: .init(red: 0.283, green: 0.283, blue: 0.318),
                indexText: .init(red: 0.38, green: 0.38, blue: 0.42),
                border: .init(red: 0, green: 0, blue: 0, alpha: 0.16),
                shadow: .init(red: 0, green: 0, blue: 0, alpha: 0.28),
                highlightBackground: coral,
                highlightText: .init(red: 1, green: 1, blue: 1),
                highlightIndexText: .init(red: 1, green: 1, blue: 1, alpha: 0.78),
                codeText: .init(red: 0.614888698630137, green: 0.614888698630137, blue: 0.614888698630137),
                highlightCodeText: .init(red: 1, green: 1, blue: 1),
                commentText: .init(red: 0.55, green: 0.55, blue: 0.58),
                highlightCommentText: .init(red: 1, green: 1, blue: 1, alpha: 0.92)
            ),
            dark: Colors(
                background: .init(red: 0.1355506262357012, green: 0.1355506262357012, blue: 0.138404323630137, alpha: 0.94),
                candidateText: .init(red: 0.95, green: 0.95, blue: 0.97),
                indexText: .init(red: 0.68, green: 0.68, blue: 0.72),
                border: .init(red: 1, green: 1, blue: 1, alpha: 0.18),
                shadow: .init(red: 0, green: 0, blue: 0, alpha: 0.58),
                highlightBackground: coral,
                highlightText: .init(red: 1, green: 1, blue: 1),
                highlightIndexText: .init(red: 1, green: 1, blue: 1, alpha: 0.78),
                codeText: .init(red: 0.7359364297945206, green: 0.7359364297945206, blue: 0.7359364297945206),
                highlightCodeText: .init(red: 1, green: 1, blue: 1),
                commentText: .init(red: 0.70, green: 0.70, blue: 0.73),
                highlightCommentText: .init(red: 1, green: 1, blue: 1, alpha: 0.92)
            )
        )
    }

    // 简约黑白：白底 / 深灰底，首选与背景同色，靠文字颜色区分。
    private static var monochromePreset: CandidateSkin {
        CandidateSkin(
            version: currentVersion,
            name: "简约黑白",
            author: "玫枫五笔",
            fontName: "",
            paddingTop: 3,
            paddingBottom: 3,
            paddingLeft: 5,
            paddingRight: 5,
            offsetTop: 4,
            offsetLeft: 0,
            cornerRadius: 7,
            verticalAlignment: .center,
            itemSpacing: 3,
            indexSpacing: 6,
            candidateFontSize: 18,
            candidateWeight: .regular,
            indexFontSize: 11,
            indexWeight: .light,
            codeFontSize: 12,
            commentFontSize: 11,
            commentWeight: .regular,
            borderWidth: 0.5,
            shadowEnabled: true,
            shadowRadius: 4,
            shadowOffsetX: 2,
            shadowOffsetY: -2,
            highlightEnabled: true,
            highlightCornerRadius: 5,
            highlightPaddingTop: 1,
            highlightPaddingBottom: 1,
            highlightPaddingLeft: 3,
            highlightPaddingRight: 3,
            highlightWeight: .regular,
            light: Colors(
                background: .init(red: 1, green: 1, blue: 1),
                candidateText: .init(red: 0.283, green: 0.283, blue: 0.318),
                indexText: .init(red: 0.38, green: 0.38, blue: 0.42),
                border: .init(red: 0, green: 0, blue: 0, alpha: 0.16),
                shadow: .init(red: 0, green: 0, blue: 0, alpha: 0.28),
                highlightBackground: .init(red: 1, green: 1, blue: 1),
                highlightText: .init(red: 0, green: 0, blue: 0),
                highlightIndexText: .init(red: 0.243, green: 0.247, blue: 0.247, alpha: 0.695),
                codeText: .init(red: 0.614888698630137, green: 0.614888698630137, blue: 0.614888698630137),
                highlightCodeText: .init(red: 0.3245130565068493, green: 0.3245130565068493, blue: 0.3245130565068493),
                commentText: .init(red: 0.55, green: 0.55, blue: 0.58),
                highlightCommentText: .init(red: 0.38, green: 0.38, blue: 0.41)
            ),
            dark: Colors(
                background: .init(red: 0.13736087328767124, green: 0.13736087328767124, blue: 0.13736087328767124, alpha: 0.94),
                candidateText: .init(red: 0.8973309957986161, green: 0.8973309957986161, blue: 0.9162221746575343),
                indexText: .init(red: 0.68, green: 0.68, blue: 0.72),
                border: .init(red: 1, green: 1, blue: 1, alpha: 0.18),
                shadow: .init(red: 0, green: 0, blue: 0, alpha: 0.58),
                highlightBackground: .init(red: 0.1409193065068493, green: 0.1409193065068493, blue: 0.1409193065068493),
                highlightText: .init(red: 1, green: 1, blue: 1),
                highlightIndexText: .init(red: 1, green: 1, blue: 1, alpha: 0.68),
                codeText: .init(red: 0.7359364297945206, green: 0.7359364297945206, blue: 0.7359364297945206),
                highlightCodeText: .init(red: 0.7462810359589042, green: 0.7462810359589042, blue: 0.7462810359589042),
                commentText: .init(red: 0.70, green: 0.70, blue: 0.73),
                highlightCommentText: .init(red: 1, green: 1, blue: 1, alpha: 0.85)
            )
        )
    }

    /// 比较外观是否一致（忽略字体，内置主题应用时会沿用当前字体）。
    func looksSame(as other: CandidateSkin) -> Bool {
        var lhs = normalized()
        var rhs = other.normalized()
        lhs.fontName = ""
        rhs.fontName = ""
        return lhs == rhs
    }

    /// 导入后统一收敛数值，避免异常配置生成不可操作的候选窗。
    func normalized() -> CandidateSkin {
        var result = self
        result.version = Self.currentVersion
        result.name = String(name.prefix(80))
        result.author = String(author.prefix(80))
        result.fontName = String(fontName.prefix(160))
        result.paddingTop = paddingTop.clamped(to: 0...30)
        result.paddingBottom = paddingBottom.clamped(to: 0...30)
        result.paddingLeft = paddingLeft.clamped(to: 0...40)
        result.paddingRight = paddingRight.clamped(to: 0...40)
        result.offsetTop = offsetTop.clamped(to: -40...80)
        result.offsetLeft = offsetLeft.clamped(to: -80...80)
        result.cornerRadius = cornerRadius.clamped(to: 0...30)
        result.itemSpacing = itemSpacing.clamped(to: 0...30)
        result.indexSpacing = indexSpacing.clamped(to: 0...20)
        result.candidateFontSize = candidateFontSize.clamped(to: 9...40)
        result.indexFontSize = indexFontSize.clamped(to: 8...32)
        result.codeFontSize = codeFontSize.clamped(to: 8...32)
        result.commentFontSize = commentFontSize.clamped(to: 8...32)
        result.borderWidth = borderWidth.clamped(to: 0...6)
        result.shadowRadius = shadowRadius.clamped(to: 0...40)
        result.shadowOffsetX = shadowOffsetX.clamped(to: -30...30)
        result.shadowOffsetY = shadowOffsetY.clamped(to: -30...30)
        result.highlightCornerRadius = highlightCornerRadius.clamped(to: 0...20)
        result.highlightPaddingTop = highlightPaddingTop.clamped(to: 0...20)
        result.highlightPaddingBottom = highlightPaddingBottom.clamped(to: 0...20)
        result.highlightPaddingLeft = highlightPaddingLeft.clamped(to: 0...20)
        result.highlightPaddingRight = highlightPaddingRight.clamped(to: 0...20)
        result.light = result.light.normalized()
        result.dark = result.dark.normalized()
        return result
    }

    func colors(for appearance: NSAppearance?) -> Colors {
        let match = appearance?.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? dark : light
    }

    /// 候选行留白：开启首选高亮时四边生效，关闭时为零。
    var highlightInsets: NSEdgeInsets {
        guard highlightEnabled else { return NSEdgeInsets() }
        return NSEdgeInsets(
            top: CGFloat(highlightPaddingTop),
            left: CGFloat(highlightPaddingLeft),
            bottom: CGFloat(highlightPaddingBottom),
            right: CGFloat(highlightPaddingRight)
        )
    }

    /// 候选条内容内边距（相对圆角背景内侧）。
    var contentInsets: NSEdgeInsets {
        NSEdgeInsets(
            top: CGFloat(paddingTop),
            left: CGFloat(paddingLeft),
            bottom: CGFloat(paddingBottom),
            right: CGFloat(paddingRight)
        )
    }
}

private extension CandidateSkin.Colors {
    func normalized() -> Self {
        .init(
            background: background.normalized(),
            candidateText: candidateText.normalized(),
            indexText: indexText.normalized(),
            border: border.normalized(),
            shadow: shadow.normalized(),
            highlightBackground: highlightBackground.normalized(),
            highlightText: highlightText.normalized(),
            highlightIndexText: highlightIndexText.normalized(),
            codeText: codeText.normalized(),
            highlightCodeText: highlightCodeText.normalized(),
            commentText: commentText.normalized(),
            highlightCommentText: highlightCommentText.normalized()
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

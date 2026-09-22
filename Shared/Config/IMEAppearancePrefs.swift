import AppKit
import Foundation

/// 候选栏外观：对齐系统中文输入法常见选项（横/纵、字号、字体等）
enum IMEAppearancePrefs {
    static let suiteName = "cn.kylebing.inputmethod.meifengwubi.prefs"
    static let didChangeNotification = Notification.Name("cn.kylebing.inputmethod.meifengwubi.appearanceChanged")

    enum Orientation: String, CaseIterable, Identifiable {
        case horizontal
        case vertical
        var id: String { rawValue }
        var title: String {
            switch self {
            case .horizontal: return "水平"
            case .vertical: return "垂直"
            }
        }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // 候选排列
    static var orientation: Orientation {
        get {
            let raw = defaults.string(forKey: Keys.orientation) ?? Orientation.horizontal.rawValue
            return Orientation(rawValue: raw) ?? .horizontal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.orientation)
            notify()
        }
    }

    // 候选字号（系统拼音大约 13–18）
    static var fontSize: Double {
        get {
            let v = defaults.double(forKey: Keys.fontSize)
            return v > 0 ? v : 14
        }
        set {
            defaults.set(min(28, max(11, newValue)), forKey: Keys.fontSize)
            notify()
        }
    }

    // 候选字体 PostScript 名；空字符串表示系统默认
    static var fontName: String {
        get { defaults.string(forKey: Keys.fontName) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.fontName)
            notify()
        }
    }

    /// 按当前偏好生成 NSFont
    static func candidateFont(size: CGFloat? = nil, bold: Bool = false) -> NSFont {
        let sz = size ?? CGFloat(fontSize)
        let name = fontName
        if !name.isEmpty, let custom = NSFont(name: name, size: sz) {
            if bold {
                return NSFontManager.shared.convert(custom, toHaveTrait: .boldFontMask)
            }
            return custom
        }
        return bold
            ? NSFont.systemFont(ofSize: sz, weight: .semibold)
            : NSFont.systemFont(ofSize: sz)
    }

    // 是否在候选条显示编码（preedit）
    static var showPreeditInPanel: Bool {
        get {
            if defaults.object(forKey: Keys.showPreedit) == nil { return true }
            return defaults.bool(forKey: Keys.showPreedit)
        }
        set {
            defaults.set(newValue, forKey: Keys.showPreedit)
            notify()
        }
    }

    // 每页候选数
    static var pageSize: Int {
        get {
            let v = defaults.integer(forKey: Keys.pageSize)
            return v > 0 ? min(9, max(3, v)) : 9
        }
        set {
            defaults.set(min(9, max(3, newValue)), forKey: Keys.pageSize)
            notify()
        }
    }

    // 是否显示候选序号
    static var showIndex: Bool {
        get {
            if defaults.object(forKey: Keys.showIndex) == nil { return true }
            return defaults.bool(forKey: Keys.showIndex)
        }
        set {
            defaults.set(newValue, forKey: Keys.showIndex)
            notify()
        }
    }

    private static func notify() {
        defaults.synchronize()
        DistributedNotificationCenter.default().post(
            name: didChangeNotification,
            object: nil
        )
    }

    private enum Keys {
        static let orientation = "candidate.orientation"
        static let fontSize = "candidate.fontSize"
        static let fontName = "candidate.fontName"
        static let showPreedit = "candidate.showPreedit"
        static let pageSize = "candidate.pageSize"
        static let showIndex = "candidate.showIndex"
    }
}

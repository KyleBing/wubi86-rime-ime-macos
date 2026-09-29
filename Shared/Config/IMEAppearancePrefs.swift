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

    static var skin: CandidateSkin {
        get {
            guard let data = defaults.data(forKey: Keys.skin),
                  let decoded = try? JSONDecoder().decode(CandidateSkin.self, from: compatibleSkinData(data)),
                  decoded.version <= CandidateSkin.currentVersion
            else {
                return migratedDefaultSkin()
            }
            let value = decoded.normalized()
            let corrected = correctedCoralHighlightCode(value)
            if corrected != value, let data = try? JSONEncoder().encode(corrected) {
                // 已套用的珊瑚红仍带着旧的灰色首选编码，读到时改成白色。
                defaults.set(data, forKey: Keys.skin)
            }
            return corrected
        }
        set {
            let value = newValue.normalized()
            if let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: Keys.skin)
                notify()
            }
        }
    }

    /// 以稳定、易读的 JSON 格式导出，便于直接复制分享。
    static func exportedSkinJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(skin)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SkinImportError.invalidText
        }
        return json
    }

    static func importSkinJSON(_ json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw SkinImportError.invalidText
        }
        let decoded: CandidateSkin
        do {
            decoded = try JSONDecoder().decode(CandidateSkin.self, from: compatibleSkinData(data))
        } catch {
            throw SkinImportError.invalidJSON(error.localizedDescription)
        }
        guard (1...CandidateSkin.currentVersion).contains(decoded.version) else {
            throw SkinImportError.unsupportedVersion(decoded.version)
        }
        skin = decoded
    }

    static func restoreDefaultSkin() {
        skin = .defaultSkin
    }

    /// 用户主题存储位数量。
    static let skinSlotCount = 8

    /// 用户保存的主题，固定 8 个位置，nil 表示空位。
    static var skinSlots: [CandidateSkin?] {
        get {
            let stored = (defaults.array(forKey: Keys.skinSlots) as? [Data]) ?? []
            return (0..<skinSlotCount).map { index in
                guard index < stored.count, !stored[index].isEmpty,
                      let decoded = try? JSONDecoder().decode(
                          CandidateSkin.self,
                          from: compatibleSkinData(stored[index])
                      )
                else { return nil }
                return decoded.normalized()
            }
        }
        set {
            // 空位存空 Data，保证下标与位置一一对应。
            let encoded: [Data] = (0..<skinSlotCount).map { index in
                guard index < newValue.count, let value = newValue[index] else { return Data() }
                return (try? JSONEncoder().encode(value.normalized())) ?? Data()
            }
            defaults.set(encoded, forKey: Keys.skinSlots)
            defaults.synchronize()
        }
    }

    // 把当前皮肤存入指定位置（覆盖原有内容）。
    static func saveCurrentSkin(toSlot index: Int) {
        guard (0..<skinSlotCount).contains(index) else { return }
        var slots = skinSlots
        slots[index] = skin
        skinSlots = slots
    }

    // 清空指定位置。
    static func clearSkinSlot(_ index: Int) {
        guard (0..<skinSlotCount).contains(index) else { return }
        var slots = skinSlots
        slots[index] = nil
        skinSlots = slots
    }

    // 应用已保存的主题，完整还原（含字体）。
    static func applySkinSlot(_ index: Int) {
        guard (0..<skinSlotCount).contains(index), let saved = skinSlots[index] else { return }
        skin = saved
    }

    // 应用内置主题；内置主题不指定字体，沿用用户当前字体。
    static func applyPreset(_ preset: CandidateSkin) {
        var value = preset
        value.fontName = skin.fontName
        skin = value
    }

    static func updateSkin(_ change: (inout CandidateSkin) -> Void) {
        var value = skin
        change(&value)
        skin = value
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
        get { skin.candidateFontSize }
        set {
            updateSkin { $0.candidateFontSize = newValue }
        }
    }

    // 候选字体 PostScript 名；空字符串表示系统默认
    static var fontName: String {
        get { skin.fontName }
        set {
            updateSkin { $0.fontName = newValue }
        }
    }

    /// 按当前偏好生成 NSFont
    static func candidateFont(size: CGFloat? = nil, bold: Bool = false) -> NSFont {
        candidateFont(
            size: size,
            weight: bold ? .semibold : skin.candidateWeight
        )
    }

    static func candidateFont(
        size: CGFloat? = nil,
        weight: CandidateSkin.FontWeight
    ) -> NSFont {
        let sz = size ?? CGFloat(fontSize)
        let name = fontName
        if !name.isEmpty, let custom = NSFont(name: name, size: sz) {
            if weight != .regular {
                let descriptor = custom.fontDescriptor.addingAttributes([
                    .traits: [NSFontDescriptor.TraitKey.weight: weight.nsWeight.rawValue]
                ])
                return NSFont(descriptor: descriptor, size: sz) ?? custom
            }
            return custom
        }
        return NSFont.systemFont(ofSize: sz, weight: weight.nsWeight)
    }

    // 编码显示范围：补码只显示还没打的字母，完整显示词条的全部编码。
    enum CodeDetail: String, CaseIterable {
        case remainder
        case full

        var title: String {
            switch self {
            case .remainder: return "补码"
            case .full: return "完整"
            }
        }
    }

    static var codeDetail: CodeDetail {
        get {
            if let raw = defaults.string(forKey: Keys.codeDetail),
               let detail = CodeDetail(rawValue: raw)
            {
                return detail
            }
            return .remainder
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.codeDetail)
            notify()
        }
    }

    // 是否在每个候选词后面显示它的五笔编码
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

    // 每页候选数（写入 Rime menu/page_size，见 RimeBehaviorPrefs）
    static var pageSize: Int {
        get { RimeBehaviorPrefs.pageSize }
        set { RimeBehaviorPrefs.pageSize = newValue }
    }

    /// 候选序号样式：不显示 / 带点（1.）/ 不带点（1）
    enum IndexStyle: String, CaseIterable {
        case hidden
        case withDot
        case plain

        var title: String {
            switch self {
            case .hidden: return "无"
            case .withDot: return "1."
            case .plain: return "1"
            }
        }

        // 生成页内序号文案；hidden 返回 nil。
        func label(forOneBased index: Int) -> String? {
            switch self {
            case .hidden: return nil
            case .withDot: return "\(index)."
            case .plain: return "\(index)"
            }
        }
    }

    static var indexStyle: IndexStyle {
        get {
            if let raw = defaults.string(forKey: Keys.indexStyle),
               let style = IndexStyle(rawValue: raw)
            {
                return style
            }
            // 兼容旧「显示序号」开关：关 → 无，开/未设 → 带点。
            if defaults.object(forKey: Keys.showIndex) != nil,
               !defaults.bool(forKey: Keys.showIndex)
            {
                return .hidden
            }
            return .withDot
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.indexStyle)
            defaults.set(newValue != .hidden, forKey: Keys.showIndex)
            notify()
        }
    }

    // 是否显示候选序号（由 indexStyle 派生，保留给旧调用点）
    static var showIndex: Bool {
        get { indexStyle != .hidden }
        set { indexStyle = newValue ? (indexStyle == .hidden ? .withDot : indexStyle) : .hidden }
    }

    /// 不展开候选词，只按数量显示圆点（如 3 个候选 → 3 个小点）。
    static var showCountDotsOnly: Bool {
        get { defaults.bool(forKey: Keys.showCountDotsOnly) }
        set {
            defaults.set(newValue, forKey: Keys.showCountDotsOnly)
            notify()
        }
    }

    /// 完全不显示候选框，只保留编码下划线；数字键、空格等选词照常。
    static var hideCandidatePanel: Bool {
        get { defaults.bool(forKey: Keys.hideCandidatePanel) }
        set {
            defaults.set(newValue, forKey: Keys.hideCandidatePanel)
            notify()
        }
    }

    /// 候选显示方式：候选框 / 仅数量圆点 / 不显示，两个开关互斥。
    enum DisplayMode: Int, CaseIterable {
        case panel
        case dots
        case hidden

        var title: String {
            switch self {
            case .panel: return "候选框"
            case .dots: return "仅圆点"
            case .hidden: return "不显示"
            }
        }
    }

    static var displayMode: DisplayMode {
        get {
            if hideCandidatePanel { return .hidden }
            return showCountDotsOnly ? .dots : .panel
        }
        set {
            defaults.set(newValue == .hidden, forKey: Keys.hideCandidatePanel)
            showCountDotsOnly = newValue == .dots
        }
    }

    // 珊瑚红首选底是红色，灰色编码看不清。只改还停在那组灰色上的首选编码。
    private static func correctedCoralHighlightCode(_ skin: CandidateSkin) -> CandidateSkin {
        guard skin.name == "珊瑚红" else { return skin }
        let grayLight = CandidateSkin.RGBAColor(red: 0.3245130565068493, green: 0.3245130565068493, blue: 0.3245130565068493)
        let grayDark = CandidateSkin.RGBAColor(red: 0.7462810359589042, green: 0.7462810359589042, blue: 0.7462810359589042)
        let white = CandidateSkin.RGBAColor(red: 1, green: 1, blue: 1)
        var value = skin
        if nearly(value.light.highlightCodeText, grayLight) {
            value.light.highlightCodeText = white
        }
        if nearly(value.dark.highlightCodeText, grayDark) {
            value.dark.highlightCodeText = white
        }
        return value
    }

    private static func nearly(_ lhs: CandidateSkin.RGBAColor, _ rhs: CandidateSkin.RGBAColor) -> Bool {
        abs(lhs.red - rhs.red) < 0.002
            && abs(lhs.green - rhs.green) < 0.002
            && abs(lhs.blue - rhs.blue) < 0.002
    }

    private static func notify() {
        defaults.synchronize()
        DistributedNotificationCenter.default().post(
            name: didChangeNotification,
            object: nil
        )
    }

    /// 旧皮肤没有纵向对齐时按居中补齐；旧水平/垂直边距拆成四边；缺失的新字段取默认值，避免整份配置被丢弃。
    private static func compatibleSkinData(_ data: Data) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        if object["verticalAlignment"] == nil {
            object["verticalAlignment"] = CandidateSkin.VerticalAlignment.center.rawValue
        }
        if object["offsetTop"] == nil {
            object["offsetTop"] = 6
        }
        if object["offsetLeft"] == nil {
            object["offsetLeft"] = 0
        }
        // paddingX/Y → 上/下/左/右；已有四边字段时保留用户值。
        if object["paddingTop"] == nil || object["paddingBottom"] == nil
            || object["paddingLeft"] == nil || object["paddingRight"] == nil
        {
            let x = (object["paddingX"] as? NSNumber)?.doubleValue ?? 10
            let y = (object["paddingY"] as? NSNumber)?.doubleValue ?? 5
            if object["paddingTop"] == nil { object["paddingTop"] = y }
            if object["paddingBottom"] == nil { object["paddingBottom"] = y }
            if object["paddingLeft"] == nil { object["paddingLeft"] = x }
            if object["paddingRight"] == nil { object["paddingRight"] = x }
        }
        // 旧的首选左右留白 highlightPaddingX 拆到左右两边。
        if let x = object["highlightPaddingX"] {
            if object["highlightPaddingLeft"] == nil { object["highlightPaddingLeft"] = x }
            if object["highlightPaddingRight"] == nil { object["highlightPaddingRight"] = x }
        }
        // 其余新增字段（含亮/暗配色里的新颜色）按默认皮肤补齐。
        if let fallback = (try? JSONEncoder().encode(CandidateSkin.defaultSkin))
            .flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        {
            for (key, value) in fallback {
                if let nested = value as? [String: Any], var existing = object[key] as? [String: Any] {
                    for (subKey, subValue) in nested where existing[subKey] == nil {
                        existing[subKey] = subValue
                    }
                    object[key] = existing
                } else if object[key] == nil {
                    object[key] = value
                }
            }
        }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? data
    }

    private static func migratedDefaultSkin() -> CandidateSkin {
        var value = CandidateSkin.defaultSkin
        // 只在新皮肤尚未保存时读取旧键，升级后保留用户原来的字体选择。
        let oldSize = defaults.double(forKey: Keys.fontSize)
        if oldSize > 0 {
            value.candidateFontSize = oldSize
        }
        value.fontName = defaults.string(forKey: Keys.fontName) ?? ""
        return value.normalized()
    }

    enum SkinImportError: LocalizedError {
        case invalidText
        case invalidJSON(String)
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .invalidText:
                return "配置不是有效的 UTF-8 文本。"
            case .invalidJSON(let detail):
                return "无法读取皮肤配置：\(detail)"
            case .unsupportedVersion(let version):
                return "不支持皮肤配置版本 \(version)。"
            }
        }
    }

    private enum Keys {
        static let orientation = "candidate.orientation"
        static let fontSize = "candidate.fontSize"
        static let fontName = "candidate.fontName"
        static let showPreedit = "candidate.showPreedit"
        static let codeDetail = "candidate.codeDetail"
        static let showIndex = "candidate.showIndex"
        static let indexStyle = "candidate.indexStyle"
        static let showCountDotsOnly = "candidate.showCountDotsOnly"
        static let hideCandidatePanel = "candidate.hidePanel"
        static let skin = "candidate.skin.v1"
        static let skinSlots = "candidate.skin.slots.v1"
    }
}

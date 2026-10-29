import Foundation

/// 引擎侧行为：写入 Rime `default.custom.yaml`，并通知 IME 重新部署
enum RimeBehaviorPrefs {
    static let suiteName = "cn.kylebing.inputmethod.meifengwubi.prefs"
    static let didChangeNotification = Notification.Name("cn.kylebing.inputmethod.meifengwubi.behaviorChanged")

    /// 翻页快捷键方案（对应 key_bindings.yaml 里的预设）
    enum PagingKeys: String, CaseIterable, Identifiable {
        case minusEqual
        case commaPeriod
        case brackets
        case minusAndComma

        var id: String { rawValue }

        var title: String {
            switch self {
            case .minusEqual: return "-= 翻页"
            case .commaPeriod: return ",. 翻页"
            case .brackets: return "[] 翻页"
            case .minusAndComma: return "-= 与 ,. 同时"
            }
        }

        /// 写入 Rime key_binder.bindings 的绑定行。用原始绑定而不用预设 include，
        /// 这样能直接追加到用户已有的 bindings 列表后面
        var bindingLines: [String] {
            switch self {
            case .minusEqual:
                return [
                    "- { when: has_menu, accept: minus, send: Page_Up }",
                    "- { when: has_menu, accept: equal, send: Page_Down }"
                ]
            case .commaPeriod:
                return [
                    "- { when: paging, accept: comma, send: Page_Up }",
                    "- { when: has_menu, accept: period, send: Page_Down }"
                ]
            case .brackets:
                return [
                    "- { when: paging, accept: bracketleft, send: Page_Up }",
                    "- { when: has_menu, accept: bracketright, send: Page_Down }"
                ]
            case .minusAndComma:
                return PagingKeys.minusEqual.bindingLines + PagingKeys.commaPeriod.bindingLines
            }
        }
    }

    /// 第 2、第 3 候选快捷键（走 Rime key_binder，非输入法自处理）
    enum SecondThirdKeys: String, CaseIterable, Identifiable {
        case none
        case semicolonApostrophe

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "无（仅用数字键）"
            case .semicolonApostrophe: return "; ' 选二三候选"
            }
        }

        var bindingLines: [String] {
            switch self {
            case .none:
                return []
            case .semicolonApostrophe:
                return [
                    "- { when: has_menu, accept: semicolon, send: 2 }",
                    "- { when: has_menu, accept: apostrophe, send: 3 }"
                ]
            }
        }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// 四码唯一：打满四码且只有一个候选时自动上屏。默认开；方案里的 auto_select 已关闭，由输入法按开关处理
    static var autoSelectUniqueFourCode: Bool {
        get {
            guard defaults.object(forKey: Keys.autoSelectUniqueFourCode) != nil else { return true }
            return defaults.bool(forKey: Keys.autoSelectUniqueFourCode)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoSelectUniqueFourCode)
            defaults.synchronize()
            DistributedNotificationCenter.default().post(name: didChangeNotification, object: nil)
        }
    }

    /// 空码清空：打满四码仍没有候选时清空编码。默认关，与方案里的 auto_clear 注释状态一致
    static var clearEmptyCode: Bool {
        get {
            guard defaults.object(forKey: Keys.clearEmptyCode) != nil else { return false }
            return defaults.bool(forKey: Keys.clearEmptyCode)
        }
        set {
            defaults.set(newValue, forKey: Keys.clearEmptyCode)
            defaults.synchronize()
            DistributedNotificationCenter.default().post(name: didChangeNotification, object: nil)
        }
    }

    /// 回车清码：编码中按回车只清空编码，不把编码字母上屏。默认关，与 Rime 的默认回车行为一致
    static var enterClearsCode: Bool {
        get {
            guard defaults.object(forKey: Keys.enterClearsCode) != nil else { return false }
            return defaults.bool(forKey: Keys.enterClearsCode)
        }
        set {
            defaults.set(newValue, forKey: Keys.enterClearsCode)
            defaults.synchronize()
            DistributedNotificationCenter.default().post(name: didChangeNotification, object: nil)
        }
    }

    // 每页候选数 → menu/page_size
    static var pageSize: Int {
        get {
            let v = defaults.integer(forKey: Keys.pageSize)
            if v > 0 { return min(9, max(3, v)) }
            // 兼容旧键 candidate.pageSize
            let legacy = defaults.integer(forKey: Keys.legacyPageSize)
            return legacy > 0 ? min(9, max(3, legacy)) : 9
        }
        set {
            let clamped = min(9, max(3, newValue))
            defaults.set(clamped, forKey: Keys.pageSize)
            defaults.set(clamped, forKey: Keys.legacyPageSize)
            defaults.synchronize()
            _ = persist()
        }
    }

    // 翻页键
    static var pagingKeys: PagingKeys {
        get {
            let raw = defaults.string(forKey: Keys.pagingKeys) ?? PagingKeys.minusAndComma.rawValue
            return PagingKeys(rawValue: raw) ?? .minusAndComma
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.pagingKeys)
            defaults.synchronize()
            _ = persist()
        }
    }

    // 二三候选键
    static var secondThirdKeys: SecondThirdKeys {
        get {
            let raw = defaults.string(forKey: Keys.secondThirdKeys) ?? SecondThirdKeys.semicolonApostrophe.rawValue
            return SecondThirdKeys(rawValue: raw) ?? .semicolonApostrophe
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.secondThirdKeys)
            defaults.synchronize()
            _ = persist()
        }
    }

    /// 写入 yaml + 标记 IME 需 redeploy（Prefs / App 均可调用；不依赖 librime）
    @discardableResult
    static func persist() -> String? {
        do {
            try writeCustomYAML()
        } catch {
            return error.localizedDescription
        }
        markSharedDeployFlag()
        DistributedNotificationCenter.default().post(name: didChangeNotification, object: nil)
        return nil
    }

    /// 写入 default.custom.yaml 中由设置管理的部分：只改菜单每页候选数和按键绑定，
    /// 文件里其他 patch（方案列表、标点、识别器、用户自己的绑定）原样保留
    static func writeCustomYAML() throws {
        _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
        let user = RimeResourceDeployer.resolveUserDataURL()
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let url = user.appendingPathComponent("default.custom.yaml")
        let existingText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // 内置方案列表随文件保留；文件还不存在时补上内置方案
        var schemaIds = RimeExistingLexicon.schemaIds(in: existingText)
        for id in RimeExistingLexicon.requiredSchemaIds where !schemaIds.contains(id) {
            schemaIds.append(id)
        }
        if schemaIds.isEmpty {
            schemaIds = RimeExistingLexicon.requiredSchemaIds
        }
        var bindings = pagingKeys.bindingLines
        bindings += secondThirdKeys.bindingLines
        // 数字键切换方案 / 中英等，与之前生成的配置保持一致
        bindings += Self.numberedModeSwitchBindings
        let text = RimeCustomPatchWriter.updated(
            text: existingText,
            schemaIds: schemaIds,
            pageSize: pageSize,
            bindingLines: bindings
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // Control+Shift+1..5 切换方案 / 中英 / 全角 / 简体 / 扩展字集
    private static let numberedModeSwitchBindings = [
        "- { when: always, accept: Control+Shift+1, select: .next }",
        "- { when: always, accept: Control+Shift+2, toggle: ascii_mode }",
        "- { when: always, accept: Control+Shift+3, toggle: full_shape }",
        "- { when: always, accept: Control+Shift+4, toggle: simplification }",
        "- { when: always, accept: Control+Shift+5, toggle: extended_charset }"
    ]

    /// 与 UserDictWriter.markNeedsDeploy 同路径，供 Prefs 在无词库模块时也能通知 IME
    private static func markSharedDeployFlag() {
        AppGroupPaths.ensureDirectories()
        let dir = AppGroupPaths.containerURL ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "1".write(to: dir.appendingPathComponent(".needs_deploy"), atomically: true, encoding: .utf8)
        let ud = UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
        ud.set(true, forKey: "rime.userdict.needsDeploy")
    }

    private enum Keys {
        static let pageSize = "rime.pageSize"
        static let legacyPageSize = "candidate.pageSize"
        static let pagingKeys = "rime.pagingKeys"
        static let secondThirdKeys = "rime.secondThirdKeys"
        static let clearEmptyCode = "rime.clearEmptyCode"
        static let enterClearsCode = "rime.enterClearsCode"
        static let autoSelectUniqueFourCode = "rime.autoSelectUniqueFourCode"
    }
}

/// default.custom.yaml 的增量改写：只改菜单每页候选数和按键绑定，文件里其他 patch 原样保留。
/// 之前只在带玫枫标记的文件上整体重写，内置模板没有标记，导致设置一直写不进去。
enum RimeCustomPatchWriter {
    static let beginMarker = "# >>> 由玫枫五笔设置生成，改动设置会重写这一段"
    static let endMarker = "# <<< 由玫枫五笔设置生成"

    /// 返回改写后的全文。text 为空（还没有 custom 文件）时按内置方案列表新建
    static func updated(text: String, schemaIds: [String], pageSize: Int, bindingLines: [String]) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.isEmpty ? newFileLines(schemaIds: schemaIds) : normalized.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        // 没有顶层 patch 时补一个，设置才有地方写
        if !lines.contains(where: { isKey($0, at: 0, key: "patch") }) {
            if !lines.isEmpty { lines.append("") }
            lines.append("patch:")
        }
        stripLegacyPathEntries(&lines)
        setPageSize(pageSize, in: &lines)
        setBindings(bindingLines, in: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    // 旧版写的是 "menu/page_size" 这类路径键，改成嵌套段之前先删掉，避免同键两处值
    private static func stripLegacyPathEntries(_ lines: inout [String]) {
        guard let patch = lines.firstIndex(where: { isKey($0, at: 0, key: "patch") }) else { return }
        let legacy = ["menu/page_size", "key_binder/bindings"]
        var i = patch + 1
        while i < lines.count {
            guard let name = keyName(lines[i]), indent(lines[i]) == 2 else {
                i += 1
                continue
            }
            guard legacy.contains(name) else {
                i += 1
                continue
            }
            lines.removeSubrange(i..<blockEnd(lines, from: i, indentLimit: 2))
        }
    }

    // 新建文件：内置方案列表 + 空的 patch，候选数与按键随后补进去
    private static func newFileLines(schemaIds: [String]) -> [String] {
        var lines = [
            "# 由玫枫五笔设置生成：改动「设置」里的候选数量与按键会更新下面的 patch",
            "patch:",
            "  schema_list:"
        ]
        lines += schemaIds.map { "    - schema: \($0)" }
        return lines
    }

    // 把 menu.page_size 改成指定值；已有 menu 段就只改 page_size 一行
    private static func setPageSize(_ size: Int, in lines: inout [String]) {
        guard let patch = lines.firstIndex(where: { isKey($0, at: 0, key: "patch") }) else { return }
        let end = patchEnd(lines, from: patch)
        let pageLine = "    page_size: \(size)"
        if let menu = (patch + 1..<min(end, lines.count)).first(where: { isKey(lines[$0], at: 2, key: "menu") }) {
            let menuEnd = blockEnd(lines, from: menu, indentLimit: 2)
            if let child = (menu + 1..<menuEnd).first(where: { isKey(lines[$0], at: 4, key: "page_size") }) {
                lines[child] = pageLine
            } else {
                lines.insert(pageLine, at: menu + 1)
            }
        } else {
            lines.insert(contentsOf: ["  menu:", pageLine], at: patch + 1)
        }
    }

    // 把按键绑定写进 key_binder.bindings 末尾的标记段，先清掉上一次写入的段和冲突的翻页 / 二三候选绑定
    private static func setBindings(_ bindings: [String], in lines: inout [String]) {
        stripManagedBlock(&lines)
        guard let patch = lines.firstIndex(where: { isKey($0, at: 0, key: "patch") }) else { return }
        let end = patchEnd(lines, from: patch)
        let block = ["      \(beginMarker)"] + bindings.map { "      \($0)" } + ["      \(endMarker)"]

        if let binder = (patch + 1..<min(end, lines.count)).first(where: { isKey(lines[$0], at: 2, key: "key_binder") }) {
            let binderEnd = blockEnd(lines, from: binder, indentLimit: 2)
            if let bindingsLine = (binder + 1..<binderEnd).first(where: { isKey(lines[$0], at: 4, key: "bindings") }) {
                let bindingsEnd = blockEnd(lines, from: bindingsLine, indentLimit: 4)
                let kept = (bindingsLine + 1..<bindingsEnd).map { lines[$0] }.filter { !isManagedBinding($0) }
                lines.replaceSubrange((bindingsLine + 1)..<bindingsEnd, with: kept + block)
            } else {
                lines.insert(contentsOf: ["    bindings:"] + block, at: binder + 1)
            }
        } else {
            lines.insert(contentsOf: ["  key_binder:", "    bindings:"] + block, at: patch + 1)
        }
    }

    // 删掉上一次写入的标记段；没有结束标记时删到当前列表结束
    private static func stripManagedBlock(_ lines: inout [String]) {
        guard let start = lines.firstIndex(where: { trimmed($0) == beginMarker }) else { return }
        var stop = lines.count
        if let end = ((start + 1)..<lines.count).first(where: { trimmed(lines[$0]) == endMarker }) {
            stop = end + 1
        } else {
            var i = start + 1
            while i < lines.count {
                let line = lines[i]
                if !isBlank(line) && !isComment(line) && indent(line) <= 4 { break }
                i += 1
            }
            stop = i
        }
        lines.removeSubrange(start..<stop)
    }

    // 翻页与二三候选的绑定由设置生成，写之前先去掉，避免和设置冲突
    private static func isManagedBinding(_ line: String) -> Bool {
        let t = trimmed(line)
        guard t.hasPrefix("- "), t.contains("send:") else { return false }
        let accepts = [
            "accept: minus", "accept: equal", "accept: comma", "accept: period",
            "accept: bracketleft", "accept: bracketright",
            "accept: semicolon, send: 2", "accept: apostrophe, send: 3"
        ]
        return accepts.contains { t.contains($0) }
    }

    // patch 顶层键之后、下一个顶层键之前的行
    private static func patchEnd(_ lines: [String], from start: Int) -> Int {
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            if !isBlank(line) && !isComment(line) && indent(line) == 0 { return i }
            i += 1
        }
        return lines.count
    }

    // 某个键对应的子块结束位置：缩进回到 <= indentLimit 的第一行
    private static func blockEnd(_ lines: [String], from start: Int, indentLimit: Int) -> Int {
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            if !isBlank(line) && !isComment(line) && indent(line) <= indentLimit { return i }
            i += 1
        }
        return lines.count
    }

    private static func isKey(_ line: String, at depth: Int, key: String) -> Bool {
        guard indent(line) == depth, let name = keyName(line) else { return false }
        return name == key
    }

    // 行首的键名，去掉引号；列表项、注释和空行都不算键
    private static func keyName(_ line: String) -> String? {
        let t = trimmed(line)
        guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("-"), let colon = t.firstIndex(of: ":") else { return nil }
        let name = String(t[..<colon]).trimmingCharacters(in: .whitespaces)
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func indent(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }

    private static func isBlank(_ line: String) -> Bool {
        trimmed(line).isEmpty
    }

    private static func isComment(_ line: String) -> Bool {
        trimmed(line).hasPrefix("#")
    }
}

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

        /// 写入 Rime key_binder 的 include 列表
        var bindingIncludes: [String] {
            switch self {
            case .minusEqual:
                return ["key_bindings:/paging_with_minus_equal"]
            case .commaPeriod:
                return ["key_bindings:/paging_with_comma_period"]
            case .brackets:
                return ["key_bindings:/paging_with_brackets"]
            case .minusAndComma:
                return [
                    "key_bindings:/paging_with_minus_equal",
                    "key_bindings:/paging_with_comma_period"
                ]
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

        var bindingIncludes: [String] {
            switch self {
            case .none:
                return []
            case .semicolonApostrophe:
                return ["key_bindings:/select_2nd_3rd_with_semicolon_apostrophe"]
            }
        }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
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

    /// 生成 / 覆盖 default.custom.yaml 中的 patch
    static func writeCustomYAML() throws {
        _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
        let user = RimeResourceDeployer.resolveUserDataURL()
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let url = user.appendingPathComponent("default.custom.yaml")
        // 只更新玫枫自己生成过的 custom；上游或用户原文件保持不动
        guard mayRewriteCustomYAML(at: url) else { return }
        let existingText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var schemaIds = RimeExistingLexicon.schemaIds(in: existingText)
        for id in RimeExistingLexicon.requiredSchemaIds where !schemaIds.contains(id) {
            schemaIds.append(id)
        }
        if schemaIds.isEmpty {
            schemaIds = RimeExistingLexicon.requiredSchemaIds
        }

        var lines: [String] = []
        lines.append("# 由玫枫五笔设置生成，修改「候选栏设置」会覆盖此文件中的 patch")
        lines.append("patch:")
        lines.append("  schema_list:")
        for id in schemaIds {
            lines.append("    - schema: \(id)")
        }
        lines.append("  \"menu/page_size\": \(pageSize)")
        lines.append("  \"key_binder/bindings\":")
        lines.append("    __patch:")
        lines.append("      - key_bindings:/emacs_editing")
        for inc in pagingKeys.bindingIncludes {
            lines.append("      - \(inc)")
        }
        for inc in secondThirdKeys.bindingIncludes {
            lines.append("      - \(inc)")
        }
        lines.append("      - key_bindings:/numbered_mode_switch")
        lines.append("")

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // 只改写带玫枫标记的 default.custom.yaml，避免盖掉极点原配置
    private static func mayRewriteCustomYAML(at url: URL) -> Bool {
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return existing.contains("由玫枫五笔设置生成")
    }

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
    }
}

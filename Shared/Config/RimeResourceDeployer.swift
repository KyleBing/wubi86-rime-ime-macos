import Foundation

/// App / 键盘扩展共用：把内置方案同步到可写目录
enum RimeResourceDeployer {
    static let schemaId = "wubi86_jidian"
    static let schemaFileName = "wubi86_jidian.schema.yaml"
    static let resourceVersionKey = "rime.resource.version"
    // 升版本时补齐用户目录里还没有的内置文件，已有文件不覆盖
    static let bundledResourceVersion = "6"
    /// 内置五笔方案（仅在目录还没有方案时同步进去）
    static var bundledRimeURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Rime", isDirectory: true)
            ?? Bundle.main.url(forResource: "Rime", withExtension: nil)
    }

    // 内置共享数据（default.yaml、按键预设、OpenCC）。只读，编译结果写到用户目录的 build/
    static func resolveSharedDataURL() -> URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("SharedSupport", isDirectory: true)
            ?? Bundle.main.url(forResource: "SharedSupport", withExtension: nil)
        guard let bundled,
              FileManager.default.fileExists(atPath: bundled.appendingPathComponent("default.yaml").path) else {
            return nil
        }
        return bundled
    }

    // 词库 import_tables 指向的文件不在时，补一份空码表。缺文件会让整本主词库编译失败。
    static func ensureMissingImportedDicts(at root: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for item in items where item.pathExtension == "yaml" && item.lastPathComponent.hasSuffix(".dict.yaml") {
            guard let text = try? String(contentsOf: item, encoding: .utf8) else { continue }
            for name in importedTableNames(in: text) {
                let dest = root.appendingPathComponent("\(name).dict.yaml")
                if fm.fileExists(atPath: dest.path) { continue }
                if let bundled = bundledRimeURL?.appendingPathComponent("\(name).dict.yaml"),
                   fm.fileExists(atPath: bundled.path) {
                    try? fm.copyItem(at: bundled, to: dest)
                    continue
                }
                let stub = """
                # 引用的词库文件不存在，部署时补的空表，避免主码表编译失败
                ---
                name: \(name)
                version: "0"
                sort: original
                columns:
                  - text
                  - code
                  - weight
                ...
                """
                try? stub.write(to: dest, atomically: true, encoding: .utf8)
            }
        }
    }

    // 只读 import_tables 段里的词库名，遇到下一个顶层字段就结束
    static func importedTableNames(in text: String) -> [String] {
        guard let header = try? NSRegularExpression(pattern: "^import_tables[ \\t]*:"),
              let nextKey = try? NSRegularExpression(pattern: "^[A-Za-z0-9_]+[ \\t]*:"),
              let item = try? NSRegularExpression(pattern: "^[ \\t]+-[ \\t]+([A-Za-z0-9_.-]+)")
        else { return [] }
        var names: [String] = []
        var inSection = false
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(location: 0, length: (line as NSString).length)
            if !inSection {
                if header.firstMatch(in: line, range: range) != nil { inSection = true }
                continue
            }
            if nextKey.firstMatch(in: line, range: range) != nil { break }
            if let match = item.firstMatch(in: line, range: range), match.numberOfRanges > 1 {
                names.append((line as NSString).substring(with: match.range(at: 1)))
            }
        }
        return names
    }

    /// 目录根上是否已有任意 Rime 方案。有的话就直接用，不再补内置文件。
    static func containsSchemaFile(at root: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return items.contains { $0.lastPathComponent.hasSuffix(".schema.yaml") }
    }

    /// 可写用户目录（优先 App Group；失败则用本地 Documents/rime）
    static func resolveUserDataURL() -> URL {
        if AppGroupPaths.ensureDirectories(), let url = AppGroupPaths.rimeUserDataURL {
            return url
        }
        // 自定义目录不可用（如外置盘未挂载）时退回默认目录
        if let fallback = AppGroupPaths.defaultRimeUserDataURL,
           (try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)) != nil {
            return fallback
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rime", isDirectory: true)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    /// 空目录才补内置五笔。已有方案的目录原样使用，共享目录就是该目录本身。
    @discardableResult
    static func syncBundledResourcesIfNeeded() -> (shared: URL, user: URL)? {
        let defaults = UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
        let user = resolveUserDataURL()
        if containsSchemaFile(at: user) {
            disableSchemaAutoSelectIfNeeded(at: user)
            return (user, user)
        }
        copyMissingBundledFiles(into: user)
        let marker = user.appendingPathComponent(".resource_version")
        let markerValue = (try? String(contentsOf: marker, encoding: .utf8))
            ?? defaults.string(forKey: resourceVersionKey)
        if markerValue == bundledResourceVersion {
            // 仍校验关键文件，坏配置时强制再同步
            let schemaOK = FileManager.default.fileExists(
                atPath: user.appendingPathComponent(schemaFileName).path
            )
            let dictOK = FileManager.default.fileExists(
                atPath: user.appendingPathComponent("wubi86_jidian.dict.yaml").path
            )
            if schemaOK && dictOK {
                disableSchemaAutoSelectIfNeeded(at: user)
                return (user, user)
            }
        }
        guard (try? forceSyncBundledResources(overwriteUserDict: false)) != nil else {
            return nil
        }
        disableSchemaAutoSelectIfNeeded(at: user)
        return (user, user)
    }

    /// 强制把内置方案拷到用户目录
    /// - Parameter overwriteUserDict: true 时连用户词库一并覆盖（复位用）
    @discardableResult
    static func forceSyncBundledResources(overwriteUserDict: Bool) throws -> (shared: URL, user: URL) {
        guard let bundled = bundledRimeURL,
              FileManager.default.fileExists(atPath: bundled.path) else {
            throw NSError(domain: "RimeResourceDeployer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "找不到内置方案资源 Bundle/Rime"
            ])
        }
        let user = resolveUserDataURL()
        let fm = FileManager.default
        try fm.createDirectory(at: user, withIntermediateDirectories: true)

        let files = try fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil)
        guard !files.isEmpty else {
            throw NSError(domain: "RimeResourceDeployer", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "内置 Rime 目录为空"
            ])
        }
        for file in files {
            let name = file.lastPathComponent
            // 用户目录已有自己的方案时，不补 default.custom.yaml，避免换掉原方案列表
            if name == "default.custom.yaml", !overwriteUserDict, userAlreadyHasOwnSchema(at: user) {
                continue
            }
            let dest = user.appendingPathComponent(name)
            // 常规同步只补缺失文件，不改已有内容；复位才覆盖
            if !overwriteUserDict, fm.fileExists(atPath: dest.path) {
                continue
            }
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: file, to: dest)
        }
        let schema = user.appendingPathComponent(schemaFileName)
        let dict = user.appendingPathComponent("wubi86_jidian.dict.yaml")
        let custom = user.appendingPathComponent("default.custom.yaml")
        // 用户自己的方案目录可以没有 default.custom.yaml
        let needsCustom = !userAlreadyHasOwnSchema(at: user)
        guard fm.fileExists(atPath: schema.path),
              fm.fileExists(atPath: dict.path),
              !needsCustom || fm.fileExists(atPath: custom.path) else {
            throw NSError(domain: "RimeResourceDeployer", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "内置方案拷贝不完整，缺少 schema/dict/default.custom"
            ])
        }
        let marker = user.appendingPathComponent(".resource_version")
        try bundledResourceVersion.write(to: marker, atomically: true, encoding: .utf8)
        let defaults = UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
        defaults.set(bundledResourceVersion, forKey: resourceVersionKey)
        return (user, user)
    }

    // 把内置五笔方案里用户目录还没有的文件补进去，已有文件不动
    static func copyMissingBundledFiles(into destRoot: URL) {
        guard let bundled = bundledRimeURL,
              FileManager.default.fileExists(atPath: bundled.path) else { return }
        copyMissing(from: bundled, to: destRoot)
    }

    private static func copyMissing(from source: URL, to dest: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        guard let items = try? fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for item in items {
            let target = dest.appendingPathComponent(item.lastPathComponent)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if item.lastPathComponent == "default.custom.yaml", userAlreadyHasOwnSchema(at: dest) {
                continue
            }
            if fm.fileExists(atPath: target.path) {
                // 已有文件保持原样，只往还没有的子目录里补文件
                if isDir {
                    copyMissing(from: item, to: target)
                }
                continue
            }
            try? fm.copyItem(at: item, to: target)
        }
    }

    // 已安装用户目录里的方案仍可能是旧的 auto_select: true，关掉后四码唯一才交给设置开关
    @discardableResult
    static func disableSchemaAutoSelectIfNeeded(at root: URL) -> Bool {
        let url = root.appendingPathComponent(schemaFileName)
        guard var text = try? String(contentsOf: url, encoding: .utf8),
              text.contains("auto_select: true") else { return false }
        text = text.replacingOccurrences(of: "auto_select: true", with: "auto_select: false")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            UserDictWriter.markNeedsDeploy()
            return true
        } catch {
            return false
        }
    }

    // 方案文件已在，且内容和内置副本不同，说明这是用户自己的 Rime 目录
    private static func userAlreadyHasOwnSchema(at root: URL) -> Bool {
        let fm = FileManager.default
        let dest = root.appendingPathComponent(schemaFileName)
        guard fm.fileExists(atPath: dest.path),
              let existing = try? String(contentsOf: dest, encoding: .utf8),
              let bundled = bundledRimeURL?.appendingPathComponent(schemaFileName),
              let bundledText = try? String(contentsOf: bundled, encoding: .utf8) else {
            return false
        }
        let left = existing.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let right = bundledText.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return left != right
    }
}

/// 读取用户 Rime 目录里已有的方案列表，不改目录中的文件。
enum RimeExistingLexicon {
    static let requiredSchemaIds = ["wubi86_jidian", "pinyin_simp"]

    // schema_list 里的方案，编译后 build/ 下应有 .schema.yaml 或 .table.bin
    static func schemasMissingBuild(at root: URL) -> [String] {
        let customURL = root.appendingPathComponent("default.custom.yaml")
        let custom = (try? String(contentsOf: customURL, encoding: .utf8)) ?? ""
        var ids = schemaIds(in: custom)
        if ids.isEmpty {
            let fallback = (try? String(contentsOf: root.appendingPathComponent("default.yaml"), encoding: .utf8)) ?? ""
            ids = schemaIds(in: fallback)
        }
        if ids.isEmpty { ids = requiredSchemaIds }
        let build = root.appendingPathComponent("build", isDirectory: true)
        return ids.filter { id in
            let schema = build.appendingPathComponent("\(id).schema.yaml")
            let table = build.appendingPathComponent("\(id).table.bin")
            return !FileManager.default.fileExists(atPath: schema.path)
                && !FileManager.default.fileExists(atPath: table.path)
        }
    }

    // 从 yaml 里按出现顺序收集 `schema:` id
    static func schemaIds(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(
            pattern: "(?m)^[ \\t]*-[ \\t]+schema:[ \\t]*[\"']?([A-Za-z0-9_.-]+)[\"']?"
        ) else { return [] }
        let ns = text as NSString
        var ids: [String] = []
        for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let id = ns.substring(with: match.range(at: 1))
            if !ids.contains(id) { ids.append(id) }
        }
        return ids
    }
}


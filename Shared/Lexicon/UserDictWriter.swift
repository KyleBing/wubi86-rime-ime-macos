import Foundation

/// 用户词库读写；列顺序与主码表一致：text / code / weight
/// 分组机制对齐码表助手（wubi-dict-editor）：
/// - 头：`dict_grouped: true`
/// - 组：`## 分组名`，组与组之间空一行
/// - 空组保留；空名展示为「- 未命名 -」
enum UserDictWriter {
    static let needsDeployKey = "rime.userdict.needsDeploy"
    /// 空行切组时无名组的落盘名（对齐 parseGroupMode）
    static let unnamedFallback = "未命名"

    // MARK: - 兼容旧 API（扁平词条）

    static func loadEntries(from url: URL = AppGroupPaths.userDictURL ?? URL(fileURLWithPath: "/dev/null")) -> [UserDictEntry] {
        loadDocument(from: url).allEntries
    }

    static func saveEntries(_ entries: [UserDictEntry], to url: URL) throws {
        try saveDocument(.flat(entries: entries), to: url)
    }

    // MARK: - 分组文档

    static func loadDocument(from url: URL) -> UserDictDocument {
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            return .empty
        }
        return parseDocument(data)
    }

    // markDeploy 为假时只写快照，不通知输入法重载。
    static func saveDocument(_ document: UserDictDocument, to url: URL, markDeploy: Bool = true) throws {
        let version = ISO8601DateFormatter().string(from: Date())
        // 只要还有分组信息（多组 / 有组名 / 分组模式），落盘必须保留 ##，不可压成扁平表
        let hasGroupInfo = document.shouldPreserveGroupHeaders
        if hasGroupInfo {
            var yaml = """
            # Rime dictionary
            # encoding: utf-8
            ---
            name: wubi86_jidian_user
            version: "\(version)"
            dict_grouped: true
            sort: by_weight
            ...

            """
            let groups = document.groups.isEmpty ? [UserDictGroup(name: "")] : document.groups
            // 每组先写 ## 分组行，再写词条（与码表助手一致：标题在词条上方）
            let body = groups.map { group -> String in
                var block = "## \(group.name)\n"
                for entry in group.entries {
                    block += yamlLine(for: entry) + "\n"
                }
                if block.hasSuffix("\n") { block.removeLast() }
                return block
            }.joined(separator: "\n\n")
            if !body.isEmpty {
                yaml += body
                yaml += "\n"
            }
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        } else {
            // 真正无分组信息时才写扁平码表
            var yaml = """
            # Rime dictionary
            # encoding: utf-8
            ---
            name: wubi86_jidian_user
            version: "\(version)"
            dict_grouped: false
            sort: by_weight
            ...

            """
            for entry in document.allEntries {
                yaml += yamlLine(for: entry) + "\n"
            }
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        }
        if markDeploy {
            markNeedsDeploy()
        }
    }

    /// 解析 yaml：对齐 dictParseCore.parseGroupMode / parseNormalMode
    static func parseDocument(_ fileContent: String) -> UserDictDocument {
        let normalized = fileContent.replacingOccurrences(of: "\r\n", with: "\n")
        guard let headerEnd = normalized.range(of: "...") else {
            if normalized.contains("##") {
                let groups = parseGroupModeBody(normalized)
                return groups.isEmpty
                    ? .empty
                    : UserDictDocument(isGroupMode: true, groups: groups)
            }
            let entries = parseFlatBody(normalized)
            return entries.isEmpty ? .empty : .flat(entries: entries)
        }
        let header = String(normalized[..<headerEnd.upperBound])
        let body = String(normalized[headerEnd.upperBound...])
        let isGroupMode = header.contains("dict_grouped: true") || body.contains("##")
        if isGroupMode {
            let groups = parseGroupModeBody(body)
            return UserDictDocument(
                isGroupMode: true,
                groups: groups.isEmpty ? [UserDictGroup(name: "")] : groups
            )
        }
        // 非分组：即使无词条也保持 flat，避免被当成分组模式
        return .flat(entries: parseFlatBody(body))
    }

    /// 对齐 parseGroupMode：`##` 开组，空行切组并保留空组
    private static func parseGroupModeBody(_ body: String) -> [UserDictGroup] {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var wordsGroup: [UserDictGroup] = []
        var temp: UserDictGroup?
        var lastItemIsEmptyLine = false

        for item in lines {
            if item.hasPrefix("##") {
                // 仅当当前组已有名字时推进（与编辑器一致）
                if let cur = temp, !cur.name.isEmpty {
                    wordsGroup.append(cur)
                } else if let cur = temp, !cur.entries.isEmpty {
                    // 无名但有词：补成未命名再推进，避免丢词
                    var named = cur
                    named.name = unnamedFallback
                    wordsGroup.append(named)
                }
                let name = String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                temp = UserDictGroup(name: name)
                lastItemIsEmptyLine = false
            } else if item.contains("\t") {
                guard let entry = parseEntryLine(item) else { continue }
                if temp == nil {
                    temp = UserDictGroup(name: "")
                }
                temp?.entries.append(entry)
                lastItemIsEmptyLine = false
            } else if item.hasPrefix("#") {
                lastItemIsEmptyLine = false
            } else {
                // 空行：切组；连续空行只切一次
                if !lastItemIsEmptyLine, let cur = temp {
                    var flushed = cur
                    if flushed.name.isEmpty {
                        flushed.name = unnamedFallback
                    }
                    wordsGroup.append(flushed)
                    temp = UserDictGroup(name: "")
                }
                lastItemIsEmptyLine = true
            }
        }
        // 末尾组：有组名或有词都保留（空分组的 ## 行不可丢）
        if let cur = temp, !cur.name.isEmpty || !cur.entries.isEmpty {
            wordsGroup.append(cur)
        }
        return wordsGroup
    }

    private static func parseFlatBody(_ body: String) -> [UserDictEntry] {
        var entries: [UserDictEntry] = []
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let entry = parseEntryLine(line) {
                entries.append(entry)
            }
        }
        return entries
    }

    // 词库检索和删行也要按同一规则拆列。
    static func parseEntryLine(_ line: String) -> UserDictEntry? {
        // 优先按 tab 拆（码表助手标准）；兼容空格分隔旧行
        let parts: [String]
        if line.contains("\t") {
            parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        } else {
            parts = line.split(whereSeparator: { $0 == " " }).map(String.init)
        }
        guard parts.count >= 2 else { return nil }
        var text = parts[0]
        var code = parts[1].replacingOccurrences(of: "\r", with: "")
        // 第三列是权重；缺列或空列表示没有权重，不补默认值
        let weight: Int?
        if parts.count >= 3 {
            let raw = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            weight = Int(raw)
        } else {
            weight = nil
        }
        // 第四列及之后是备注（对齐码表助手 word.note）
        let note = parts.count >= 4
            ? parts[3...].joined(separator: "\t")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let firstLooksLikeCode = text.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
        let secondHasCJK = code.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
        if firstLooksLikeCode && secondHasCJK {
            swap(&text, &code)
        }
        return UserDictEntry(code: code.lowercased(), text: text, weight: weight, note: note)
    }

    // 有备注时写出四列，避免备注被当成权重
    private static func yamlLine(for entry: UserDictEntry) -> String {
        let note = entry.note
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            if let weight = entry.weight {
                return "\(entry.text)\t\(entry.code)\t\(weight)"
            }
            return "\(entry.text)\t\(entry.code)"
        }
        let weight = entry.weight.map(String.init) ?? ""
        return "\(entry.text)\t\(entry.code)\t\(weight)\t\(note)"
    }

    static func markNeedsDeploy() {
        // App 与 IME 不同 Bundle：用 Application Support 文件跨进程通知
        AppGroupPaths.ensureDirectories()
        let url = deployFlagURL()
        try? "1".write(to: url, atomically: true, encoding: .utf8)
        let defaults = UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
        defaults.set(true, forKey: needsDeployKey)
    }

    static func consumeNeedsDeploy() -> Bool {
        let needed = peekNeedsDeploy()
        guard needed else { return false }
        clearNeedsDeploy()
        return true
    }

    // 只查看，不清标记。输入法正在打字时先留着，等编码结束再部署。
    static func peekNeedsDeploy() -> Bool {
        let url = deployFlagURL()
        if FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        let defaults = UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
        return defaults.bool(forKey: needsDeployKey)
    }

    private static func clearNeedsDeploy() {
        let url = deployFlagURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        let defaults = UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
        if defaults.bool(forKey: needsDeployKey) {
            defaults.set(false, forKey: needsDeployKey)
        }
    }

    private static func deployFlagURL() -> URL {
        let dir = AppGroupPaths.containerURL
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".needs_deploy")
    }
}

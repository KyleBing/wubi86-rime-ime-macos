import Foundation

/// 主词库自动编码（对齐 wubi-dict-editor DictMap）
enum WubiDictEncoder {
    static let mainDictNameKey = "wubi.mainDict.fileName"
    static let defaultMainDictName = "wubi86_jidian.dict.yaml"
    static let charMapFileName = "wubi_charmap.tsv"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
    }

    static var selectedMainDictName: String {
        get { defaults.string(forKey: mainDictNameKey) ?? defaultMainDictName }
        set { defaults.set(newValue, forKey: mainDictNameKey) }
    }

    static var mainDictURL: URL {
        RimeResourceDeployer.resolveUserDataURL().appendingPathComponent(selectedMainDictName)
    }

    static var charMapURL: URL {
        RimeResourceDeployer.resolveUserDataURL().appendingPathComponent(charMapFileName)
    }

    /// 用户目录下可选的码表文件
    static func availableDictFileNames() -> [String] {
        let dir = RimeResourceDeployer.resolveUserDataURL()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".dict.yaml") && !$0.contains("user") }
            .sorted()
    }

    static func charMapStatus() -> (exists: Bool, count: Int, modified: Date?) {
        let url = charMapURL
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (false, 0, nil)
        }
        let count = text.split(whereSeparator: \.isNewline).filter { $0.contains("\t") }.count
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return (true, count, modified)
    }

    /// 从主词库提取单字码表并落盘
    @discardableResult
    static func rebuildCharMap() throws -> Int {
        let url = mainDictURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "WubiDictEncoder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "找不到主词库文件：\(selectedMainDictName)"
            ])
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let map = extractCharacterMap(from: content)
        var out = ""
        for (ch, code) in map.sorted(by: { $0.key < $1.key }) {
            out += "\(ch)\t\(code)\n"
        }
        try out.write(to: charMapURL, atomically: true, encoding: .utf8)
        cachedMap = map
        return map.count
    }

    /// 是否为汉字（CJK 统一汉字及扩展 A）
    static func isChineseHanzi(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        let v = scalar.value
        return (v >= 0x4E00 && v <= 0x9FFF) || (v >= 0x3400 && v <= 0x4DBF)
    }

    /// 只抽取词条中的汉字，标点 / 英文 / 数字等忽略
    static func chineseCharacters(in word: String) -> [Character] {
        Array(word.filter(isChineseHanzi))
    }

    /// 按五笔规则给词条编码；仅匹配汉字，缺字时返回空串
    static func encode(word: String) -> String {
        let map = loadCharMap()
        guard !map.isEmpty else { return "" }
        // 带其它内容时只拿汉字参与编码
        var chars = chineseCharacters(in: word)
        guard !chars.isEmpty else { return "" }
        guard chars.count >= 2 else {
            // 单字：取已有码，没有则空
            guard let ch = chars.first else { return "" }
            return map[String(ch)] ?? ""
        }
        if chars.count > 4 {
            chars = [chars[0], chars[1], chars[2], chars[chars.count - 1]]
        }
        let codes = chars.map { map[String($0)] ?? "" }
        if codes.contains(where: \.isEmpty) { return "" }
        switch codes.count {
        case 2:
            return String(codes[0].prefix(2)) + String(codes[1].prefix(2))
        case 3:
            return String(codes[0].prefix(1)) + String(codes[1].prefix(1)) + String(codes[2].prefix(2))
        default:
            return String(codes[0].prefix(1)) + String(codes[1].prefix(1))
                + String(codes[2].prefix(1)) + String(codes[codes.count - 1].prefix(1))
        }
    }

    // MARK: - Private

    private static var cachedMap: [String: String]?

    private static func loadCharMap() -> [String: String] {
        if let cachedMap { return cachedMap }
        guard let text = try? String(contentsOf: charMapURL, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].count == 1 else { continue }
            map[parts[0]] = parts[1].lowercased()
        }
        cachedMap = map
        return map
    }

    static func clearCache() {
        cachedMap = nil
    }

    /// 提取单字：优先收录每个字第一条长度≥2 的编码（与 DictMap 一致）
    static func extractCharacterMap(from fileContent: String) -> [String: String] {
        var map: [String: String] = [:]
        var inBody = false
        let normalized = fileContent.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed == "..." {
                inBody = true
                continue
            }
            if !inBody, trimmed.hasPrefix("---") { continue }
            // 无 yaml 头时整文件当码表体
            if !inBody, raw.contains("\t"), !trimmed.hasPrefix("#"), !trimmed.hasPrefix("name:") {
                inBody = true
            }
            guard inBody else { continue }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = raw.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 2 else { continue }
            let text = parts[0]
            let code = parts[1].lowercased()
            guard text.count == 1, code.count >= 2 else { continue }
            if map[text] == nil {
                map[text] = code
            }
        }
        return map
    }
}

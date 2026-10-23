import AppKit
import Foundation

/// 一条码表命中：词条来自哪个文件、哪个分组。
struct DictLexiconHit {
    let fileURL: URL
    /// `##` 后面的分组名；扁平码表为空。
    let groupName: String
    /// 给用户看的来源，例如「用户词 · 工作」「主词库」。
    let sourceTitle: String
    let entry: UserDictEntry

    // 同编码表的五列：词条、编码、权重、词库、分组。没有权重或分组就留空。
    var tableColumns: [String] {
        let group = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            entry.text,
            entry.code,
            entry.weight.map(String.init) ?? "",
            Self.lexiconName(fileName: fileURL.lastPathComponent),
            group
        ]
    }

    static let columnTitles = ["词条", "编码", "权重", "词库", "分组"]
    static let tableFont = NSFont.systemFont(ofSize: 11)
    static let headerFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    // 按每列最宽的内容计算制表位，中英文混排也能上下对齐。
    static func alignedTable(_ hits: [DictLexiconHit], limit: Int = 40) -> NSAttributedString {
        let sorted = hits.sorted { a, b in
            let wa = a.entry.weight ?? -1
            let wb = b.entry.weight ?? -1
            if wa != wb { return wa > wb }
            if a.sourceTitle != b.sourceTitle { return a.sourceTitle < b.sourceTitle }
            return a.entry.text < b.entry.text
        }
        let shown = Array(sorted.prefix(limit))
        let rows = shown.map(\.tableColumns)
        let gap: CGFloat = 18
        var x: CGFloat = 0
        var stops: [NSTextTab] = []
        for index in 0..<(columnTitles.count - 1) {
            let headerWidth = textWidth(columnTitles[index], font: headerFont)
            let bodyWidth = rows.map { textWidth($0[index], font: tableFont) }.max() ?? 0
            x += max(headerWidth, bodyWidth) + gap
            stops.append(NSTextTab(textAlignment: .left, location: x, options: [:]))
        }
        let style = NSMutableParagraphStyle()
        style.tabStops = stops
        style.defaultTabInterval = 2000
        style.lineSpacing = 3

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: columnTitles.joined(separator: "\t") + "\n", attributes: [
            .font: headerFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ]))
        for (index, row) in rows.enumerated() {
            let line = row.joined(separator: "\t") + (index == rows.count - 1 ? "" : "\n")
            result.append(NSAttributedString(string: line, attributes: [
                .font: tableFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style
            ]))
        }
        let rest = sorted.count - shown.count
        if rest > 0 {
            result.append(NSAttributedString(string: "\n还有 \(rest) 条未列出", attributes: [
                .font: tableFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]))
        }
        return result
    }

    static func message(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: tableFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    static func lexiconName(fileName: String) -> String {
        switch fileName {
        case "wubi86_jidian.dict.yaml":
            return "主词库"
        case "wubi86_jidian_user.dict.yaml":
            return "用户词"
        case "wubi86_jidian_user_hamster.dict.yaml":
            return "Hamster 词库"
        case "wubi86_jidian_extra.dict.yaml":
            return "扩展词库"
        default:
            return fileName.replacingOccurrences(of: ".dict.yaml", with: "")
        }
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// 按编码 / 词面检索当前方案导入的码表，并支持从原文件删掉一行。
final class DictLexiconIndex {
    static let shared = DictLexiconIndex()

    private var byCode: [String: [DictLexiconHit]] = [:]
    private var byText: [String: [DictLexiconHit]] = [:]
    private var stamp = ""
    private let lock = NSLock()

    private init() {}

    // 造词或删词后丢弃缓存，下次查询按文件重新读。
    func invalidate() {
        lock.lock()
        invalidateUnlocked()
        lock.unlock()
    }

    func hits(code: String) -> [DictLexiconHit] {
        lock.lock()
        defer { lock.unlock() }
        reloadIfNeeded()
        return byCode[code.lowercased()] ?? []
    }

    func hits(text: String) -> [DictLexiconHit] {
        lock.lock()
        defer { lock.unlock() }
        reloadIfNeeded()
        return byText[text] ?? []
    }

    // 候选条词后要标的编码。普通输入只标还没打的后几码；z 反查标词库里单字的五笔全码。
    func displayCodes(texts: [String], preedit: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        reloadIfNeeded()
        let reverse = Self.isReverseLookup(preedit)
        let prefix = preedit.lowercased().filter { $0.isASCII && $0.isLetter }
        let showFull = IMEAppearancePrefs.codeDetail == .full
        return texts.map {
            displayCodeUnlocked(text: $0, prefix: prefix, reverse: reverse, showFull: showFull)
        }
    }

    // 候选条词后要标的备注：取码表第四列的备注，同词多条时优先当前编码命中的那条。
    func displayNotes(texts: [String], preedit: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        reloadIfNeeded()
        let prefix = preedit.lowercased().filter { $0.isASCII && $0.isLetter }
        let reverse = Self.isReverseLookup(preedit)
        return texts.map { text in
            let all = byText[text] ?? []
            guard !all.isEmpty else { return "" }
            // 反查时输入的是拼音，不对编码做筛选。
            let matched = reverse ? all : all.filter { prefix.isEmpty || $0.entry.code.hasPrefix(prefix) }
            let pool = matched.isEmpty ? all : matched
            let exact = prefix.isEmpty ? [] : pool.filter { $0.entry.code == prefix }
            let preferred = exact.isEmpty ? pool : exact
            return preferred.first { !$0.entry.note.isEmpty }?.entry.note ?? ""
        }
    }

    /// 当前输入下，这个候选最可能对应的码，以及同词的其它编码。
    func match(text: String, preedit: String) -> (hits: [DictLexiconHit], otherCodes: [String]) {
        lock.lock()
        defer { lock.unlock() }
        reloadIfNeeded()
        let prefix = preedit.lowercased().filter { $0.isLetter }
        let all = (byText[text] ?? []).filter { prefix.isEmpty || $0.entry.code.hasPrefix(prefix) }
        guard !all.isEmpty else { return ([], []) }
        let exact = all.filter { $0.entry.code == prefix }
        let chosenCode: String
        if !exact.isEmpty {
            chosenCode = prefix
        } else {
            // 编码还没输完时，取最短的补全码（权重高的优先）。
            chosenCode = all.min { a, b in
                if a.entry.code.count != b.entry.code.count {
                    return a.entry.code.count < b.entry.code.count
                }
                return (a.entry.weight ?? 0) > (b.entry.weight ?? 0)
            }?.entry.code ?? all[0].entry.code
        }
        let chosen = all.filter { $0.entry.code == chosenCode }
        let others = Set(all.map(\.entry.code)).subtracting([chosenCode]).sorted()
        return (chosen, others)
    }

    /// 从命中的那个码表文件里删掉对应的一行。
    func remove(_ hit: DictLexiconHit) throws {
        lock.lock()
        defer { lock.unlock() }
        let raw = try String(contentsOf: hit.fileURL, encoding: .utf8)
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        var group = ""
        var removed = false
        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                group = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard !removed, let entry = UserDictWriter.parseEntryLine(line) else { continue }
            guard entry.text == hit.entry.text, entry.code == hit.entry.code, group == hit.groupName else { continue }
            lines.remove(at: index)
            removed = true
            break
        }
        guard removed else {
            throw NSError(domain: "DictLexiconIndex", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "词库里已经没有「\(hit.entry.text)」。"
            ])
        }
        var out = lines.joined(separator: "\n")
        if normalized.hasSuffix("\n"), !out.hasSuffix("\n") {
            out += "\n"
        }
        try out.write(to: hit.fileURL, atomically: true, encoding: .utf8)
        UserDictWriter.markNeedsDeploy()
        invalidateUnlocked()
    }

    // 只改这一行的权重列，分组、备注和文件里的先后顺序保持不动。
    func updateWeight(_ hit: DictLexiconHit, to weight: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        let raw = try String(contentsOf: hit.fileURL, encoding: .utf8)
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        var group = ""
        var updated = false
        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                group = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard !updated, let entry = UserDictWriter.parseEntryLine(line) else { continue }
            guard entry.text == hit.entry.text, entry.code == hit.entry.code, group == hit.groupName else { continue }
            lines[index] = Self.lineReplacingWeight(line, weight: weight)
            updated = true
        }
        guard updated else {
            throw NSError(domain: "DictLexiconIndex", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "词库里已经没有「\(hit.entry.text)」。"
            ])
        }
        var out = lines.joined(separator: "\n")
        if normalized.hasSuffix("\n"), !out.hasSuffix("\n") {
            out += "\n"
        }
        try out.write(to: hit.fileURL, atomically: true, encoding: .utf8)
        UserDictWriter.markNeedsDeploy()
        invalidateUnlocked()
    }

    // 第三列是权重。有备注或词根时留在后面，不整行重写。
    private static func lineReplacingWeight(_ line: String, weight: Int) -> String {
        let value = String(weight)
        if line.contains("\t") {
            var parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            while parts.count < 3 { parts.append("") }
            parts[2] = value
            return parts.joined(separator: "\t")
        }
        var parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3 {
            parts[2] = value
            return parts.joined(separator: " ")
        }
        return line + "\t" + value
    }

    // z 开头、后面只有字母或结束符 '，与方案里的反查规则一致。
    private static func isReverseLookup(_ preedit: String) -> Bool {
        let compact = preedit.lowercased().filter { $0.isASCII && ($0.isLetter || $0 == "'") }
        return compact.range(of: #"^z[a-z]*'?$"#, options: .regularExpression) != nil
    }

    // 反查输入的是拼音，不能拿来对五笔码；词组没有对应五笔码时留空，不按拆字规则现造。
    private func displayCodeUnlocked(text: String, prefix: String, reverse: Bool, showFull: Bool) -> String {
        let all = byText[text] ?? []
        if reverse {
            guard text.count == 1 else { return "" }
            return all.max { $0.entry.code.count < $1.entry.code.count }?.entry.code ?? ""
        }
        let matched = all.filter { prefix.isEmpty || $0.entry.code.hasPrefix(prefix) }
        guard let code = matched.min(by: { a, b in
            if a.entry.code.count != b.entry.code.count {
                return a.entry.code.count < b.entry.code.count
            }
            return (a.entry.weight ?? 0) > (b.entry.weight ?? 0)
        })?.entry.code, code.hasPrefix(prefix) else { return "" }
        // 补码时已经打过的字母不再重复显示。反查输入的是拼音，单字始终给全码。
        if showFull || prefix.isEmpty { return code }
        return String(code.dropFirst(prefix.count))
    }

    private func invalidateUnlocked() {
        stamp = ""
        byCode = [:]
        byText = [:]
    }

    // MARK: - 索引

    private func reloadIfNeeded() {
        let files = lexiconFiles()
        let next = files.map { url -> String in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? 0
            return "\(url.path)|\(modified)|\(size)"
        }.joined(separator: "\n")
        guard next != stamp else { return }
        var codes: [String: [DictLexiconHit]] = [:]
        var texts: [String: [DictLexiconHit]] = [:]
        for url in files {
            index(url: url, codes: &codes, texts: &texts)
        }
        byCode = codes
        byText = texts
        stamp = next
    }

    // 主词库加上它 import_tables 里列出的码表。
    private func lexiconFiles() -> [URL] {
        let dir = RimeResourceDeployer.resolveUserDataURL()
        let mainURL = dir.appendingPathComponent(WubiDictEncoder.selectedMainDictName)
        var urls: [URL] = []
        if FileManager.default.fileExists(atPath: mainURL.path) {
            urls.append(mainURL)
        }
        guard let text = try? String(contentsOf: mainURL, encoding: .utf8) else { return urls }
        let header = text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix { $0.trimmingCharacters(in: .whitespaces) != "..." }
        var inImport = false
        for lineSub in header {
            let trimmed = lineSub.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import_tables:") {
                inImport = true
                continue
            }
            guard inImport else { continue }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard trimmed.hasPrefix("-") else { break }
            var name = trimmed
            while name.hasPrefix("-") {
                name.removeFirst()
            }
            name = name.trimmingCharacters(in: .whitespaces)
            if let hash = name.firstIndex(of: "#") {
                name = String(name[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty else { continue }
            let file = name.hasSuffix(".dict.yaml") ? name : name + ".dict.yaml"
            let url = dir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path), !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }

    private func index(
        url: URL,
        codes: inout [String: [DictLexiconHit]],
        texts: inout [String: [DictLexiconHit]]
    ) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        let fileName = url.lastPathComponent
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let grouped = normalized.contains("\n##") || normalized.hasPrefix("##")
        var group = ""
        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##") {
                group = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let entry = UserDictWriter.parseEntryLine(line) else { continue }
            let hit = DictLexiconHit(
                fileURL: url,
                groupName: group,
                sourceTitle: sourceTitle(fileName: fileName, groupName: group, grouped: grouped),
                entry: entry
            )
            codes[entry.code, default: []].append(hit)
            texts[entry.text, default: []].append(hit)
        }
    }

    // 文件名换成用户能看懂的词库名；分组码表再带上组名。
    private func sourceTitle(fileName: String, groupName: String, grouped: Bool) -> String {
        let base = DictLexiconHit.lexiconName(fileName: fileName)
        guard grouped else { return base }
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "\(base) · 未分组" }
        return "\(base) · \(name)"
    }
}

extension NSTextView {
    // 表格按内容变宽，超出窗口时横向滚动，避免换行把列拆开。
    func configureAsLexiconTable() {
        isVerticallyResizable = true
        isHorizontallyResizable = true
        textContainer?.widthTracksTextView = false
        textContainer?.heightTracksTextView = false
        textContainer?.containerSize = NSSize(width: 8000, height: CGFloat.greatestFiniteMagnitude)
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    func setLexiconTable(_ text: NSAttributedString) {
        textStorage?.setAttributedString(text)
    }
}

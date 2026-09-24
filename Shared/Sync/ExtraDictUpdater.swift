import Foundation

/// 线上扩展词库：拉取后覆盖 `wubi86_jidian_extra.dict.yaml`。只写文件，不提供查看或编辑。
enum ExtraDictUpdater {
    static var activeURL: URL {
        RimeResourceDeployer.resolveUserDataURL()
            .appendingPathComponent(WubiCloudConfig.extraDictFileName)
    }

    static func localEntryCount() -> Int {
        guard let text = try? String(contentsOf: activeURL, encoding: .utf8) else { return 0 }
        return UserDictWriter.parseDocument(text).entryCount
    }

    // 覆盖写入。added 是相对拉取前本地没有的「词+编码」条数。
    static func applyOnlineItems(_ items: [WubiCloudAPI.ExtraWordItem]) throws -> (added: Int, wordCount: Int) {
        let previous = localKeys()
        let document = buildDocument(from: items)
        let incoming = Set(document.allEntries.map { "\($0.text)\t\($0.code)" })
        let added = incoming.subtracting(previous).count
        let yaml = serializeExtraYAML(document)
        try yaml.write(to: activeURL, atomically: true, encoding: .utf8)
        WubiCloudConfig.lastExtraPullAt = Date()
        UserDictWriter.markNeedsDeploy()
        return (added, document.entryCount)
    }

    private static func localKeys() -> Set<String> {
        guard let text = try? String(contentsOf: activeURL, encoding: .utf8) else { return [] }
        return Set(UserDictWriter.parseDocument(text).allEntries.map { "\($0.text)\t\($0.code)" })
    }

    static func buildDocument(from items: [WubiCloudAPI.ExtraWordItem]) -> UserDictDocument {
        let sorted = items.sorted { a, b in
            if a.category_id != b.category_id { return a.category_id < b.category_id }
            return (a.id ?? 0) < (b.id ?? 0)
        }
        var groups: [UserDictGroup] = []
        var lastName: String?
        for item in sorted {
            let name = item.category_name
            let entry = UserDictEntry(
                code: item.code,
                text: item.word,
                weight: max(0, item.weight),
                note: item.comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            if lastName != name {
                groups.append(UserDictGroup(name: name, entries: [entry]))
                lastName = name
            } else if !groups.isEmpty {
                groups[groups.count - 1].entries.append(entry)
            }
        }
        if groups.isEmpty {
            return UserDictDocument(isGroupMode: true, groups: [UserDictGroup(name: "")])
        }
        return UserDictDocument(isGroupMode: true, groups: groups)
    }

    static func serializeExtraYAML(_ document: UserDictDocument) -> String {
        let version = ISO8601DateFormatter().string(from: Date())
        var yaml = """
        # Rime dictionary
        # encoding: utf-8
        ---
        name: wubi86_jidian_extra
        note: "扩展词库"
        version: "\(version)"
        dict_grouped: true
        sort: original
        ...

        """
        let groups = document.groups.isEmpty ? [UserDictGroup(name: "")] : document.groups
        let body = groups.map { group -> String in
            var block = "## \(group.name)\n"
            for entry in group.entries {
                block += line(for: entry) + "\n"
            }
            if block.hasSuffix("\n") { block.removeLast() }
            return block
        }.joined(separator: "\n\n")
        if !body.isEmpty {
            yaml += body
            yaml += "\n"
        }
        return yaml
    }

    // 无权重且无备注时只写词和编码；有备注时补上权重列，避免备注错位
    private static func line(for entry: UserDictEntry) -> String {
        let note = entry.note
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            if let weight = entry.weight, weight > 0 {
                return "\(entry.text)\t\(entry.code)\t\(weight)"
            }
            return "\(entry.text)\t\(entry.code)"
        }
        let weight = entry.weight.map(String.init) ?? ""
        return "\(entry.text)\t\(entry.code)\t\(weight)\t\(note)"
    }
}

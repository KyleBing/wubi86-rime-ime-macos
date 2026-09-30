import Foundation

extension UserDictWriter {
    /// 可写用户词库路径（与 Rime user_data_dir 一致）
    static var activeURL: URL {
        let userDir = RimeResourceDeployer.resolveUserDataURL()
        let url = userDir.appendingPathComponent("wubi86_jidian_user.dict.yaml")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? saveDocument(.empty, to: url)
        }
        return url
    }

    static func loadActiveDocument() -> UserDictDocument {
        loadDocument(from: activeURL)
    }

    static func loadActiveEntries() -> [UserDictEntry] {
        loadActiveDocument().allEntries
    }

    static func saveActiveDocument(_ document: UserDictDocument) throws {
        try saveDocument(document, to: activeURL)
        // 自动同步自己写回时不要再排一次。
        UserDictAutoSync.noteLocalEdit()
    }

    /// 键盘造词：写入首个分组；无分组时建未命名组（对齐「全部」下添加）
    static func addEntry(_ entry: UserDictEntry) throws {
        var doc = loadActiveDocument()
        if doc.groups.isEmpty {
            doc.groups = [UserDictGroup(name: "", entries: [])]
        }
        try addEntry(entry, toGroupId: doc.groups[0].id, document: &doc, boostWeight: true)
        try saveActiveDocument(doc)
    }

    static func addEntry(_ entry: UserDictEntry, toGroupId groupId: UUID) throws {
        var doc = loadActiveDocument()
        try addEntry(entry, toGroupId: groupId, document: &doc, boostWeight: true)
        try saveActiveDocument(doc)
    }

    /// 按分组下标添加（详情页用，避免 UUID 重载后失效）
    static func addEntry(_ entry: UserDictEntry, toGroupIndex index: Int, boostWeight: Bool = true) throws {
        var doc = loadActiveDocument()
        guard doc.groups.indices.contains(index) else {
            throw NSError(domain: "UserDictWriter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "找不到目标分组"
            ])
        }
        try addEntry(entry, toGroupId: doc.groups[index].id, document: &doc, boostWeight: boostWeight)
        try saveActiveDocument(doc)
    }

    /// 「全部」选中时添加：新建「- 未命名 -」组并插到最前（对齐 addNewWord groupIndex=-1）
    static func addEntryInNewUnnamedGroup(_ entry: UserDictEntry) throws -> UUID {
        var doc = loadActiveDocument()
        var stored = entry
        stored.weight = boostedWeight(stored.weight)
        // 全库去重
        doc.removeEntries { $0.code == stored.code && $0.text == stored.text }
        let group = UserDictGroup(name: "- 未命名 -", entries: [stored])
        doc.groups.insert(group, at: 0)
        try saveActiveDocument(doc)
        return group.id
    }

    private static func addEntry(
        _ entry: UserDictEntry,
        toGroupId groupId: UUID,
        document: inout UserDictDocument,
        boostWeight: Bool
    ) throws {
        guard let idx = document.groups.firstIndex(where: { $0.id == groupId }) else {
            throw NSError(domain: "UserDictWriter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "找不到目标分组"
            ])
        }
        document.removeEntries { $0.code == entry.code && $0.text == entry.text }
        var stored = entry
        // 造词把权重抬高，保证能排到前面；词库管理可以保持空权重
        if boostWeight {
            stored.weight = boostedWeight(stored.weight)
        }
        // 组内按编码序插入（对齐 addWordToDictInOrderWithGroup）
        let list = document.groups[idx].entries
        var insertAt = list.count
        for i in 0..<max(0, list.count - 1) {
            if stored.code >= list[i].code && stored.code <= list[i + 1].code {
                insertAt = i + 1
                break
            }
        }
        if list.isEmpty {
            insertAt = 0
        } else if stored.code < list[0].code {
            insertAt = 0
        } else if stored.code > list[list.count - 1].code {
            insertAt = list.count
        }
        document.groups[idx].entries.insert(stored, at: insertAt)
    }

    // 未写权重或低于造词门槛时，用 100000
    private static func boostedWeight(_ weight: Int?) -> Int {
        let value = weight ?? 0
        return value < 100_000 ? 100_000 : value
    }

    static func removeEntry(_ entry: UserDictEntry) throws {
        var doc = loadActiveDocument()
        // 保留空分组
        doc.removeEntries { $0.code == entry.code && $0.text == entry.text }
        try saveActiveDocument(doc)
    }

    static func removeEntry(_ entry: UserDictEntry, fromGroupId groupId: UUID) throws {
        var doc = loadActiveDocument()
        guard let idx = doc.groups.firstIndex(where: { $0.id == groupId }) else { return }
        doc.groups[idx].entries.removeAll { $0.code == entry.code && $0.text == entry.text }
        try saveActiveDocument(doc)
    }

    static func removeEntry(_ entry: UserDictEntry, fromGroupIndex index: Int) throws {
        var doc = loadActiveDocument()
        guard doc.groups.indices.contains(index) else { return }
        doc.groups[index].entries.removeAll { $0.code == entry.code && $0.text == entry.text }
        try saveActiveDocument(doc)
    }

    static func moveEntries(_ entries: [UserDictEntry], toGroupId targetId: UUID) throws {
        var doc = loadActiveDocument()
        doc.moveEntries(entries, toGroupId: targetId)
        try saveActiveDocument(doc)
    }

    static func moveEntries(_ entries: [UserDictEntry], toGroupIndex targetIndex: Int) throws {
        var doc = loadActiveDocument()
        guard doc.groups.indices.contains(targetIndex) else { return }
        doc.moveEntries(entries, toGroupId: doc.groups[targetIndex].id)
        try saveActiveDocument(doc)
    }

    static func exportText() -> String {
        (try? String(contentsOf: activeURL, encoding: .utf8)) ?? ""
    }

    static func importText(_ text: String) throws {
        let doc = parseDocument(text)
        try saveActiveDocument(doc.groups.isEmpty ? .empty : doc)
    }
}

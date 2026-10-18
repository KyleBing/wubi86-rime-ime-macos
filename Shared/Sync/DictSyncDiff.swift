import Foundation

/// 对比本地与线上用户词库。同一条看分组 + 词 + 编码，权重和备注用来判断是否一致。
enum DictSyncDiff {
    struct WordItem: Equatable {
        let key: String
        let word: String
        let code: String
        let priority: String
        let note: String
        let groupName: String

        // 词和编码，用来在差异列表里认这一条。
        var brief: String { "\(word)  \(code)" }

        // 权重、备注、分组里有内容的才写出来。
        var detail: String {
            var parts: [String] = []
            if !priority.isEmpty { parts.append("权重 \(priority)") }
            if !note.isEmpty { parts.append("备注 \(note)") }
            if !groupName.isEmpty { parts.append(groupName) }
            return parts.isEmpty ? "无权重、备注" : parts.joined(separator: "  ")
        }
    }

    struct ChangedPair: Equatable {
        let local: WordItem
        let remote: WordItem
    }

    struct Result: Equatable {
        let localCount: Int
        let remoteCount: Int
        let onlyLocal: [WordItem]
        let onlyRemote: [WordItem]
        let changed: [ChangedPair]
        let sameCount: Int
        let hasRemote: Bool

        var isIdentical: Bool {
            hasRemote && onlyLocal.isEmpty && onlyRemote.isEmpty && changed.isEmpty
        }

        var summary: String {
            if !hasRemote {
                return "云端尚无该文件备份。本地 \(localCount) 条，可上传覆盖。"
            }
            if isIdentical {
                return "本地与云端完全一致（\(localCount) 条）。"
            }
            return "本地 \(localCount) 条，云端 \(remoteCount) 条。仅本地 \(onlyLocal.count)，仅云端 \(onlyRemote.count)，内容不同 \(changed.count)。"
        }

        // 弹窗列表只写逐条差异。摘要已经显示在标题下，这里不再重复。
        func detailReport(maxPerSection: Int = 800) -> String {
            if !hasRemote || isIdentical { return "" }
            var lines: [String] = []
            appendSection("仅本地（\(onlyLocal.count)）", items: onlyLocal, into: &lines, limit: maxPerSection)
            appendSection("仅云端（\(onlyRemote.count)）", items: onlyRemote, into: &lines, limit: maxPerSection)
            if !changed.isEmpty {
                lines.append("内容不同（\(changed.count)）")
                let shown = changed.prefix(maxPerSection)
                for pair in shown {
                    lines.append("  " + pair.local.brief)
                    lines.append("    本地  " + pair.local.detail)
                    lines.append("    云端  " + pair.remote.detail)
                }
                let rest = changed.count - shown.count
                if rest > 0 {
                    lines.append("  …还有 \(rest) 条")
                }
                lines.append("")
            }
            return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        }

        private func appendSection(_ title: String, items: [WordItem], into lines: inout [String], limit: Int) {
            guard !items.isEmpty else { return }
            lines.append(title)
            let shown = items.prefix(limit)
            for item in shown {
                lines.append("  " + item.brief + "  " + item.detail)
            }
            let rest = items.count - shown.count
            if rest > 0 {
                lines.append("  …还有 \(rest) 条")
            }
            lines.append("")
        }
    }

    static func flatten(_ document: UserDictDocument) -> [WordItem] {
        var list: [WordItem] = []
        for group in document.groups {
            for entry in group.entries {
                list.append(WordItem(
                    key: identityKey(group: group.name, text: entry.text, code: entry.code),
                    word: entry.text,
                    code: entry.code,
                    priority: entry.weight.map(String.init) ?? "",
                    note: entry.note,
                    groupName: group.name
                ))
            }
        }
        return list
    }

    static func compare(local: UserDictDocument, remote: UserDictDocument?) -> Result {
        let localWords = flatten(local)
        let remoteWords = remote.map(flatten) ?? []

        var localMap: [String: WordItem] = [:]
        for item in localWords { localMap[item.key] = item }
        var remoteMap: [String: WordItem] = [:]
        for item in remoteWords { remoteMap[item.key] = item }

        var onlyLocal: [WordItem] = []
        var onlyRemote: [WordItem] = []
        var changed: [ChangedPair] = []
        var sameCount = 0

        for (key, localItem) in localMap {
            guard let remoteItem = remoteMap[key] else {
                onlyLocal.append(localItem)
                continue
            }
            if localItem.priority == remoteItem.priority && localItem.note == remoteItem.note {
                sameCount += 1
            } else {
                changed.append(ChangedPair(local: localItem, remote: remoteItem))
            }
        }
        for (key, remoteItem) in remoteMap where localMap[key] == nil {
            onlyRemote.append(remoteItem)
        }

        onlyLocal.sort { $0.key < $1.key }
        onlyRemote.sort { $0.key < $1.key }
        changed.sort { $0.local.key < $1.local.key }

        return Result(
            localCount: localWords.count,
            remoteCount: remoteWords.count,
            onlyLocal: onlyLocal,
            onlyRemote: onlyRemote,
            changed: changed,
            sameCount: sameCount,
            hasRemote: remote != nil
        )
    }

    // 把云端没有的词条并入本地。编码和词相同就是同一条，权重不同也不另加一份。
    static func mergeRemoteIntoLocal(_ local: UserDictDocument, remote: UserDictDocument) -> (document: UserDictDocument, added: Int) {
        var result = local
        var added = 0

        if result.isGroupMode || remote.isGroupMode || result.shouldPreserveGroupHeaders {
            var groupIndexByName: [String: Int] = [:]
            for (i, g) in result.groups.enumerated() {
                groupIndexByName[g.name] = i
            }
            for remoteGroup in remote.groups {
                if let idx = groupIndexByName[remoteGroup.name] {
                    var existingKeys = Set(result.groups[idx].entries.map {
                        identityKey(group: result.groups[idx].name, text: $0.text, code: $0.code)
                    })
                    for entry in remoteGroup.entries {
                        let key = identityKey(group: remoteGroup.name, text: entry.text, code: entry.code)
                        guard !existingKeys.contains(key) else { continue }
                        result.groups[idx].entries.append(entry)
                        existingKeys.insert(key)
                        added += 1
                    }
                } else {
                    result.groups.append(remoteGroup)
                    groupIndexByName[remoteGroup.name] = result.groups.count - 1
                    added += remoteGroup.entries.count
                }
            }
            if !result.isGroupMode && result.shouldPreserveGroupHeaders {
                result.isGroupMode = true
            }
        } else {
            var existingKeys = Set(result.allEntries.map {
                identityKey(group: "", text: $0.text, code: $0.code)
            })
            if result.groups.isEmpty {
                result.groups = [UserDictGroup(name: "", entries: [])]
            }
            for entry in remote.allEntries {
                let key = identityKey(group: "", text: entry.text, code: entry.code)
                guard !existingKeys.contains(key) else { continue }
                result.groups[0].entries.append(entry)
                existingKeys.insert(key)
                added += 1
            }
        }
        return (result, added)
    }

    /// 对照上次同步快照做三方合并。返回的 nextBase 只推进双方已经一致的词条。
    struct ThreeWayMerge: Equatable {
        var merged: UserDictDocument
        var nextBase: UserDictDocument
        var conflicts: [WordItem]
        var tookRemote: Int
        var dropped: Int
        var needsUpload: Bool
        var localChanged: Bool
    }

    static func threeWayMerge(base: UserDictDocument?, local: UserDictDocument, remote: UserDictDocument) -> ThreeWayMerge {
        let baseMap = base.map(indexMap) ?? [:]
        let localMap = indexMap(local)
        let remoteMap = indexMap(remote)
        let keys = Set(baseMap.keys).union(localMap.keys).union(remoteMap.keys)

        var chosen: [String: WordItem] = [:]
        var conflictKeys = Set<String>()
        var conflicts: [WordItem] = []
        var tookRemote = 0
        var dropped = 0

        for key in keys.sorted() {
            let decision = pick(base: baseMap[key], local: localMap[key], remote: remoteMap[key])
            switch decision {
            case .use(let item):
                chosen[key] = item
                if let remoteItem = remoteMap[key], sameContent(item, remoteItem) {
                    if let localItem = localMap[key] {
                        if !sameContent(localItem, remoteItem) { tookRemote += 1 }
                    } else {
                        tookRemote += 1
                    }
                }
            case .drop:
                if localMap[key] != nil { dropped += 1 }
            case .conflict(let item):
                conflicts.append(item)
                conflictKeys.insert(key)
                // 冲突时文件里先留本地版本，避免未上传就把云端改掉。
                if let localItem = localMap[key] {
                    chosen[key] = localItem
                }
            }
        }

        let merged = document(from: chosen, template: local)
        let mergedMap = indexMap(merged)
        var baseNext: [String: WordItem] = [:]
        if conflictKeys.isEmpty {
            baseNext = mergedMap
        } else {
            for (key, item) in remoteMap {
                if conflictKeys.contains(key) {
                    if let old = baseMap[key] { baseNext[key] = old }
                    continue
                }
                if let kept = chosen[key], sameContent(kept, item) {
                    baseNext[key] = item
                }
            }
            for key in conflictKeys {
                if let old = baseMap[key] { baseNext[key] = old }
            }
        }

        return ThreeWayMerge(
            merged: merged,
            nextBase: document(from: baseNext, template: local),
            conflicts: conflicts,
            tookRemote: tookRemote,
            dropped: dropped,
            needsUpload: conflictKeys.isEmpty && !mapsEqual(mergedMap, remoteMap),
            localChanged: !mapsEqual(mergedMap, localMap)
        )
    }

    private enum Pick {
        case use(WordItem)
        case drop
        case conflict(WordItem)
    }

    // 有快照时：只一边改过就采用那边；两边都改且内容不同则冲突。没有快照时，单边出现视为新增。
    private static func pick(base: WordItem?, local: WordItem?, remote: WordItem?) -> Pick {
        switch (base, local, remote) {
        case let (_, local?, remote?) where sameContent(local, remote):
            return .use(local)
        case (nil, let local?, .some(_)):
            return .conflict(local)
        case let (base?, local?, remote?):
            let localChanged = !sameContent(local, base)
            let remoteChanged = !sameContent(remote, base)
            if localChanged && remoteChanged { return .conflict(local) }
            if remoteChanged { return .use(remote) }
            return .use(local)
        case let (base?, local?, nil):
            if sameContent(local, base) { return .drop }
            return .conflict(local)
        case let (base?, nil, remote?):
            if sameContent(remote, base) { return .drop }
            return .conflict(remote)
        case (_, let local?, nil):
            return .use(local)
        case (_, nil, let remote?):
            return .use(remote)
        default:
            return .drop
        }
    }

    // 同一条是分组里的编码 + 词。权重不参与认词，只在 sameContent 里比较是否一致。
    private static func identityKey(group: String, text: String, code: String) -> String {
        "\(group)\t\(text)\t\(code)"
    }

    private static func indexMap(_ document: UserDictDocument) -> [String: WordItem] {
        var map: [String: WordItem] = [:]
        for item in flatten(document) {
            map[item.key] = item
        }
        return map
    }

    private static func sameContent(_ lhs: WordItem, _ rhs: WordItem) -> Bool {
        lhs.priority == rhs.priority && lhs.note == rhs.note && lhs.groupName == rhs.groupName
    }

    private static func mapsEqual(_ lhs: [String: WordItem], _ rhs: [String: WordItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, item) in lhs {
            guard let other = rhs[key], sameContent(item, other) else { return false }
        }
        return true
    }

    // 按本地分组顺序放回词条；分组变了或是云端新词则追加到对应组。
    private static func document(from chosen: [String: WordItem], template: UserDictDocument) -> UserDictDocument {
        var result = template
        var used = Set<String>()
        for index in result.groups.indices {
            var kept: [UserDictEntry] = []
            for entry in result.groups[index].entries {
                let key = identityKey(
                    group: result.groups[index].name,
                    text: entry.text,
                    code: entry.code
                )
                guard let item = chosen[key] else { continue }
                var updated = entry
                updated.weight = Int(item.priority)
                updated.note = item.note
                kept.append(updated)
                used.insert(key)
            }
            result.groups[index].entries = kept
        }
        let extras = chosen.keys.filter { !used.contains($0) }.sorted()
        for key in extras {
            guard let item = chosen[key] else { continue }
            let entry = UserDictEntry(
                code: item.code,
                text: item.word,
                weight: Int(item.priority),
                note: item.note
            )
            if let index = result.groups.firstIndex(where: { $0.name == item.groupName }) {
                result.groups[index].entries.append(entry)
            } else {
                result.groups.append(UserDictGroup(name: item.groupName, entries: [entry]))
                if !item.groupName.isEmpty {
                    result.isGroupMode = true
                }
            }
        }
        return result
    }
}

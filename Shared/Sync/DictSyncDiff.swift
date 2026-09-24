import Foundation

/// 对比本地与线上用户词库。唯一键是词 + 编码，权重或备注不同算内容变更。
enum DictSyncDiff {
    struct WordItem: Equatable {
        let key: String
        let word: String
        let code: String
        let priority: String
        let note: String
        let groupName: String
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
    }

    static func flatten(_ document: UserDictDocument) -> [WordItem] {
        var list: [WordItem] = []
        for group in document.groups {
            for entry in group.entries {
                list.append(WordItem(
                    key: "\(entry.text)\t\(entry.code)",
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

    // 把云端独有词条并入本地，同词同码但权重不同时再追加一份
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
                    var existingKeys = Set(result.groups[idx].entries.map { "\($0.text)\t\($0.code)" })
                    for entry in remoteGroup.entries {
                        let key = "\(entry.text)\t\(entry.code)"
                        if existingKeys.contains(key) {
                            if let localEntry = result.groups[idx].entries.first(where: { $0.text == entry.text && $0.code == entry.code }),
                               localEntry.weight != entry.weight {
                                result.groups[idx].entries.append(entry)
                                added += 1
                            }
                        } else {
                            result.groups[idx].entries.append(entry)
                            existingKeys.insert(key)
                            added += 1
                        }
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
            var existingKeys = Set(result.allEntries.map { "\($0.text)\t\($0.code)" })
            if result.groups.isEmpty {
                result.groups = [UserDictGroup(name: "", entries: [])]
            }
            for entry in remote.allEntries {
                let key = "\(entry.text)\t\(entry.code)"
                if existingKeys.contains(key) {
                    if let localEntry = result.allEntries.first(where: { $0.text == entry.text && $0.code == entry.code }),
                       localEntry.weight != entry.weight {
                        result.groups[0].entries.append(entry)
                        added += 1
                    }
                } else {
                    result.groups[0].entries.append(entry)
                    existingKeys.insert(key)
                    added += 1
                }
            }
        }
        return (result, added)
    }
}

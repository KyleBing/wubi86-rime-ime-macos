import Foundation

/// 用户词条模型（M5 造词使用）
struct UserDictEntry: Codable, Equatable, Identifiable {
    var id: String { "\(code)|\(text)" }
    var code: String
    var text: String
    /// 空表示码表里没有权重列
    var weight: Int?
    /// 码表第四列，对应码表助手的备注
    var note: String

    init(code: String, text: String, weight: Int? = nil, note: String = "") {
        self.code = code
        self.text = text
        self.weight = weight
        self.note = note
    }
}

/// 用户词库分组（对齐码表助手 WordGroup / ## 分组）
struct UserDictGroup: Identifiable, Equatable {
    var id: UUID
    var name: String
    var entries: [UserDictEntry]

    init(id: UUID = UUID(), name: String, entries: [UserDictEntry] = []) {
        self.id = id
        self.name = name
        self.entries = entries
    }

    /// 展示名：空名显示为「- 未命名 -」（与码表助手一致）
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "- 未命名 -" : trimmed
    }

    var isEmpty: Bool { entries.isEmpty }
}

/// 带分组的完整用户词库
struct UserDictDocument: Equatable {
    /// 是否分组模式（dict_grouped）
    var isGroupMode: Bool
    var groups: [UserDictGroup]

    var allEntries: [UserDictEntry] {
        groups.flatMap(\.entries)
    }

    var entryCount: Int { allEntries.count }

    /// 落盘时是否必须保留 ## 分组行
    var shouldPreserveGroupHeaders: Bool {
        if isGroupMode { return true }
        if groups.count > 1 { return true }
        return groups.contains {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static var empty: UserDictDocument {
        // 默认分组模式，便于管理
        UserDictDocument(isGroupMode: true, groups: [UserDictGroup(name: "")])
    }

    static func flat(entries: [UserDictEntry]) -> UserDictDocument {
        UserDictDocument(isGroupMode: false, groups: [UserDictGroup(name: "", entries: entries)])
    }

    mutating func moveGroup(id: UUID, direction: GroupMoveDirection) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        switch direction {
        case .up:
            guard i > 0 else { return }
            groups.swapAt(i, i - 1)
        case .down:
            guard i < groups.count - 1 else { return }
            groups.swapAt(i, i + 1)
        }
    }

    /// 长按拖动排序（List.onMove / DropDelegate）
    mutating func moveGroups(from source: IndexSet, to destination: Int) {
        // 不用 SwiftUI 的 MutableCollection.move，避免键盘扩展链接失败
        var reordered = groups
        let moving = source.sorted().map { reordered[$0] }
        for index in source.sorted(by: >) {
            reordered.remove(at: index)
        }
        let dest = min(max(0, destination), reordered.count)
        reordered.insert(contentsOf: moving, at: dest)
        groups = reordered
    }

    /// 在指定下标前插入空分组（对齐 addGroupBeforeId）
    @discardableResult
    mutating func insertEmptyGroup(before index: Int) -> UserDictGroup {
        let group = UserDictGroup(name: "")
        let i = max(0, min(index, groups.count))
        groups.insert(group, at: i)
        return group
    }

    mutating func deleteGroup(id: UUID) {
        groups.removeAll { $0.id == id }
    }

    /// 删除词条但保留空分组（对齐码表助手 deleteWords）
    mutating func removeEntries(matching predicate: (UserDictEntry) -> Bool) {
        for i in groups.indices {
            groups[i].entries.removeAll(where: predicate)
        }
    }

    /// 将词条移到目标分组末尾（同文件内移动，对齐码表助手）
    mutating func moveEntries(_ entries: [UserDictEntry], toGroupId targetId: UUID) {
        guard groups.contains(where: { $0.id == targetId }) else { return }
        let ids = Set(entries.map(\.id))
        removeEntries { ids.contains($0.id) }
        guard let dest = groups.firstIndex(where: { $0.id == targetId }) else { return }
        for entry in entries {
            groups[dest].entries.removeAll { $0.code == entry.code && $0.text == entry.text }
            groups[dest].entries.append(entry)
        }
    }
}

enum GroupMoveDirection {
    case up, down
}

/// 分组筛选：全部 / 某一组（对齐 activeGroupId，-1 = 全部）
enum UserDictGroupFilter: Equatable, Hashable {
    case all
    case group(UUID)
}

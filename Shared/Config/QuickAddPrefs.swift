import AppKit

/// 全局造词快捷键与用户词当前分组。App / 偏好面板 / 输入法分进程，落在 Application Support。
enum QuickAddPrefs {
    static let changedNotification = Notification.Name("cn.kylebing.inputmethod.meifengwubi.quickAddHotkeyChanged")

    // Carbon：kVK_ANSI_N = 45，controlKey | optionKey = 6144
    static let defaultKeyCode: UInt32 = 45
    static let defaultModifiers: UInt32 = 6144
    // 上一版默认是 ⌃⌥W，已保存的默认值迁到 ⌃⌥N
    private static let legacyKeyCode: UInt32 = 13

    private static let fileName = "quickadd.json"
    private static let lock = NSLock()

    private struct Store: Codable {
        var keyCode: UInt32 = QuickAddPrefs.defaultKeyCode
        var modifiers: UInt32 = QuickAddPrefs.defaultModifiers
        var display: String = "⌃⌥N"
        var selectedGroupIndex: Int = 0
    }

    static var keyCode: UInt32 {
        get { load().keyCode }
        set { update { $0.keyCode = newValue } }
    }

    static var modifiers: UInt32 {
        get { load().modifiers }
        set { update { $0.modifiers = newValue } }
    }

    static var display: String {
        get { load().display }
        set { update { $0.display = newValue } }
    }

    static var selectedGroupIndex: Int {
        get { load().selectedGroupIndex }
        set { update { $0.selectedGroupIndex = max(0, newValue) } }
    }

    // 至少带一个修饰键，避免把单字母注册成全局热键
    static func saveShortcut(keyCode: UInt32, modifiers: UInt32, display: String) {
        guard modifiers != 0 else { return }
        update {
            $0.keyCode = keyCode
            $0.modifiers = modifiers
            $0.display = display
        }
        DistributedNotificationCenter.default().post(name: changedNotification, object: nil)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= 256 }
        if flags.contains(.shift) { value |= 512 }
        if flags.contains(.option) { value |= 2048 }
        if flags.contains(.control) { value |= 4096 }
        return value
    }

    static func displayString(for event: NSEvent) -> String {
        var prefix = ""
        let flags = event.modifierFlags
        if flags.contains(.control) { prefix += "⌃" }
        if flags.contains(.option) { prefix += "⌥" }
        if flags.contains(.shift) { prefix += "⇧" }
        if flags.contains(.command) { prefix += "⌘" }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        return prefix + key
    }

    private static func update(_ body: (inout Store) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var store = readUnlocked()
        body(&store)
        writeUnlocked(store)
    }

    private static func load() -> Store {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked()
    }

    private static func readUnlocked() -> Store {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              var store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store()
        }
        // 只改仍停在旧默认键上的配置，用户自己设过的组合不动。
        if store.keyCode == legacyKeyCode,
           store.modifiers == defaultModifiers,
           store.display == "⌃⌥W" || store.display == "⌃⌥w" {
            store.keyCode = defaultKeyCode
            store.display = "⌃⌥N"
            writeUnlocked(store)
        }
        return store
    }

    private static func writeUnlocked(_ store: Store) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static var fileURL: URL? {
        AppGroupPaths.containerURL?.appendingPathComponent(fileName)
    }
}

/// 候选排序快捷键，默认与造词同一组修饰键加 0（⌃⌥0），可在设置里单独修改
enum RankShortcutPrefs {
    static let changedNotification = Notification.Name("cn.kylebing.inputmethod.meifengwubi.rankHotkeyChanged")

    // Carbon：kVK_ANSI_0 = 29，controlKey | optionKey = 6144
    static let defaultKeyCode: UInt32 = 29
    static let defaultModifiers: UInt32 = 6144

    private static let fileName = "rankshortcut.json"
    private static let lock = NSLock()

    private struct Store: Codable {
        var keyCode: UInt32 = RankShortcutPrefs.defaultKeyCode
        var modifiers: UInt32 = RankShortcutPrefs.defaultModifiers
        var display: String = "⌃⌥0"
    }

    static var keyCode: UInt32 { load().keyCode }

    static var modifiers: UInt32 { load().modifiers }

    static var display: String { load().display }

    // 至少带一个修饰键，避免把单个数字键吃掉
    static func saveShortcut(keyCode: UInt32, modifiers: UInt32, display: String) {
        guard modifiers != 0 else { return }
        update {
            $0.keyCode = keyCode
            $0.modifiers = modifiers
            $0.display = display
        }
        DistributedNotificationCenter.default().post(name: changedNotification, object: nil)
    }

    // 数字键盘的 0 与小键盘上的同一颗键都认
    static func matches(keyCode eventKeyCode: UInt16, carbonModifiers carbon: UInt32) -> Bool {
        let store = load()
        guard store.modifiers != 0, carbon == store.modifiers else { return false }
        let code = UInt32(eventKeyCode)
        if code == store.keyCode { return true }
        // kVK_ANSI_0 = 29，kVK_ANSI_Keypad0 = 82
        return store.keyCode == 29 && code == 82
    }

    private static func update(_ body: (inout Store) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var store = readUnlocked()
        body(&store)
        writeUnlocked(store)
    }

    private static func load() -> Store {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked()
    }

    private static func readUnlocked() -> Store {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store()
        }
        return store
    }

    private static func writeUnlocked(_ store: Store) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static var fileURL: URL? {
        AppGroupPaths.containerURL?.appendingPathComponent(fileName)
    }
}

import AppKit
import Carbon
import InputMethodKit
import os.log

private let log = Logger(subsystem: "cn.kylebing.inputmethod.meifengwubi", category: "IME")

/// 显式入口：部分系统上 @main AppDelegate 不会进 didFinishLaunching，导致 IMKServer 未创建、打不出字
@main
enum MeifengIMEMain {
    static func main() {
        let app = NSApplication.shared
        // 不要在这里改 activationPolicy。LSUIElement 已经没有 Dock；
        // 启动时再设 accessory，部分应用（含 Electron）不会把按键交给输入法，菜单项也不出现。
        let delegate = IMEAppDelegate()
        app.delegate = delegate
        // IMK 要求尽早建立连接名，不要等 run loop 空转
        delegate.startServer()
        _ = RimeSession.shared.ensureStarted(forceFullCheck: false)
        IMEAppDelegate.installEditingMenu()
        QuickAddHotKey.install()
        // 各软件会记住自己的输入法；选中玫枫后再点别的输入框，要跟着过去
        MeifengInputSourceLock.install()
        IMEAppDelegate.appendLaunchLog("main entered, server+rime ready")
        app.run()
    }
}

final class IMEAppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func startServer() {
        let conn = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
            ?? "MeifengWubi_1_Connection"
        let bundleId = Bundle.main.bundleIdentifier ?? "cn.kylebing.inputmethod.meifengwubi"
        server = IMKServer(name: conn, bundleIdentifier: bundleId)
        log.info("IMKServer ready conn=\(conn, privacy: .public)")
        Self.appendLaunchLog("IMKServer ready conn=\(conn)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 双保险：若 main 已建好则跳过
        if server == nil {
            startServer()
            _ = RimeSession.shared.ensureStarted(forceFullCheck: false)
        }
        // 设置页改了 page_size / 翻页键后立即 redeploy
        DistributedNotificationCenter.default().addObserver(
            forName: RimeBehaviorPrefs.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            _ = RimeSession.shared.ensureStarted(forceFullCheck: false)
        }
        Self.appendLaunchLog("applicationDidFinishLaunching")
    }

    func applicationWillTerminate(_ notification: Notification) {
        RimeSession.shared.shutdown()
    }

    // 输入法是后台进程，没有系统编辑菜单时，文本框收不到全选、复制、粘贴。
    static func installEditingMenu() {
        let main = NSApp.mainMenu ?? NSMenu()
        let hasSelectAll = main.items.contains { item in
            item.submenu?.items.contains { $0.action == #selector(NSText.selectAll(_:)) } == true
        }
        if hasSelectAll {
            NSApp.mainMenu = main
            return
        }
        if main.items.isEmpty {
            let appItem = NSMenuItem()
            appItem.submenu = NSMenu()
            main.addItem(appItem)
        }
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = NSEvent.ModifierFlags([.command, .shift])
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    static func appendLaunchLog(_ msg: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
        let urls = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/MeifengWubi-ime.log"),
            URL(fileURLWithPath: "/tmp/MeifengWubi-ime.log")
        ]
        guard let data = line.data(using: .utf8) else { return }
        for url in urls {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
        NSLog("[MeifengWubi] %@", msg)
    }
}

/// 用户选中玫枫五笔后，切换到其他软件的输入框时保持选中。
enum MeifengInputSourceLock {
    private static let modeId = "cn.kylebing.inputmethod.meifengwubi.wubi"
    // 离开当前软件时若仍是玫枫，下个软件也选回玫枫
    private static var restoreOnNextApp = false
    // 切软件时系统会先改回那个软件的旧输入法，这段时间内忽略，避免把「跟着走」清掉
    private static var ignoreSourceChangeUntil = Date.distantPast
    private static var applying = false

    static func install() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            guard !applying else { return }
            restoreOnNextApp = isSelected()
            if restoreOnNextApp {
                ignoreSourceChangeUntil = Date().addingTimeInterval(0.6)
            }
        }
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard restoreOnNextApp else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return }
            applying = true
            select()
            applying = false
            IMEAppDelegate.appendLaunchLog("kept input source for \(app?.bundleIdentifier ?? "?")")
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            if applying || Date() < ignoreSourceChangeUntil { return }
            // 用户在当前软件里手动换了输入法，就不再自动跟过去
            restoreOnNextApp = isSelected()
        }
        restoreOnNextApp = isSelected()
    }

    private static func isSelected() -> Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return inputSourceID(source) == modeId
    }

    private static func select() {
        guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else { return }
        guard let mode = list.first(where: { inputSourceID($0) == modeId }) else { return }
        _ = TISSelectInputSource(mode)
    }

    private static func inputSourceID(_ source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

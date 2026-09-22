import AppKit

/// IMK showPreferences: 使用的窗口控制器（Info.plist InputMethodServerPreferencesWindowControllerClass）
@objc(MeifengPreferencesWindowController)
final class MeifengPreferencesWindowController: NSWindowController {
    @objc override init(window: NSWindow?) {
        super.init(window: window)
    }

    @objc convenience init() {
        let form = IMESettingsControls.makeFormView(width: 480)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: form.bounds.width, height: max(form.bounds.height, 320)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "玫枫五笔设置"
        win.contentView = form
        win.center()
        win.isReleasedWhenClosed = false
        self.init(window: win)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        // 每次打开刷新控件状态
        if let win = window {
            let form = IMESettingsControls.makeFormView(width: 480)
            win.contentView = form
            win.setContentSize(form.bounds.size)
        }
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }
}

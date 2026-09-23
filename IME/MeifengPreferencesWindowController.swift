import AppKit

/// IMK showPreferences: 使用的窗口控制器（Info.plist InputMethodServerPreferencesWindowControllerClass）
@objc(MeifengPreferencesWindowController)
final class MeifengPreferencesWindowController: NSWindowController, NSWindowDelegate {
    @objc override init(window: NSWindow?) {
        // IMK 常走 alloc/init → init(window: nil)，必须在这里建好窗口
        if let window {
            super.init(window: window)
        } else {
            let win = Self.makeWindow()
            super.init(window: win)
        }
        self.window?.delegate = self
    }

    @objc convenience init() {
        self.init(window: Self.makeWindow())
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeWindow() -> NSWindow {
        // IME 进程注入词库部署 / 目录切换；换目录后重启自身以便读新路径。
        IMESettingsControls.lexiconActions = IMESettingsControls.LexiconActions(
            deploy: {
                switch RimeConfigDeploy.deployNow() {
                case .success: return (true, "部署成功")
                case .failure(let err): return (false, err)
                }
            },
            reset: {
                switch RimeConfigDeploy.resetToFactory() {
                case .success: return (true, "已复位并部署")
                case .failure(let err): return (false, err)
                }
            },
            changeDataDirectory: { url in
                switch RimeConfigDeploy.changeUserDataDirectory(to: url) {
                case .success:
                    let message = url == nil ? "已恢复默认词库目录并部署" : "已切换词库目录并部署"
                    return (true, message)
                case .failure(let err):
                    return (false, err)
                }
            },
            restartIME: {
                let kill = Process()
                kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                kill.arguments = ["MeifengWubiIME"]
                try? kill.run()
                kill.waitUntilExit()
            }
        )
        let size = IMESettingsControls.preferredWindowSize
        let form = IMESettingsControls.makeFormView(size: size)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "玫枫五笔设置"
        win.titleVisibility = .visible
        win.titlebarAppearsTransparent = false
        // accessory 进程里有时标题字不显，用标准控件强化
        win.toolbar = nil
        win.contentView = form
        win.minSize = IMESettingsControls.minWindowSize
        win.setContentSize(size)
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        return win
    }

    override func showWindow(_ sender: Any?) {
        if window == nil {
            window = Self.makeWindow()
            window?.delegate = self
        }
        if let win = window {
            let size = win.contentLayoutRect.size
            let use = NSSize(
                width: max(size.width, IMESettingsControls.minWindowSize.width),
                height: max(size.height, IMESettingsControls.minWindowSize.height)
            )
            win.contentView = IMESettingsControls.makeFormView(size: use)
            win.setContentSize(use)
        }
        if NSApp.activationPolicy() == .prohibited {
            NSApp.setActivationPolicy(.accessory)
        }
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
    }
}

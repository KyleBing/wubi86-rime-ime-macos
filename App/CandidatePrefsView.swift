import AppKit
import SwiftUI

/// 主 App 直接承载共享 AppKit 设置页，保证与输入法入口完全一致。
struct CandidatePrefsView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CandidateSettingsWindow.installLexiconActions()
        let view = IMESettingsControls.makeFormView()
        // 跟随 SwiftUI 弹窗尺寸缩放，避免固定 900 宽时左侧栏被裁出窗口。
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 独立设置窗口，不依附主界面，避免 sheet 被主窗口裁切。
enum CandidateSettingsWindow {
    private static var controller: NSWindowController?

    // App 侧注入词库部署 / 目录切换能力。
    static func installLexiconActions() {
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
                IMEInstaller.restartRunningIME()
            },
            restartQuitsSettings: false
        )
    }

    static func show() {
        installLexiconActions()
        if controller == nil {
            let size = IMESettingsControls.preferredWindowSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "玫枫五笔设置"
            window.contentView = IMESettingsControls.makeFormView(size: size)
            window.minSize = IMESettingsControls.minWindowSize
            window.setContentSize(size)
            window.center()
            controller = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }
}

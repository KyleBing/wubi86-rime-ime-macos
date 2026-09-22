import AppKit
import InputMethodKit
import os.log

private let log = Logger(subsystem: "cn.kylebing.inputmethod.meifengwubi", category: "IME")

/// 显式入口：部分系统上 @main AppDelegate 不会进 didFinishLaunching，导致 IMKServer 未创建、打不出字
@main
enum MeifengIMEMain {
    static func main() {
        let app = NSApplication.shared
        // accessory：无 Dock，但允许设置窗口置前（勿用 prohibited / LSBackgroundOnly）
        app.setActivationPolicy(.accessory)
        let delegate = IMEAppDelegate()
        app.delegate = delegate
        // IMK 要求尽早建立连接名，不要等 run loop 空转
        delegate.startServer()
        _ = RimeSession.shared.ensureStarted(forceFullCheck: false)
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

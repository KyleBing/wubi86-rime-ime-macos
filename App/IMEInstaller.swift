import AppKit
import Carbon
import Foundation

enum IMEInstaller {
    static var installedIMEURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/MeifengWubiIME.app")
    }

    static let bundleId = "cn.kylebing.inputmethod.meifengwubi"
    // 已改为无 Input Mode 的扁平输入法，仅保留 Bundle ID
    private static let hiToolbox = "com.apple.HIToolbox" as CFString

    static func statusText() -> String {
        let exists = FileManager.default.fileExists(atPath: installedIMEURL.path)
        let enabled = isEnabledInPrefs()
        if exists && enabled {
            return "已安装且已写入系统输入法列表（显示名：玫枫五笔 / Meifeng Wubi）"
        }
        if exists {
            return "已安装到 ~/Library/Input Methods/，但可能尚未出现在设置列表，请点「安装 / 更新」或注销一次"
        }
        return "尚未安装到 ~/Library/Input Methods/"
    }

    /// 拷贝 IME.app（可在后台线程）
    static func copyEmbeddedIME() throws {
        guard let embedded = Bundle.main.url(forResource: "MeifengWubiIME", withExtension: "app") else {
            throw NSError(domain: "IMEInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "宿主包内找不到 MeifengWubiIME.app，请先完整编译 MeifengWubi 目标"
            ])
        }
        let fm = FileManager.default
        let destDir = installedIMEURL.deletingLastPathComponent()
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["MeifengWubiIME"]
        try? task.run()
        task.waitUntilExit()

        if fm.fileExists(atPath: installedIMEURL.path) {
            try fm.removeItem(at: installedIMEURL)
        }
        try fm.copyItem(at: embedded, to: installedIMEURL)
    }

    /// 注册 / 启用 / 部署 / 拉起（必须主线程：TIS 会 assert）
    static func finishInstallOnMain() {
        precondition(Thread.isMainThread, "finishInstallOnMain 必须在主线程")
        registerInputSource(at: installedIMEURL)
        enableInSystemPreferences()
        _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
        switch RimeConfigDeploy.deployNow() {
        case .success:
            NSLog("[MeifengWubi] pre-deploy ok")
        case .failure(let err):
            NSLog("[MeifengWubi] pre-deploy failed: %@", err)
        }
        let killAgent = Process()
        killAgent.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killAgent.arguments = ["TextInputMenuAgent"]
        try? killAgent.run()
        killAgent.waitUntilExit()
        NSWorkspace.shared.open(installedIMEURL)
    }

    /// 一键安装（主线程）
    static func installEmbeddedIME() throws {
        precondition(Thread.isMainThread, "IMEInstaller.installEmbeddedIME 必须在主线程")
        try copyEmbeddedIME()
        finishInstallOnMain()
    }

    private static func registerInputSource(at url: URL) {
        precondition(Thread.isMainThread, "TIS 必须在主线程")
        let status = TISRegisterInputSource(url as CFURL)
        NSLog("[MeifengWubi] TISRegisterInputSource status=%d path=%@", status, url.path)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        // 只注册安装目录，不要 -R 递归扫到工程里的构建产物
        task.arguments = ["-f", "-trusted", url.path]
        try? task.run()
        task.waitUntilExit()

        // 按 InputSourceID 去重，只 Enable 一次，避免同名多项
        var enabledIds = Set<String>()
        if let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] {
            for src in list {
                guard let p = TISGetInputSourceProperty(src, kTISPropertyBundleID) else { continue }
                let bid = "\(Unmanaged<CFTypeRef>.fromOpaque(p).takeUnretainedValue())"
                guard bid == bundleId else { continue }
                let iid: String = {
                    guard let ip = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return bid }
                    return "\(Unmanaged<CFTypeRef>.fromOpaque(ip).takeUnretainedValue())"
                }()
                if enabledIds.contains(iid) { continue }
                _ = TISEnableInputSource(src)
                enabledIds.insert(iid)
            }
        }
    }

    /// 只追加一条 Keyboard Input Method，绝不 setPersistentDomain 整域覆盖
    static func enableInSystemPreferences() {
        let methodEntry: [String: Any] = [
            "Bundle ID": bundleId,
            "InputSourceKind": "Keyboard Input Method"
        ]

        var enabled = CFPreferencesCopyAppValue(
            "AppleEnabledInputSources" as CFString,
            hiToolbox
        ) as? [[String: Any]]
        if enabled == nil {
            let plistURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/com.apple.HIToolbox.plist")
            if let dict = NSDictionary(contentsOf: plistURL) as? [String: Any],
               let list = dict["AppleEnabledInputSources"] as? [[String: Any]] {
                enabled = list
            }
        }
        // 去掉旧的 mode / 重复 method，再只留一条
        var list = (enabled ?? []).filter { ($0["Bundle ID"] as? String) != bundleId }
        list.append(methodEntry)

        CFPreferencesSetAppValue(
            "AppleEnabledInputSources" as CFString,
            list as CFArray,
            hiToolbox
        )
        CFPreferencesAppSynchronize(hiToolbox)
        NSLog("[MeifengWubi] wrote AppleEnabledInputSources, count=%d", list.count)
    }

    static func isEnabledInPrefs() -> Bool {
        if let enabled = CFPreferencesCopyAppValue(
            "AppleEnabledInputSources" as CFString,
            hiToolbox
        ) as? [[String: Any]] {
            return enabled.contains { ($0["Bundle ID"] as? String) == bundleId }
        }
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.HIToolbox.plist")
        guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let enabled = dict["AppleEnabledInputSources"] as? [[String: Any]] else {
            return false
        }
        return enabled.contains { ($0["Bundle ID"] as? String) == bundleId }
    }

    static func openInputSourcesPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

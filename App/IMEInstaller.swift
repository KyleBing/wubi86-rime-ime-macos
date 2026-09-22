import AppKit
import Carbon
import Foundation

enum IMEInstaller {
    static var installedIMEURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/MeifengWubiIME.app")
    }

    static let bundleId = "cn.kylebing.inputmethod.meifengwubi"
    static let modeId = "cn.kylebing.inputmethod.meifengwubi.wubi"
    private static let hiToolbox = "com.apple.HIToolbox" as CFString

    static func statusText() -> String {
        let exists = FileManager.default.fileExists(atPath: installedIMEURL.path)
        let enabled = isEnabledInPrefs()
        if exists && enabled {
            return "已安装且已启用（系统设置 → 键盘 → 输入法 → 简体中文 → 玫枫五笔）"
        }
        if exists {
            return "已安装到 ~/Library/Input Methods/，请点「安装 / 更新」启用，或到输入法「+」→ 简体中文添加"
        }
        return "尚未安装到 ~/Library/Input Methods/"
    }

    static func copyEmbeddedIME() throws {
        guard let embedded = Bundle.main.url(forResource: "MeifengWubiIME", withExtension: "app") else {
            throw NSError(domain: "IMEInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "宿主包内找不到 MeifengWubiIME.app，请先完整编译 MeifengWubi 目标"
            ])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: installedIMEURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["MeifengWubiIME"]
        try? kill.run()
        kill.waitUntilExit()

        unregisterBuildProductCopies()

        if fm.fileExists(atPath: installedIMEURL.path) {
            let ls = Process()
            ls.executableURL = URL(fileURLWithPath: lsregisterPath)
            ls.arguments = ["-u", installedIMEURL.path]
            try? ls.run()
            ls.waitUntilExit()
            try fm.removeItem(at: installedIMEURL)
        }
        try fm.copyItem(at: embedded, to: installedIMEURL)
    }

    static func finishInstallOnMain() {
        precondition(Thread.isMainThread, "finishInstallOnMain 必须在主线程")
        registerInputSource(at: installedIMEURL)
        enableInSystemPreferences()
        _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
        switch RimeConfigDeploy.deployNow() {
        case .success: NSLog("[MeifengWubi] pre-deploy ok")
        case .failure(let err): NSLog("[MeifengWubi] pre-deploy failed: %@", err)
        }
        let killAgent = Process()
        killAgent.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killAgent.arguments = ["TextInputMenuAgent"]
        try? killAgent.run()
        killAgent.waitUntilExit()
        NSWorkspace.shared.open(installedIMEURL)
    }

    static func installEmbeddedIME() throws {
        precondition(Thread.isMainThread, "installEmbeddedIME 必须在主线程")
        try copyEmbeddedIME()
        finishInstallOnMain()
    }

    private static var lsregisterPath: String {
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    }

    private static func unregisterBuildProductCopies() {
        let candidates = [
            "build/DerivedDataRelease/Build/Products/Release/MeifengWubiIME.app",
            "build/DerivedDataRelease/Build/Products/Release/MeifengWubi.app/Contents/Resources/MeifengWubiIME.app",
            "build/DerivedData/Build/Products/Debug/MeifengWubiIME.app",
            "build/DerivedData/Build/Products/Debug/MeifengWubi.app/Contents/Resources/MeifengWubiIME.app"
        ]
        let roots = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Developer/wubi86-rime-macos-ime").path
        ]
        var paths = Set<String>()
        for root in roots {
            for rel in candidates { paths.insert(root + "/" + rel) }
        }
        if let embedded = Bundle.main.url(forResource: "MeifengWubiIME", withExtension: "app") {
            paths.insert(embedded.path)
        }
        for path in paths {
            guard path != installedIMEURL.path,
                  FileManager.default.fileExists(atPath: path) else { continue }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: lsregisterPath)
            task.arguments = ["-u", path]
            try? task.run()
            task.waitUntilExit()
        }
    }

    private static func registerInputSource(at url: URL) {
        precondition(Thread.isMainThread, "TIS 必须在主线程")
        _ = TISRegisterInputSource(url as CFURL)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsregisterPath)
        task.arguments = ["-f", "-trusted", url.path]
        try? task.run()
        task.waitUntilExit()

        // 只 Enable 五笔 mode 一次（供「简体中文」分类与菜单栏使用）
        var didMode = false
        if let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] {
            for src in list {
                guard let bp = TISGetInputSourceProperty(src, kTISPropertyBundleID) else { continue }
                let bid = "\(Unmanaged<CFTypeRef>.fromOpaque(bp).takeUnretainedValue())"
                guard bid == bundleId else { continue }
                let iid: String = {
                    guard let ip = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "" }
                    return "\(Unmanaged<CFTypeRef>.fromOpaque(ip).takeUnretainedValue())"
                }()
                if iid == modeId, !didMode {
                    _ = TISEnableInputSource(src)
                    didMode = true
                    NSLog("[MeifengWubi] enabled mode %@", modeId)
                }
            }
        }
    }

    /// 写 Input Mode + Keyboard Input Method（与系统拼音一致，否则「+」列表可能看不到）
    static func enableInSystemPreferences() {
        let modeEntry: [String: Any] = [
            "Bundle ID": bundleId,
            "Input Mode": modeId,
            "InputSourceKind": "Input Mode"
        ]
        let methodEntry: [String: Any] = [
            "Bundle ID": bundleId,
            "InputSourceKind": "Keyboard Input Method"
        ]

        var enabled = CFPreferencesCopyAppValue(
            "AppleEnabledInputSources" as CFString, hiToolbox
        ) as? [[String: Any]]
        if enabled == nil {
            let plistURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/com.apple.HIToolbox.plist")
            if let dict = NSDictionary(contentsOf: plistURL) as? [String: Any],
               let list = dict["AppleEnabledInputSources"] as? [[String: Any]] {
                enabled = list
            }
        }
        var list = (enabled ?? []).filter { ($0["Bundle ID"] as? String) != bundleId }
        list.append(modeEntry)
        list.append(methodEntry)

        CFPreferencesSetAppValue(
            "AppleEnabledInputSources" as CFString, list as CFArray, hiToolbox
        )
        CFPreferencesAppSynchronize(hiToolbox)
        NSLog("[MeifengWubi] HIToolbox entries=%d", list.count)
    }

    static func isEnabledInPrefs() -> Bool {
        if let enabled = CFPreferencesCopyAppValue(
            "AppleEnabledInputSources" as CFString, hiToolbox
        ) as? [[String: Any]] {
            return enabled.contains { ($0["Bundle ID"] as? String) == bundleId }
        }
        return false
    }

    static func openInputSourcesPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

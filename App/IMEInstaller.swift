import AppKit
import Carbon
import Foundation

enum IMEInstaller {
    // 用户目录安装，无需管理员权限（与改系统 /Library 的 osascript 提权无关）
    static var installedIMEURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/MeifengWubiIME.app")
    }

    // 若曾装到系统目录，安装时一并注销，避免双份
    private static let legacySystemIMEURL = URL(fileURLWithPath: "/Library/Input Methods/MeifengWubiIME.app")

    static let bundleId = "cn.kylebing.inputmethod.meifengwubi"
    static let modeId = "cn.kylebing.inputmethod.meifengwubi.wubi"

    static func statusText() -> String {
        let exists = FileManager.default.fileExists(atPath: installedIMEURL.path)
        let enabled = isModeEnabled()
        if exists && enabled {
            return "已安装且已启用（系统设置 → 键盘 → 输入法 → 简体中文 → 玫枫五笔）"
        }
        if exists {
            return "已安装到 ~/Library/Input Methods/，请点「安装 / 更新」启用（会自动加入菜单栏列表）"
        }
        return "尚未安装到 ~/Library/Input Methods/"
    }

    static func copyEmbeddedIME() throws {
        guard let embedded = Bundle.main.url(forResource: "MeifengWubiIME", withExtension: "payload") else {
            throw NSError(domain: "IMEInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "宿主包内找不到 MeifengWubiIME.payload，请先完整编译 MeifengWubi 目标"
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
        // 宿主包内的 .payload、用户目录旧副本、曾装到系统目录的副本一并注销
        unregisterPaths([embedded.path, installedIMEURL.path, legacySystemIMEURL.path])

        if fm.fileExists(atPath: installedIMEURL.path) {
            try fm.removeItem(at: installedIMEURL)
        }
        try fm.copyItem(at: embedded, to: installedIMEURL)
    }

    static func finishInstallOnMain() {
        precondition(Thread.isMainThread, "finishInstallOnMain 必须在主线程")
        registerInputSource(at: installedIMEURL)
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
    }

    // 结束正在运行的输入法进程，系统下次需要时会自动拉起，从而读到新的词库目录
    static func restartRunningIME() {
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["MeifengWubiIME"]
        try? kill.run()
        kill.waitUntilExit()
    }

    static func installEmbeddedIME() throws {
        precondition(Thread.isMainThread, "installEmbeddedIME 必须在主线程")
        try copyEmbeddedIME()
        finishInstallOnMain()
    }

    private static var lsregisterPath: String {
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    }

    private static func unregisterPaths(_ paths: [String]) {
        // 即使文件已删也要 -u：Launch Services 会残留幽灵注册（launch-disabled）。
        for path in paths {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: lsregisterPath)
            task.arguments = ["-u", path]
            try? task.run()
            task.waitUntilExit()
        }
    }

    private static func unregisterBuildProductCopies() {
        let fm = FileManager.default
        var paths = Set<String>()
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            home.appendingPathComponent("Developer/wubi86-rime-macos-ime/build"),
            URL(fileURLWithPath: "/Applications"),
        ]
        let names: Set<String> = ["MeifengWubiIME.app", "MeifengWubiIME.payload"]
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where names.contains(url.lastPathComponent) {
                paths.insert(url.path)
                enumerator.skipDescendants()
            }
        }
        // 常见幽灵路径（宿主改名 / 已从 Applications 删除后仍留在 LS 库）
        paths.insert("/Applications/MeifengWubi.app/Contents/Resources/MeifengWubiIME.payload")
        paths.insert("/Applications/玫枫五笔.app/Contents/Resources/MeifengWubiIME.payload")
        if let embedded = Bundle.main.url(forResource: "MeifengWubiIME", withExtension: "payload") {
            paths.insert(embedded.path)
        }
        unregisterPaths(Array(paths).filter { $0 != installedIMEURL.path })
    }

    /// 打开宿主时调用：清掉包内 payload 抢注册，只保留用户目录输入法。
    static func reassertInstalledIME() {
        precondition(Thread.isMainThread, "TIS 必须在主线程")
        guard FileManager.default.fileExists(atPath: installedIMEURL.path) else { return }
        unregisterBuildProductCopies()
        unregisterPaths([legacySystemIMEURL.path])
        registerInputSource(at: installedIMEURL)
    }

    private static func registerInputSource(at url: URL) {
        precondition(Thread.isMainThread, "TIS 必须在主线程")
        // 卸掉再启用。不要同时手写 HIToolbox + ThirdParty，否则 mode 会双份。
        removeFromThirdPartyEnabledList()
        removeFromHIToolboxEnabledList()
        for source in registeredSources(includeAllInstalled: false) {
            NSLog("[MeifengWubi] disable %@", inputSourceID(source))
            _ = TISDisableInputSource(source)
        }
        DistributedNotificationCenter.default().post(
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )

        _ = TISRegisterInputSource(url as CFURL)

        // 注册后列表偶发延迟，短暂重试
        var sources: [TISInputSource] = []
        for _ in 0..<20 {
            sources = registeredSources(includeAllInstalled: true)
            if sources.contains(where: { inputSourceID($0) == modeId }) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }

        // mode 依赖父输入法已启用
        if let method = sources.first(where: { inputSourceID($0) == bundleId }) {
            _ = TISEnableInputSource(method)
            NSLog("[MeifengWubi] enabled method %@", bundleId)
        }
        if let mode = sources.first(where: { inputSourceID($0) == modeId }) {
            _ = TISEnableInputSource(mode)
            NSLog("[MeifengWubi] enabled mode %@", modeId)
            _ = TISSelectInputSource(mode)
        } else {
            NSLog("[MeifengWubi] mode not found after register: %@", modeId)
        }
        // 只写 Input Mode，避免设置页多出空白父项行
        ensureInThirdPartyEnabledList()
        DistributedNotificationCenter.default().post(
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
    }

    private static let inputSourcesDomain = "com.apple.inputsources" as CFString
    private static let thirdPartyKey = "AppleEnabledThirdPartyInputSources"
    private static let hiToolboxDomain = "com.apple.HIToolbox" as CFString

    private static func loadThirdPartyEnabledList() -> [[String: Any]] {
        CFPreferencesAppSynchronize(inputSourcesDomain)
        guard let raw = CFPreferencesCopyAppValue(thirdPartyKey as CFString, inputSourcesDomain) as? [[String: Any]] else {
            return []
        }
        return raw
    }

    private static func saveThirdPartyEnabledList(_ list: [[String: Any]]) {
        CFPreferencesSetAppValue(thirdPartyKey as CFString, list as CFArray, inputSourcesDomain)
        CFPreferencesAppSynchronize(inputSourcesDomain)
    }

    private static func removeFromThirdPartyEnabledList() {
        let filtered = loadThirdPartyEnabledList().filter { ($0["Bundle ID"] as? String) != bundleId }
        saveThirdPartyEnabledList(filtered)
    }

    private static func ensureInThirdPartyEnabledList() {
        // 只保留 Input Mode，丢掉父项 Keyboard Input Method，避免菜单栏/设置页异常。
        var list = loadThirdPartyEnabledList().filter { ($0["Bundle ID"] as? String) != bundleId }
        list.append([
            "Bundle ID": bundleId,
            "Input Mode": modeId,
            "InputSourceKind": "Input Mode",
        ])
        saveThirdPartyEnabledList(list)
    }

    // 清掉误写入 HIToolbox 的条目，防止与 ThirdParty 叠成双份 mode
    private static func removeFromHIToolboxEnabledList() {
        for key in ["AppleEnabledInputSources", "AppleSelectedInputSources"] {
            guard let entries = CFPreferencesCopyValue(
                key as CFString,
                hiToolboxDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [[String: Any]] else { continue }
            let filtered = entries.filter { ($0["Bundle ID"] as? String) != bundleId }
            CFPreferencesSetValue(
                key as CFString,
                filtered as CFArray,
                hiToolboxDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        CFPreferencesSynchronize(hiToolboxDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func registeredSources(includeAllInstalled: Bool = true) -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, includeAllInstalled)?
            .takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.filter { inputSourceProperty($0, key: kTISPropertyBundleID) == bundleId }
    }

    private static func inputSourceID(_ source: TISInputSource) -> String {
        inputSourceProperty(source, key: kTISPropertyInputSourceID)
    }

    private static func inputSourceProperty(_ source: TISInputSource, key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
        return "\(Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue())"
    }

    static func isModeEnabled() -> Bool {
        registeredSources(includeAllInstalled: false).contains {
            inputSourceID($0) == modeId
        }
    }

    static func openInputSourcesPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

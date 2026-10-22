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
        let componentNote = hasNewerEmbeddedComponent ? "；输入法组件有新版本，点「安装 / 更新」应用" : ""
        if exists && enabled {
            return "已安装且已启用（系统设置 → 键盘 → 输入法 → 简体中文 → 玫枫五笔）\(componentNote)"
        }
        if exists {
            return "已安装到 ~/Library/Input Methods/，请点「安装 / 更新」启用（会自动加入菜单栏列表）\(componentNote)"
        }
        return "尚未安装到 ~/Library/Input Methods/"
    }

    /// 宿主包里携带的输入法组件版本（Sparkle 更新宿主后，这份是新的）
    static var embeddedIMEVersion: (version: String, build: Int)? {
        guard let url = Bundle.main.url(forResource: "MeifengWubiIME", withExtension: "payload") else { return nil }
        return bundleVersion(at: url)
    }

    /// 已安装到 ~/Library/Input Methods 的输入法版本
    static var installedIMEVersion: (version: String, build: Int)? {
        bundleVersion(at: installedIMEURL)
    }

    /// 宿主里的 payload 比已安装副本新：Sparkle 只换了宿主，需要重跑一次安装
    static var hasNewerEmbeddedComponent: Bool {
        guard let embedded = embeddedIMEVersion, let installed = installedIMEVersion else { return false }
        if UpdateChecker.isNewer(embedded.version, than: installed.version) { return true }
        return embedded.version == installed.version && embedded.build > installed.build
    }

    /// 输入法进程是否在跑。没在跑时换组件不会打断用户打字。
    static var isIMERunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    /// 更新宿主后自动换上新组件；输入法正在使用时不动，等用户点「安装 / 更新」。
    @discardableResult
    static func applyComponentUpdateIfIdle() -> Bool {
        guard hasNewerEmbeddedComponent, !isIMERunning else { return false }
        do {
            try copyEmbeddedIME()
            finishInstallOnMain()
            return true
        } catch {
            return false
        }
    }

    private static func bundleVersion(at url: URL) -> (version: String, build: Int)? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) else { return nil }
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        return version.isEmpty ? nil : (version, build)
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

        // 只注销包内 payload 和系统目录旧副本。用户目录那份不能先 -u，否则会被标成 launch-disabled。
        unregisterPaths([embedded.path, legacySystemIMEURL.path])

        if fm.fileExists(atPath: installedIMEURL.path) {
            try fm.removeItem(at: installedIMEURL)
        }
        try fm.copyItem(at: embedded, to: installedIMEURL)
    }

    static func finishInstallOnMain() {
        precondition(Thread.isMainThread, "finishInstallOnMain 必须在主线程")
        // 点「安装 / 更新」时换的是正在用的包，需要把旧进程换掉。
        adoptInstalledBundle(restartIME: true)
        // 词库部署可能要几十秒，留在主线程会让整个窗口点不了。
        DispatchQueue.global(qos: .userInitiated).async {
            _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
            switch RimeConfigDeploy.deployNow() {
            case .success: NSLog("[MeifengWubi] pre-deploy ok")
            case .failure(let err): NSLog("[MeifengWubi] pre-deploy failed: %@", err)
            }
        }
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
            home.appendingPathComponent("Developer/wubi86-rime-ime-macos/build"),
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

    /// 打开宿主时调用：只注销包内 payload 等已知幽灵路径（可在后台跑）。
    /// 不要扫 DerivedData，那会把主线程堵住十几秒，窗口一直进不去。
    static func unregisterKnownGhostCopies() {
        var paths = [
            "/Applications/MeifengWubi.app/Contents/Resources/MeifengWubiIME.payload",
            "/Applications/玫枫五笔.app/Contents/Resources/MeifengWubiIME.payload",
            legacySystemIMEURL.path,
        ]
        if let embedded = Bundle.main.url(forResource: "MeifengWubiIME", withExtension: "payload") {
            paths.append(embedded.path)
        }
        unregisterPaths(paths.filter { $0 != installedIMEURL.path })
    }

    /// 刷新状态时清构建目录里的旧副本。会遍历 DerivedData，必须放后台。
    static func unregisterStaleBuildCopies() {
        unregisterBuildProductCopies()
        unregisterPaths([legacySystemIMEURL.path])
    }

    /// 打开宿主时调用：已启用只刷新登记，不 disable，避免刚选中的输入法掉线。
    static func ensureEnabledOnMain() {
        precondition(Thread.isMainThread, "TIS 必须在主线程")
        // 打开宿主时不杀正在打字的输入法进程，只把登记刷新到用户目录副本。
        adoptInstalledBundle(restartIME: false)
    }

    /// 安装或手动刷新后，把用户目录输入法重新登记为当前项。调用前应已在后台清完幽灵路径。
    static func reassertInstalledIME() {
        precondition(Thread.isMainThread, "TIS 必须在主线程")
        adoptInstalledBundle(restartIME: false)
    }

    // 已启用时只重新登记用户目录的包，不 disable、不杀菜单进程。首次安装才走完整启用。
    private static func adoptInstalledBundle(restartIME: Bool) {
        precondition(Thread.isMainThread, "adoptInstalledBundle 必须在主线程")
        guard FileManager.default.fileExists(atPath: installedIMEURL.path) else { return }
        registerBundleWithLaunchServices(installedIMEURL)
        if isModeEnabled() {
            _ = TISRegisterInputSource(installedIMEURL as CFURL)
            postInputSourcesChanged()
            if restartIME { restartRunningIME() }
            return
        }
        registerInputSource(at: installedIMEURL)
    }

    // 强制刷新 Launch Services 里这一条，清掉以前 -u 留下的 launch-disabled。
    private static func registerBundleWithLaunchServices(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: lsregisterPath)
        task.arguments = ["-f", "-R", url.path]
        try? task.run()
        task.waitUntilExit()
    }

    private static func postInputSourcesChanged() {
        DistributedNotificationCenter.default().post(
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
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

        // 只启用输入模式。启用模式时系统会带上父项；父子各启用一次会弹出两个允许窗口。
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
        // 只结束输入法自己。菜单进程继续跑，下次切换时会拉起新包。
        DispatchQueue.global(qos: .userInitiated).async {
            restartRunningIME()
        }
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

    // 只清启用列表里的重复项。不要动 AppleSelectedInputSources，否则一切换软件就退回别的输入法。
    private static func removeFromHIToolboxEnabledList() {
        for key in ["AppleEnabledInputSources"] {
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

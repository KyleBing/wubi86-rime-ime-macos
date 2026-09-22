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
        let enabled = isModeEnabled()
        if exists && enabled {
            return "已安装且已启用（系统设置 → 键盘 → 输入法 → 简体中文 → 玫枫五笔）"
        }
        if exists {
            return "已安装到 ~/Library/Input Methods/，请点「安装 / 更新」启用，或到输入法「+」→ 简体中文添加"
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

    static func installEmbeddedIME() throws {
        precondition(Thread.isMainThread, "installEmbeddedIME 必须在主线程")
        try copyEmbeddedIME()
        finishInstallOnMain()
    }

    private static var lsregisterPath: String {
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    }

    private static func unregisterBuildProductCopies() {
        let fm = FileManager.default
        let candidates = [
            "build/DerivedDataRelease/Build/Products/Release/MeifengWubiIME.app",
            "build/DerivedData/Build/Products/Debug/MeifengWubiIME.app",
        ]
        let roots = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Developer/wubi86-rime-macos-ime").path
        ]
        var paths = Set<String>()
        for root in roots {
            for rel in candidates { paths.insert(root + "/" + rel) }
        }
        // Xcode 默认 DerivedData 中的副本也会被系统注册，需一并注销以免输入源重复
        let derivedDataRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if let enumerator = fm.enumerator(
            at: derivedDataRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator where url.lastPathComponent == "MeifengWubiIME.app" {
                paths.insert(url.path)
                enumerator.skipDescendants()
            }
        }
        for path in paths {
            guard path != installedIMEURL.path,
                  fm.fileExists(atPath: path) else { continue }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: lsregisterPath)
            task.arguments = ["-u", path]
            try? task.run()
            task.waitUntilExit()
        }
    }

    private static func registerInputSource(at url: URL) {
        precondition(Thread.isMainThread, "TIS 必须在主线程")
        removeLegacyPreferenceEntries()
        _ = TISRegisterInputSource(url as CFURL)

        // 注册后再次清理缓存，只启用一个可选择的五笔模式
        let sources = registeredSources()
        sources.forEach { _ = TISDisableInputSource($0) }
        if let mode = sources.first(where: { inputSourceID($0) == modeId }) {
            _ = TISEnableInputSource(mode)
            NSLog("[MeifengWubi] enabled mode %@", modeId)
        }
    }

    private static func removeLegacyPreferenceEntries() {
        // 旧版本手工写入 HIToolbox，与 TISEnableInputSource 的第三方记录叠加后会显示重复项
        for key in ["AppleEnabledInputSources", "AppleSelectedInputSources"] {
            guard let entries = CFPreferencesCopyValue(
                key as CFString,
                hiToolbox,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [[String: Any]] else { continue }
            let filtered = entries.filter { ($0["Bundle ID"] as? String) != bundleId }
            CFPreferencesSetValue(
                key as CFString,
                filtered as CFArray,
                hiToolbox,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        CFPreferencesSynchronize(hiToolbox, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
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

import Carbon
import Foundation

let path = NSString(string: "~/Library/Input Methods/MeifengWubiIME.app").expandingTildeInPath
let systemPath = "/Library/Input Methods/MeifengWubiIME.app"
let bundleId = "cn.kylebing.inputmethod.meifengwubi"
let modeId = "cn.kylebing.inputmethod.meifengwubi.wubi"
let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
let inputSourcesDomain = "com.apple.inputsources" as CFString
let thirdPartyKey = "AppleEnabledThirdPartyInputSources" as CFString

func unregister(_ item: String) {
    // 文件已删也要注销，否则 LS 留下 launch-disabled 幽灵项。
    let task = Process()
    task.executableURL = URL(fileURLWithPath: lsregister)
    task.arguments = ["-u", item]
    try? task.run()
    task.waitUntilExit()
    print("unregister:", item)
}

// 只注销构建目录 / Applications 宿主包内 payload / 系统目录旧副本。
let home = FileManager.default.homeDirectoryForCurrentUser
let roots = [
    home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
    home.appendingPathComponent("Developer/wubi86-rime-macos-ime/build"),
    URL(fileURLWithPath: "/Applications"),
]
let names: Set<String> = ["MeifengWubiIME.app", "MeifengWubiIME.payload"]
var stale: [String] = [
    "/Applications/MeifengWubi.app/Contents/Resources/MeifengWubiIME.payload",
    "/Applications/玫枫五笔.app/Contents/Resources/MeifengWubiIME.payload",
]
for root in roots where FileManager.default.fileExists(atPath: root.path) {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { continue }
    for case let url as URL in enumerator where names.contains(url.lastPathComponent) {
        if url.path != path { stale.append(url.path) }
        enumerator.skipDescendants()
    }
}
stale.forEach(unregister)
if systemPath != path { unregister(systemPath) }
print("kept:", path)

guard FileManager.default.fileExists(atPath: path) else {
    print("skip TIS refresh: IME not installed")
    exit(0)
}

func property(_ source: TISInputSource, _ key: CFString) -> String {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
    return "\(Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue())"
}

func sources(includeAll: Bool) -> [TISInputSource] {
    guard let list = TISCreateInputSourceList(nil, includeAll)?
        .takeRetainedValue() as? [TISInputSource] else { return [] }
    return list.filter { property($0, kTISPropertyBundleID) == bundleId }
}

let hiToolbox = "com.apple.HIToolbox" as CFString

func loadThirdParty() -> [[String: Any]] {
    CFPreferencesAppSynchronize(inputSourcesDomain)
    return (CFPreferencesCopyAppValue(thirdPartyKey, inputSourcesDomain) as? [[String: Any]]) ?? []
}

func saveThirdParty(_ list: [[String: Any]]) {
    CFPreferencesSetAppValue(thirdPartyKey, list as CFArray, inputSourcesDomain)
    CFPreferencesAppSynchronize(inputSourcesDomain)
}

// 清 HIToolbox 里误写入的条目，避免与 ThirdParty 双份 mode（设置页会丢）
for key in ["AppleEnabledInputSources", "AppleSelectedInputSources"] {
    guard let entries = CFPreferencesCopyValue(
        key as CFString, hiToolbox, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
    ) as? [[String: Any]] else { continue }
    let filtered = entries.filter { ($0["Bundle ID"] as? String) != bundleId }
    CFPreferencesSetValue(
        key as CFString, filtered as CFArray, hiToolbox, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
    )
}
CFPreferencesSynchronize(hiToolbox, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

// 覆盖安装后菜单栏常不刷新：先从第三方列表卸掉，再 disable / register / enable。
var third = loadThirdParty().filter { ($0["Bundle ID"] as? String) != bundleId }
saveThirdParty(third)
for source in sources(includeAll: false) {
    let id = property(source, kTISPropertyInputSourceID)
    _ = TISDisableInputSource(source)
    print("disable:", id)
}
DistributedNotificationCenter.default().post(
    name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
    object: nil
)

_ = TISRegisterInputSource(URL(fileURLWithPath: path) as CFURL)

var all: [TISInputSource] = []
for _ in 0..<20 {
    all = sources(includeAll: true)
    if all.contains(where: { property($0, kTISPropertyInputSourceID) == modeId }) { break }
    Thread.sleep(forTimeInterval: 0.05)
}

if let method = all.first(where: { property($0, kTISPropertyInputSourceID) == bundleId }) {
    _ = TISEnableInputSource(method)
    print("enable method:", bundleId)
}
if let mode = all.first(where: { property($0, kTISPropertyInputSourceID) == modeId }) {
    _ = TISEnableInputSource(mode)
    _ = TISSelectInputSource(mode)
    print("enable mode:", modeId)
} else {
    print("mode not found after register")
    exit(1)
}

third = loadThirdParty().filter { ($0["Bundle ID"] as? String) != bundleId }
third.append([
    "Bundle ID": bundleId,
    "Input Mode": modeId,
    "InputSourceKind": "Input Mode",
])
saveThirdParty(third)
DistributedNotificationCenter.default().post(
    name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
    object: nil
)

let enabled = sources(includeAll: false).map { property($0, kTISPropertyInputSourceID) }
print("enabled now:", enabled.joined(separator: ", "))
print("unique enabled:", Set(enabled).count, "of", enabled.count)

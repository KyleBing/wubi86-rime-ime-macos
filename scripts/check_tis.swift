import Carbon
import Foundation

// cleanup：只注销幽灵路径，不 disable / enable。安装脚本用它，避免每次都弹「允许输入法」。
// refresh：同样先清幽灵路径，再把用户目录的包重新登记给正在运行的输入法服务，不杀菜单进程。
let args = CommandLine.arguments.dropFirst()
let cleanupOnly = args.contains("cleanup")
let refreshOnly = args.contains("refresh")

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
    home.appendingPathComponent("Developer/wubi86-rime-ime-macos/build"),
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

if cleanupOnly {
    print("cleanup only, skip enable")
    exit(0)
}

if refreshOnly {
    refreshInstalledIME()
    exit(0)
}

// 覆盖安装后通知当前登录会话：路径不变，只换了包内容。已启用则不再 disable / enable。
func refreshInstalledIME() {
    let register = Process()
    register.executableURL = URL(fileURLWithPath: lsregister)
    register.arguments = ["-f", "-R", path]
    try? register.run()
    register.waitUntilExit()
    print("lsregister:", path)

    _ = TISRegisterInputSource(URL(fileURLWithPath: path) as CFURL)
    var enabled = sources(includeAll: false)
    if !enabled.contains(where: { property($0, kTISPropertyInputSourceID) == modeId }) {
        let all = sources(includeAll: true)
        if let mode = all.first(where: { property($0, kTISPropertyInputSourceID) == modeId }) {
            _ = TISEnableInputSource(mode)
            print("enable mode:", modeId)
        } else {
            print("mode not found after register")
            exit(1)
        }
        enabled = sources(includeAll: false)
    } else {
        print("already enabled, skip enable")
    }
    DistributedNotificationCenter.default().post(
        name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
        object: nil
    )
    print("enabled now:", enabled.map { property($0, kTISPropertyInputSourceID) }.joined(separator: ", "))
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

// 只清启用列表。Selected 是当前选中项，清掉后一切到别的软件就会掉回旧输入法。
for key in ["AppleEnabledInputSources"] {
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

// 只启用输入模式。系统会一并启用父项；再对父项调用一次会多弹一个允许窗口。
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

import Carbon
import Foundation

let path = NSString(string: "~/Library/Input Methods/MeifengWubiIME.app").expandingTildeInPath
let bundleId = "cn.kylebing.inputmethod.meifengwubi"
let modeId = "cn.kylebing.inputmethod.meifengwubi.wubi"

// 清除旧安装器写入 HIToolbox 的重复记录，启用状态交给 TIS 维护
let hiToolbox = "com.apple.HIToolbox" as CFString
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

print("path:", path, "exists:", FileManager.default.fileExists(atPath: path))
print("register:", TISRegisterInputSource(URL(fileURLWithPath: path) as CFURL))

func prop(_ src: TISInputSource, _ key: CFString) -> String? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return "\(Unmanaged<CFTypeRef>.fromOpaque(p).takeUnretainedValue())"
}

guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
    fputs("no list\n", stderr); exit(1)
}

var found = 0
var matches: [TISInputSource] = []
for src in list {
    let bid = prop(src, kTISPropertyBundleID) ?? ""
    guard bid == bundleId else { continue }
    found += 1
    matches.append(src)
    let iid = prop(src, kTISPropertyInputSourceID) ?? ""
    let typ = prop(src, kTISPropertyInputSourceType) ?? ""
    let name = prop(src, kTISPropertyLocalizedName) ?? ""
    print("FOUND id=\(iid) type=\(typ) name=\(name)")
}

// 每次安装先禁用全部旧记录，再只启用一个可选择模式
matches.forEach { _ = TISDisableInputSource($0) }
let mode = matches.first { prop($0, kTISPropertyInputSourceID) == modeId }
let enabledMode = mode.map {
    print("  enable mode:", TISEnableInputSource($0))
    print("  select mode:", TISSelectInputSource($0))
    return true
} ?? false
print("found:", found, "modeEnabled:", enabledMode)

import Carbon
import Foundation

let path = NSString(string: "~/Library/Input Methods/MeifengWubiIME.app").expandingTildeInPath
let bundleId = "cn.kylebing.inputmethod.meifengwubi"
let modeId = "cn.kylebing.inputmethod.meifengwubi.wubi"
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
var enabledMode = false
for src in list {
    let bid = prop(src, kTISPropertyBundleID) ?? ""
    guard bid == bundleId else { continue }
    found += 1
    let iid = prop(src, kTISPropertyInputSourceID) ?? ""
    let typ = prop(src, kTISPropertyInputSourceType) ?? ""
    let name = prop(src, kTISPropertyLocalizedName) ?? ""
    print("FOUND id=\(iid) type=\(typ) name=\(name)")
    if iid == modeId, !enabledMode {
        print("  enable mode:", TISEnableInputSource(src))
        print("  select mode:", TISSelectInputSource(src))
        enabledMode = true
    }
}
print("found:", found, "modeEnabled:", enabledMode)

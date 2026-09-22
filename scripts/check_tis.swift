import Carbon
import Foundation

let path = NSString(string: "~/Library/Input Methods/MeifengWubiIME.app").expandingTildeInPath
print("path:", path)
print("exists:", FileManager.default.fileExists(atPath: path))
let url = URL(fileURLWithPath: path) as CFURL
print("register:", TISRegisterInputSource(url))

guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
    fputs("no list\n", stderr)
    exit(1)
}

func prop(_ src: TISInputSource, _ key: CFString) -> String? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return "\(Unmanaged<CFTypeRef>.fromOpaque(p).takeUnretainedValue())"
}

var found = 0
var enabledIds = Set<String>()
for src in list {
    let bid = prop(src, kTISPropertyBundleID) ?? ""
    let iid = prop(src, kTISPropertyInputSourceID) ?? ""
    let name = prop(src, kTISPropertyLocalizedName) ?? ""
    if bid.contains("kylebing") || iid.contains("kylebing") || name.contains("玫枫") || name.lowercased().contains("meifeng") || bid.contains("meifengwubi") {
        found += 1
        print("FOUND id=\(iid) name=\(name) bundle=\(bid) type=\(prop(src, kTISPropertyInputSourceType) ?? "")")
        // 同一 ID 只 enable 一次
        if !enabledIds.contains(iid) {
            print("  enable:", TISEnableInputSource(src))
            enabledIds.insert(iid)
        } else {
            print("  skip duplicate id")
        }
    }
}
print("found:", found, "enabledUnique:", enabledIds.count, "total:", list.count)

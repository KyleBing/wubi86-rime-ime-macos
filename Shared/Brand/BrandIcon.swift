import AppKit

/// 品牌图：App 主界面与设置侧栏共用透明 Logo；圆角图仅作兼容保留。
enum BrandIcon {
    static let resourceName = "BrandIconRounded"
    static let settingsResourceName = "SettingsLogo"

    /// 兼容旧调用；新界面请用 settingsImage。
    static func image() -> NSImage? {
        settingsImage()
    }

    /// 透明枫叶 Logo（App 主页 / 设置侧栏），与 AppIcon 无关。
    static func settingsImage() -> NSImage? {
        load(settingsResourceName)
    }

    private static func load(_ name: String) -> NSImage? {
        // 优先当前代码所在 bundle（prefPane / IME / App 均可）。
        if let img = Bundle(for: BundleToken.self).image(forResource: name) {
            return img
        }
        if let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSImage(named: name)
    }

    private final class BundleToken: NSObject {}
}

import AppKit

/// 圆角品牌图：App 主界面 / 输入法设置面板共用
enum BrandIcon {
    static let resourceName = "BrandIconRounded"
    static let settingsResourceName = "SettingsLogo"

    static func image() -> NSImage? {
        load(resourceName)
    }

    /// 设置侧边栏使用独立的透明枫叶 Logo，不影响 App 和输入法图标。
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

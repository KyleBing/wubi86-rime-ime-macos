import Foundation

/// macOS：用 Application Support 代替 iOS App Group；保留同名 API 以便共享代码少改
enum AppGroupPaths {
    // 保留字段名，实际不再使用 App Group
    static let appGroupId = "cn.kylebing.wubi86rime.macos"

    static var containerURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MeifengWubi", isDirectory: true)
    }

    static var rimeUserDataURL: URL? {
        containerURL?.appendingPathComponent("rime", isDirectory: true)
    }

    static var userDictURL: URL? {
        rimeUserDataURL?.appendingPathComponent("wubi86_jidian_user.dict.yaml")
    }

    @discardableResult
    static func ensureDirectories() -> Bool {
        guard let rimeUserDataURL else { return false }
        do {
            try FileManager.default.createDirectory(at: rimeUserDataURL, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}

import Foundation

/// macOS：用 Application Support 代替 iOS App Group；保留同名 API 以便共享代码少改
enum AppGroupPaths {
    // 保留字段名，实际不再使用 App Group
    static let appGroupId = "cn.kylebing.wubi86rime.macos"

    static var containerURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MeifengWubi", isDirectory: true)
    }

    /// 默认 Rime 目录（Application Support/MeifengWubi/rime）
    static var defaultRimeUserDataURL: URL? {
        containerURL?.appendingPathComponent("rime", isDirectory: true)
    }

    /// 实际使用的 Rime 目录：用户改选过则用自定义目录，否则为默认目录
    static var rimeUserDataURL: URL? {
        customRimeUserDataURL ?? defaultRimeUserDataURL
    }

    // App 与输入法是两个进程，自定义目录以纯文本文件记录在固定容器目录中，双方都能读到
    private static var customDirRecordURL: URL? {
        containerURL?.appendingPathComponent("rime_user_dir.txt")
    }

    /// 用户改选的 Rime 目录；未设置或记录无效时为 nil
    static var customRimeUserDataURL: URL? {
        guard let record = customDirRecordURL,
              let raw = try? String(contentsOf: record, encoding: .utf8)
        else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 写入自定义目录；传 nil 恢复默认目录
    static func setCustomRimeUserDataURL(_ url: URL?) throws {
        guard let container = containerURL, let record = customDirRecordURL else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        if let url, url.standardizedFileURL != defaultRimeUserDataURL?.standardizedFileURL {
            try url.standardizedFileURL.path.write(to: record, atomically: true, encoding: .utf8)
        } else if fm.fileExists(atPath: record.path) {
            try fm.removeItem(at: record)
        }
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

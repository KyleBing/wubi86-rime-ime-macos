import Foundation

/// App / 键盘扩展共用：把内置方案同步到可写目录
enum RimeResourceDeployer {
    static let schemaId = "wubi86_jidian"
    static let schemaFileName = "wubi86_jidian.schema.yaml"
    static let resourceVersionKey = "rime.resource.version"
    // 升版本以强制覆盖同步内置方案（修 charset / history_translator 等）
    static let bundledResourceVersion = "4"

    /// 内置 Resources/Rime 目录
    static var bundledRimeURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Rime", isDirectory: true)
            ?? Bundle.main.url(forResource: "Rime", withExtension: nil)
    }

    /// 可写用户目录（优先 App Group；失败则用本地 Documents/rime）
    static func resolveUserDataURL() -> URL {
        if AppGroupPaths.ensureDirectories(), let url = AppGroupPaths.rimeUserDataURL {
            return url
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rime", isDirectory: true)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    /// 将 Bundle 方案文件同步到用户目录（版本变化时覆盖）
    @discardableResult
    static func syncBundledResourcesIfNeeded() -> (shared: URL, user: URL)? {
        let defaults = UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
        let user = resolveUserDataURL()
        let marker = user.appendingPathComponent(".resource_version")
        let markerValue = (try? String(contentsOf: marker, encoding: .utf8))
            ?? defaults.string(forKey: resourceVersionKey)
        if markerValue == bundledResourceVersion {
            // 仍校验关键文件，坏配置时强制再同步
            let schemaOK = FileManager.default.fileExists(
                atPath: user.appendingPathComponent(schemaFileName).path
            )
            let dictOK = FileManager.default.fileExists(
                atPath: user.appendingPathComponent("wubi86_jidian.dict.yaml").path
            )
            if schemaOK && dictOK {
                return (user, user)
            }
        }
        return try? forceSyncBundledResources(overwriteUserDict: false)
    }

    /// 强制把内置方案拷到用户目录
    /// - Parameter overwriteUserDict: true 时连用户词库一并覆盖（复位用）
    @discardableResult
    static func forceSyncBundledResources(overwriteUserDict: Bool) throws -> (shared: URL, user: URL) {
        guard let bundled = bundledRimeURL,
              FileManager.default.fileExists(atPath: bundled.path) else {
            throw NSError(domain: "RimeResourceDeployer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "找不到内置方案资源 Bundle/Rime"
            ])
        }
        let user = resolveUserDataURL()
        let fm = FileManager.default
        try fm.createDirectory(at: user, withIntermediateDirectories: true)

        let files = try fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil)
        guard !files.isEmpty else {
            throw NSError(domain: "RimeResourceDeployer", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "内置 Rime 目录为空"
            ])
        }
        for file in files {
            let name = file.lastPathComponent
            let dest = user.appendingPathComponent(name)
            let isUserDict = name.hasPrefix("wubi86_jidian_user")
            // 扩展词库可能已从线上拉取，常规同步不要覆盖；复位时 overwriteUserDict=true 会恢复内置
            let isExtraDict = name == "wubi86_jidian_extra.dict.yaml"
            if (isUserDict || isExtraDict), !overwriteUserDict, fm.fileExists(atPath: dest.path) {
                continue
            }
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: file, to: dest)
        }
        let schema = user.appendingPathComponent(schemaFileName)
        let dict = user.appendingPathComponent("wubi86_jidian.dict.yaml")
        let custom = user.appendingPathComponent("default.custom.yaml")
        guard fm.fileExists(atPath: schema.path),
              fm.fileExists(atPath: dict.path),
              fm.fileExists(atPath: custom.path) else {
            throw NSError(domain: "RimeResourceDeployer", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "内置方案拷贝不完整，缺少 schema/dict/default.custom"
            ])
        }
        let marker = user.appendingPathComponent(".resource_version")
        try bundledResourceVersion.write(to: marker, atomically: true, encoding: .utf8)
        let defaults = UserDefaults(suiteName: AppGroupPaths.appGroupId) ?? .standard
        defaults.set(bundledResourceVersion, forKey: resourceVersionKey)
        return (user, user)
    }
}

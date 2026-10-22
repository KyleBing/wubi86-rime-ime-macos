import Foundation

/// update.json 的字段。发布工作流在打标签时生成，作为 Release 附件上传。
/// 客户端只读这一个文件，不调用 GitHub API（未登录时限流 60 次/小时/IP）。
struct UpdateManifest: Decodable {
    let platform: String?
    let version: String
    let build: Int?
    let downloadURL: String?
    let fallbackURL: String?
    let sha256: String?
    let size: Int64?
    let minimumVersion: String?
    let notes: String?
    let notesURL: String?

    enum CodingKeys: String, CodingKey {
        case platform, version, build, sha256, size, notes
        case downloadURL = "download_url"
        case fallbackURL = "fallback_url"
        case minimumVersion = "minimum_version"
        case notesURL = "notes_url"
    }
}

enum UpdateCheckResult {
    case newer(UpdateManifest)
    case upToDate(version: String)
    case failed(String)
}

/// 查更新：主地址是 Release 的固定附件，备用地址是国内镜像。
/// Sparkle 启用时由 Sparkle 自己检查，这里只服务开发包和未配公钥的构建。
enum UpdateChecker {
    static let source = URL(string: "https://github.com/KyleBing/wubi86-rime-ime-macos/releases/latest/download/update.json")!
    static let mirror = URL(string: "https://kylebing.cn/wubi/update/macos.json")!
    static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    private static let lastCheckKey = "update.lastCheckAt"
    private static let skippedKey = "update.skippedVersion"
    private static let autoCheckKey = "update.autoCheck"

    // 清单是静态文件，超时收紧，避免设置窗口一直转圈
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    // 启动时自动检查，默认开启
    static var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    static var isAutoCheckDue: Bool {
        let at = UserDefaults.standard.double(forKey: lastCheckKey)
        return at <= 0 || Date().timeIntervalSince1970 - at >= autoCheckInterval
    }

    // 用户选择「以后再说」的版本，自动提示时跳过
    static var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: skippedKey) }
        set { UserDefaults.standard.set(newValue, forKey: skippedKey) }
    }

    static func check(completion: @escaping (UpdateCheckResult) -> Void) {
        attempt([source, mirror], index: 0, lastError: nil, completion: completion)
    }

    private static func attempt(
        _ sources: [URL],
        index: Int,
        lastError: String?,
        completion: @escaping (UpdateCheckResult) -> Void
    ) {
        guard index < sources.count else {
            completion(.failed(lastError ?? "无法连接更新服务器"))
            return
        }

        var request = URLRequest(
            url: sources[index],
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("MeifengWubi/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            guard
                error == nil,
                let data,
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data),
                !manifest.version.isEmpty
            else {
                let status = (response as? HTTPURLResponse)?.statusCode
                let reason = status == 404
                    ? "更新服务器上还没有发布版本"
                    : (error?.localizedDescription ?? "更新清单格式不正确")
                attempt(sources, index: index + 1, lastError: reason, completion: completion)
                return
            }

            // 两个平台的清单分开托管，防止拿错包
            if let platform = manifest.platform, platform != "macos" {
                attempt(sources, index: index + 1, lastError: "清单平台是 \(platform)", completion: completion)
                return
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            if isNewer(manifest.version, than: currentVersion)
                || (manifest.version == currentVersion && (manifest.build ?? 0) > currentBuild)
            {
                completion(.newer(manifest))
            } else {
                completion(.upToDate(version: currentVersion))
            }
        }.resume()
    }

    /// 只比较数字段，忽略 v 前缀与 -beta 这类后缀。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = versionComponents(candidate), let b = versionComponents(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func versionComponents(_ raw: String) -> [Int]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }

        var parts: [Int] = []
        var digits = ""
        for ch in text {
            if ch.isNumber {
                digits.append(ch)
            } else if ch == "." {
                guard let n = Int(digits) else { return nil }
                parts.append(n)
                digits = ""
            } else {
                break  // 遇到 -beta / +build 就结束
            }
        }
        if !digits.isEmpty {
            guard let n = Int(digits) else { return nil }
            parts.append(n)
        }
        return parts.isEmpty ? nil : parts
    }
}

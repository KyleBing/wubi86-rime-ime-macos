import Foundation

/// 云端同步账号。与码表助手、iOS 共用 portal 账号；凭证写文件，供 App 与输入法两边读取。
struct WubiCloudUserInfo: Codable, Equatable {
    var uid: Int
    var email: String
    var nickname: String
    var token: String

    var isLoggedIn: Bool {
        uid > 0 && !token.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case uid, email, nickname, token
    }

    init(uid: Int, email: String, nickname: String, token: String) {
        self.uid = uid
        self.email = email
        self.nickname = nickname
        self.token = token
    }
}

enum WubiCloudConfig {
    static let defaultBaseURL = "https://kylebing.cn/wubi/"
    static let syncDictFileName = "wubi86_jidian_user.dict.yaml"
    static let extraDictFileName = "wubi86_jidian_extra.dict.yaml"
    static let syncMaxContentLength = 40_000

    private static let fileName = "cloud.json"
    private static let lock = NSLock()

    private struct Store: Codable {
        var baseURL: String = WubiCloudConfig.defaultBaseURL
        var user: WubiCloudUserInfo?
        var lastSyncAt: Double = 0
        var lastExtraPullAt: Double = 0
    }

    static func resolveBaseURL(_ raw: String?) -> String {
        var base = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = defaultBaseURL }
        if base.hasPrefix("http://kylebing.cn/") {
            base = "https://" + base.dropFirst("http://".count)
        }
        // 旧版默认指向 portal-go，拆分后自动切到五笔独立服务
        if base == "https://kylebing.cn/portal/" || base == "https://kylebing.cn/portal" {
            base = defaultBaseURL
        }
        if !base.hasSuffix("/") { base += "/" }
        return base
    }

    static var baseURL: String {
        get { resolveBaseURL(load().baseURL) }
        set { update { $0.baseURL = resolveBaseURL(newValue) } }
    }

    static var userInfo: WubiCloudUserInfo? {
        get {
            guard let info = load().user, info.isLoggedIn else { return nil }
            return info
        }
        set { update { $0.user = newValue } }
    }

    static var isLoggedIn: Bool {
        userInfo?.isLoggedIn == true
    }

    static var lastSyncAt: Date? {
        get {
            let t = load().lastSyncAt
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { update { $0.lastSyncAt = newValue?.timeIntervalSince1970 ?? 0 } }
    }

    static var lastExtraPullAt: Date? {
        get {
            let t = load().lastExtraPullAt
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { update { $0.lastExtraPullAt = newValue?.timeIntervalSince1970 ?? 0 } }
    }

    // 响应头续签 JWT 写回本地
    static func updateTokenIfNeeded(_ token: String) {
        guard !token.isEmpty else { return }
        update { store in
            guard var info = store.user, info.token != token else { return }
            info.token = token
            store.user = info
        }
    }

    static func logout() {
        update { $0.user = nil }
    }

    private static func update(_ body: (inout Store) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var store = readUnlocked()
        body(&store)
        writeUnlocked(store)
    }

    private static func load() -> Store {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked()
    }

    private static func readUnlocked() -> Store {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store()
        }
        return store
    }

    private static func writeUnlocked(_ store: Store) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static var fileURL: URL? {
        AppGroupPaths.containerURL?.appendingPathComponent(fileName)
    }
}

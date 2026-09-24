import Foundation

/// 云端词库 API（对齐 iOS / 码表助手：Bearer JWT）
enum WubiCloudAPI {
    enum APIError: LocalizedError {
        case notLoggedIn
        case invalidURL
        case httpStatus(Int)
        case serverMessage(String)
        case decodeFailed
        case contentTooLarge
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .notLoggedIn: return "未登录，请先登录"
            case .invalidURL: return "请求地址无效"
            case .httpStatus(let code): return "网络错误（HTTP \(code)）"
            case .serverMessage(let msg): return msg
            case .decodeFailed: return "响应解析失败"
            case .contentTooLarge: return "同步内容超过 \(WubiCloudConfig.syncMaxContentLength) 字"
            case .emptyResponse: return "服务器无返回"
            }
        }
    }

    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool
        let message: String?
        let data: T?
    }

    private struct EmptyData: Decodable {}

    struct LoginData: Decodable {
        let uid: Int
        let email: String?
        let nickname: String?
        let token: String
    }

    // POST user/login，成功后写入本地账号
    static func login(email: String, password: String, baseURL: String = WubiCloudConfig.baseURL) async throws -> WubiCloudUserInfo {
        let url = try makeURL(base: baseURL, path: "user/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)
        applyRenewedToken(from: response)
        let envelope = try JSONDecoder().decode(Envelope<LoginData>.self, from: data)
        guard envelope.success, let login = envelope.data, !login.token.isEmpty else {
            throw APIError.serverMessage(envelope.message ?? "登录失败")
        }
        let info = WubiCloudUserInfo(
            uid: login.uid,
            email: login.email ?? email,
            nickname: login.nickname ?? "",
            token: login.token
        )
        WubiCloudConfig.baseURL = baseURL
        WubiCloudConfig.userInfo = info
        return info
    }

    struct PullData: Decodable {
        let title: String?
        let content: String?
    }

    // GET wubi/dict/pull；云端无备份时返回 nil
    static func pullDict(
        title: String = WubiCloudConfig.syncDictFileName,
        userInfo: WubiCloudUserInfo? = WubiCloudConfig.userInfo,
        baseURL: String = WubiCloudConfig.baseURL
    ) async throws -> (title: String, yaml: String)? {
        guard let userInfo, userInfo.isLoggedIn else { throw APIError.notLoggedIn }
        var components = URLComponents(url: try makeURL(base: baseURL, path: "wubi/dict/pull"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "title", value: title)]
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(userInfo, to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)
        applyRenewedToken(from: response)
        let envelope = try JSONDecoder().decode(Envelope<PullData>.self, from: data)
        guard envelope.success else {
            let msg = envelope.message ?? ""
            if msg.contains("不存在") || msg.contains("未") || msg.lowercased().contains("not found") {
                return nil
            }
            throw APIError.serverMessage(msg.isEmpty ? "拉取失败" : msg)
        }
        guard let payload = envelope.data, let yaml = payload.content, !yaml.isEmpty else {
            return nil
        }
        return (payload.title ?? title, yaml)
    }

    // PUT wubi/dict/push，正文为 YAML 原文
    static func pushDict(
        title: String = WubiCloudConfig.syncDictFileName,
        yaml: String,
        wordCount: Int,
        userInfo: WubiCloudUserInfo? = WubiCloudConfig.userInfo,
        baseURL: String = WubiCloudConfig.baseURL
    ) async throws {
        guard let userInfo, userInfo.isLoggedIn else { throw APIError.notLoggedIn }
        guard yaml.count < WubiCloudConfig.syncMaxContentLength else {
            throw APIError.contentTooLarge
        }
        let url = try makeURL(base: baseURL, path: "wubi/dict/push")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(userInfo, to: &request)
        let body: [String: Any] = [
            "title": title,
            "content": yaml,
            "contentSize": yaml.count,
            "wordCount": wordCount
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)
        applyRenewedToken(from: response)
        let envelope = try JSONDecoder().decode(Envelope<EmptyData>.self, from: data)
        guard envelope.success else {
            throw APIError.serverMessage(envelope.message ?? "上传失败")
        }
        WubiCloudConfig.lastSyncAt = Date()
    }

    /// 扩展词库词条（POST wubi/word/export-extra）
    struct ExtraWordItem: Decodable, Equatable {
        let id: Int?
        let code: String
        let word: String
        let priority: FlexibleInt?
        let comment: String?
        let category_id: Int
        let category_name: String

        var weight: Int {
            priority?.value ?? 0
        }
    }

    struct FlexibleInt: Decodable, Equatable {
        let value: Int
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) {
                value = i
            } else if let s = try? c.decode(String.self), let i = Int(s.trimmingCharacters(in: .whitespaces)) {
                value = i
            } else {
                value = 0
            }
        }
    }

    // 拉取线上扩展词库全部分类词条，只读不回写
    static func pullExtraDict(
        userInfo: WubiCloudUserInfo? = WubiCloudConfig.userInfo,
        baseURL: String = WubiCloudConfig.baseURL
    ) async throws -> [ExtraWordItem] {
        guard let userInfo, userInfo.isLoggedIn else { throw APIError.notLoggedIn }
        let url = try makeURL(base: baseURL, path: "wubi/word/export-extra")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(userInfo, to: &request)
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)
        applyRenewedToken(from: response)
        let envelope = try JSONDecoder().decode(Envelope<[ExtraWordItem]>.self, from: data)
        guard envelope.success, let list = envelope.data else {
            throw APIError.serverMessage(envelope.message ?? "拉取扩展词库失败")
        }
        return list
    }

    private static func makeURL(base: String, path: String) throws -> URL {
        let root = WubiCloudConfig.resolveBaseURL(base)
        let cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + cleaned) else { throw APIError.invalidURL }
        return url
    }

    private static func applyAuth(_ user: WubiCloudUserInfo, to request: inout URLRequest) {
        request.setValue("Bearer \(user.token)", forHTTPHeaderField: "Authorization")
    }

    private static func applyRenewedToken(from response: URLResponse) {
        guard let http = response as? HTTPURLResponse else { return }
        if let renewed = http.value(forHTTPHeaderField: "X-Access-Token"), !renewed.isEmpty {
            WubiCloudConfig.updateTokenIfNeeded(renewed)
        }
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
    }
}

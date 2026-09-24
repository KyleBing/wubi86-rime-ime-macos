import Foundation

/// 用户词双向同步与扩展词库拉取。部署由调用方触发，方便偏好面板在没有引擎时只写标记。
enum CloudDictSync {
    struct CompareOutcome {
        let summary: String
        let hasRemote: Bool
        let remoteYaml: String?
        let remoteDocument: UserDictDocument?
    }

    static func compare() async throws -> CompareOutcome {
        let local = UserDictWriter.loadActiveDocument()
        let pulled = try await WubiCloudAPI.pullDict()
        if let pulled {
            let remote = UserDictWriter.parseDocument(pulled.yaml)
            let result = DictSyncDiff.compare(local: local, remote: remote)
            return CompareOutcome(
                summary: result.summary,
                hasRemote: true,
                remoteYaml: pulled.yaml,
                remoteDocument: remote
            )
        }
        let result = DictSyncDiff.compare(local: local, remote: nil)
        return CompareOutcome(
            summary: result.summary,
            hasRemote: false,
            remoteYaml: nil,
            remoteDocument: nil
        )
    }

    static func uploadLocal() async throws -> String {
        let yaml = UserDictWriter.exportText()
        let count = UserDictWriter.loadActiveDocument().entryCount
        try await WubiCloudAPI.pushDict(yaml: yaml, wordCount: count)
        return "已上传覆盖云端（\(count) 条）"
    }

    static func download(cachedYaml: String?) async throws -> String {
        let yaml: String
        if let cachedYaml, !cachedYaml.isEmpty {
            yaml = cachedYaml
        } else if let pulled = try await WubiCloudAPI.pullDict() {
            yaml = pulled.yaml
        } else {
            throw WubiCloudAPI.APIError.serverMessage("云端尚无备份，无法下载")
        }
        try UserDictWriter.importText(yaml)
        return "已用云端覆盖本地"
    }

    static func merge(remote: UserDictDocument?) async throws -> String {
        let remoteDoc: UserDictDocument
        if let remote {
            remoteDoc = remote
        } else if let pulled = try await WubiCloudAPI.pullDict() {
            remoteDoc = UserDictWriter.parseDocument(pulled.yaml)
        } else {
            return try await uploadLocal()
        }
        let local = UserDictWriter.loadActiveDocument()
        let (merged, added) = DictSyncDiff.mergeRemoteIntoLocal(local, remote: remoteDoc)
        try UserDictWriter.saveActiveDocument(merged)
        let yaml = UserDictWriter.exportText()
        try await WubiCloudAPI.pushDict(yaml: yaml, wordCount: merged.entryCount)
        return "已合并（本地新增 \(added) 条）并上传"
    }

    // 扩展词库只拉取覆盖，返回新增条数和覆盖后的总条数
    static func pullExtra() async throws -> (added: Int, wordCount: Int) {
        let items = try await WubiCloudAPI.pullExtraDict()
        return try ExtraDictUpdater.applyOnlineItems(items)
    }
}

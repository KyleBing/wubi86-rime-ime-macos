import Darwin
import Foundation

/// 用户词双向同步与扩展词库拉取。部署由调用方触发，方便偏好面板在没有引擎时只写标记。
enum CloudDictSync {
    struct CompareOutcome {
        let diff: DictSyncDiff.Result
        let remoteYaml: String?
        let remoteDocument: UserDictDocument?

        var summary: String { diff.summary }
        var hasRemote: Bool { diff.hasRemote }
    }

    static func compare() async throws -> CompareOutcome {
        let local = UserDictWriter.loadActiveDocument()
        let pulled = try await WubiCloudAPI.pullDict()
        if let pulled {
            let remote = UserDictWriter.parseDocument(pulled.yaml)
            let result = DictSyncDiff.compare(local: local, remote: remote)
            return CompareOutcome(
                diff: result,
                remoteYaml: pulled.yaml,
                remoteDocument: remote
            )
        }
        let result = DictSyncDiff.compare(local: local, remote: nil)
        return CompareOutcome(
            diff: result,
            remoteYaml: nil,
            remoteDocument: nil
        )
    }

    static func uploadLocal() async throws -> String {
        let yaml = UserDictWriter.exportText()
        let count = UserDictWriter.loadActiveDocument().entryCount
        let revision = try await WubiCloudAPI.pushDict(yaml: yaml, wordCount: count)
        UserDictAutoSync.noteCloudRevision(revision, snapshot: UserDictWriter.loadActiveDocument())
        return "上传完成：已用本地 \(count) 条覆盖云端"
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
        let count = UserDictWriter.parseDocument(yaml).entryCount
        if let meta = try? await WubiCloudAPI.fetchMeta() {
            UserDictAutoSync.noteCloudRevision(meta.revision, snapshot: UserDictWriter.loadActiveDocument())
        }
        return "下载完成：已用云端 \(count) 条覆盖本地"
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
        let revision = try await WubiCloudAPI.pushDict(yaml: yaml, wordCount: merged.entryCount)
        UserDictAutoSync.noteCloudRevision(revision, snapshot: merged)
        if added == 0 {
            return "合并完成：没有新词条，已把本地 \(merged.entryCount) 条上传云端"
        }
        return "合并完成：并入 \(added) 条，现共 \(merged.entryCount) 条，已上传云端"
    }

    // 扩展词库只拉取覆盖，返回新增条数和覆盖后的总条数
    static func pullExtra() async throws -> (added: Int, wordCount: Int) {
        let items = try await WubiCloudAPI.pullExtraDict()
        return try ExtraDictUpdater.applyOnlineItems(items)
    }
}

/// 用户词自动同步。快照记在 Application Support，不进 Rime 词库目录。
enum UserDictAutoSync {
    // 启动时拉一次；本地改词后稍等再传；运行中定期收下其他设备的修改。
    static let launchDelay: TimeInterval = 2
    static let localEditDelay: TimeInterval = 3
    static let interval: TimeInterval = 10 * 60

    enum Tone: String, Codable {
        case success, error, attention
    }

    struct LastResult: Codable, Equatable {
        var text: String
        var tone: Tone
    }

    private struct Store: Codable {
        var enabled: Bool = false
        var last: LastResult?
    }

    private static let stateLock = NSLock()
    private static var installed = false
    private static var applying = false
    private static var running = false
    private static var pending = false
    private static var retryQueued = false
    private static var debounce: DispatchWorkItem?
    private static var timer: Timer?

    static var isEnabled: Bool {
        get { loadStore().enabled }
        set {
            var store = loadStore()
            store.enabled = newValue
            saveStore(store)
            DistributedNotificationCenter.default().post(name: .meifengAutoSyncSettingChanged, object: nil)
        }
    }

    static var lastResult: LastResult? {
        loadStore().last
    }

    static var isApplying: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return applying
    }

    // 登录后如果开关已经开着，马上补一轮。
    static func syncSoon() {
        install()
        start(delay: 0.3)
    }

    // 输入法或主 App 启动时调用。开关关闭时定时器仍在，到点会直接返回。
    static func install() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { install() }
            return
        }
        stateLock.lock()
        let already = installed
        if !already { installed = true }
        stateLock.unlock()
        guard !already else { return }

        DistributedNotificationCenter.default().addObserver(
            forName: .meifengAutoSyncSettingChanged,
            object: nil,
            queue: .main
        ) { _ in
            guard isEnabled else { return }
            start(delay: 0.3)
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            start(delay: 0)
        }
        start(delay: launchDelay)
    }

    // 本地词库刚写入。自动同步过程中的写回不从这里再排。
    static func noteLocalEdit() {
        stateLock.lock()
        let skip = applying
        stateLock.unlock()
        guard !skip, isEnabled, WubiCloudConfig.isLoggedIn else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { noteLocalEdit() }
            return
        }
        debounce?.cancel()
        let work = DispatchWorkItem { start(delay: 0) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + localEditDelay, execute: work)
    }

    private static func start(delay: TimeInterval) {
        guard isEnabled, WubiCloudConfig.isLoggedIn else { return }
        let fire = {
            if claimRun() == false { return }
            Task {
                await runOnce()
                let again = finishRun()
                if again {
                    start(delay: 0)
                }
            }
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: fire)
        } else {
            fire()
        }
    }

    private static func runOnce() async {
        guard isEnabled, WubiCloudConfig.isLoggedIn else { return }
        guard let lock = acquireLock() else {
            scheduleRetry()
            return
        }
        defer { flock(lock.fileDescriptor, LOCK_UN); try? lock.close() }
        do {
            let outcome = try await syncBody()
            record(outcome.text, tone: outcome.tone)
        } catch {
            record("自动同步失败：\(error.localizedDescription)", tone: .error)
        }
    }

    // 手动上传或下载成功后记下版本，避免下一轮自动同步再整份重拉。
    static func noteCloudRevision(_ revision: Int, snapshot: UserDictDocument) {
        guard revision > 0 else { return }
        saveRevision(revision)
        try? saveBase(snapshot)
    }

    private static func syncBody() async throws -> (text: String, tone: Tone) {
        let meta = try await WubiCloudAPI.fetchMeta()
        let savedRev = loadRevision()
        let base = loadBase()
        let local = UserDictWriter.loadActiveDocument()
        let localDirty = base.map { !sameDocument(local, $0) } ?? true
        // 云端版本没变，本地也没改：不下载正文。
        if let meta, meta.revision == savedRev, savedRev > 0, !localDirty {
            return ("自动同步：本地与云端一致", .success)
        }
        // 版本没变但本地改过：云端正文就是上次快照，不必再拉。
        if let meta, meta.revision == savedRev, savedRev > 0, let base, localDirty {
            return try await mergeAndPush(remote: base, remoteRevision: savedRev, base: base, allowRetry: true)
        }
        return try await pullMergeAndPush(allowRetry: true)
    }

    private static func pullMergeAndPush(allowRetry: Bool) async throws -> (text: String, tone: Tone) {
        let pulled = try await WubiCloudAPI.pullDict()
        let base = loadBase()
        if pulled == nil {
            let local = UserDictWriter.loadActiveDocument()
            let yaml = UserDictWriter.exportText()
            let count = local.entryCount
            let revision = try await WubiCloudAPI.pushDict(yaml: yaml, wordCount: count, baseRevision: 0)
            try saveBase(local)
            saveRevision(revision)
            return notingReload(("自动同步：云端还没有备份，已上传本地 \(count) 条", .success))
        }
        let remote = UserDictWriter.parseDocument(pulled?.yaml ?? "")
        return try await mergeAndPush(
            remote: remote,
            remoteRevision: pulled?.revision ?? 0,
            base: base,
            allowRetry: allowRetry
        )
    }

    private static func mergeAndPush(
        remote: UserDictDocument,
        remoteRevision: Int,
        base: UserDictDocument?,
        allowRetry: Bool
    ) async throws -> (text: String, tone: Tone) {
        let local = UserDictWriter.loadActiveDocument()
        let merged = DictSyncDiff.threeWayMerge(base: base, local: local, remote: remote)
        if merged.localChanged {
            setApplying(true)
            do {
                try UserDictWriter.saveActiveDocument(merged.merged)
            } catch {
                setApplying(false)
                throw error
            }
            setApplying(false)
            NotificationCenter.default.post(name: .meifengUserDictDidChange, object: nil)
        }
        var revision = remoteRevision
        if merged.needsUpload {
            let fresh = UserDictWriter.loadActiveDocument()
            // 上传前本地又被改过，这次不覆盖云端，等下一轮用新内容再合并。
            if !sameDocument(fresh, merged.merged) {
                noteLocalEdit()
                return notingReload(("自动同步：本地又有新改动，稍后重试", .attention))
            }
            let yaml = UserDictWriter.exportText()
            do {
                revision = try await WubiCloudAPI.pushDict(
                    yaml: yaml,
                    wordCount: merged.merged.entryCount,
                    baseRevision: remoteRevision
                )
            } catch WubiCloudAPI.APIError.revisionConflict {
                // 别的设备刚写过。快照先不动，再拉一次全文重新合并。
                guard allowRetry else { throw WubiCloudAPI.APIError.revisionConflict(remoteRevision) }
                return try await pullMergeAndPush(allowRetry: false)
            }
        }
        // 冲突词的快照保持旧内容，下一轮仍会标成冲突，不会被静默上传。
        try saveBase(merged.nextBase)
        if revision > 0 {
            saveRevision(revision)
        }
        return notingReload(message(for: merged))
    }

    // 本地文件比上次成功加载新（同步写回，或编辑器已经改过同一份 yaml）才通知输入法。
    // 只上传、文件没变时不部署。正在打字由输入法自己推迟。
    private static func notingReload(_ result: (text: String, tone: Tone)) -> (text: String, tone: Tone) {
        guard requestEngineReloadIfStale() else { return result }
        return (result.text + "，已重新加载用户词", result.tone)
    }

    @discardableResult
    private static func requestEngineReloadIfStale() -> Bool {
        guard let modified = userDictModificationDate() else { return false }
        if let stamp = engineReloadStamp(),
           stamp.path == UserDictWriter.activeURL.path,
           modified.timeIntervalSince1970 <= stamp.mtime + 0.01 {
            return false
        }
        UserDictWriter.markNeedsDeploy()
        DistributedNotificationCenter.default().postNotificationName(
            .meifengUserDictNeedsReload,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }

    // 输入法增量部署成功后记下文件时间和路径，避免每 10 分钟重复加载。
    static func noteEngineDidReload() {
        guard let modified = userDictModificationDate() else { return }
        guard let url = engineReloadStampURL else { return }
        AppGroupPaths.ensureDirectories()
        let body = "\(modified.timeIntervalSince1970)\n\(UserDictWriter.activeURL.path)\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func userDictModificationDate() -> Date? {
        let url = UserDictWriter.activeURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static var engineReloadStampURL: URL? {
        AppGroupPaths.containerURL?.appendingPathComponent("user-dict-engine-reload.txt")
    }

    private static func engineReloadStamp() -> (mtime: TimeInterval, path: String)? {
        guard let url = engineReloadStampURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2, let mtime = TimeInterval(lines[0]) else { return nil }
        return (mtime, lines[1])
    }

    private static func message(for merged: DictSyncDiff.ThreeWayMerge) -> (text: String, tone: Tone) {
        if !merged.conflicts.isEmpty {
            let names = merged.conflicts.prefix(3).map(\.word).joined(separator: "、")
            let suffix = merged.conflicts.count > 3 ? " 等 \(merged.conflicts.count) 条" : ""
            return ("自动同步：\(names)\(suffix) 两边都改过，已保留本地，未上传", .attention)
        }
        if merged.needsUpload && merged.tookRemote > 0 {
            return ("自动同步：已收下云端 \(merged.tookRemote) 条，并上传本地改动", .success)
        }
        if merged.needsUpload {
            return ("自动同步：已上传本地改动", .success)
        }
        if merged.tookRemote > 0 || merged.dropped > 0 {
            return ("自动同步：已更新本地，收下 \(merged.tookRemote) 条，删除 \(merged.dropped) 条", .success)
        }
        return ("自动同步：本地与云端一致", .success)
    }

    private static func sameDocument(_ lhs: UserDictDocument, _ rhs: UserDictDocument) -> Bool {
        let left = DictSyncDiff.flatten(lhs)
        let right = DictSyncDiff.flatten(rhs)
        guard left.count == right.count else { return false }
        let map = Dictionary(right.map { ($0.key, $0) }, uniquingKeysWith: { _, new in new })
        return left.allSatisfy { item in
            guard let other = map[item.key] else { return false }
            return item.priority == other.priority && item.note == other.note && item.groupName == other.groupName
        }
    }

    // 这些锁只出现在同步函数里，避免在 async 任务里直接加锁。
    private static func claimRun() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if running {
            pending = true
            return false
        }
        running = true
        return true
    }

    private static func finishRun() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        running = false
        let again = pending
        pending = false
        return again
    }

    private static func setApplying(_ value: Bool) {
        stateLock.lock()
        applying = value
        stateLock.unlock()
    }

    private static func scheduleRetry() {
        stateLock.lock()
        let queued = retryQueued
        if !queued { retryQueued = true }
        stateLock.unlock()
        guard !queued else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            stateLock.lock()
            retryQueued = false
            stateLock.unlock()
            start(delay: 0)
        }
    }

    private static func record(_ text: String, tone: Tone) {
        var store = loadStore()
        store.last = LastResult(text: text, tone: tone)
        saveStore(store)
        DistributedNotificationCenter.default().post(name: .meifengAutoSyncDidFinish, object: nil)
    }

    private static func acquireLock() -> FileHandle? {
        guard let root = AppGroupPaths.containerURL else { return nil }
        let url = root.appendingPathComponent("user-dict-sync.lock")
        AppGroupPaths.ensureDirectories()
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        guard let handle = try? FileHandle(forUpdating: url) else { return nil }
        if flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            try? handle.close()
            return nil
        }
        return handle
    }

    private static func loadBase() -> UserDictDocument? {
        guard let url = baseURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UserDictWriter.loadDocument(from: url)
    }

    private static func loadRevision() -> Int {
        guard let url = revisionURL,
              let text = try? String(contentsOf: url, encoding: .utf8),
              let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
        return value
    }

    private static func saveRevision(_ revision: Int) {
        guard let url = revisionURL, revision > 0 else { return }
        AppGroupPaths.ensureDirectories()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? String(revision).write(to: url, atomically: true, encoding: .utf8)
    }

    private static var revisionURL: URL? {
        baseURL?.appendingPathExtension("rev")
    }

    private static func saveBase(_ document: UserDictDocument) throws {
        guard let url = baseURL else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try UserDictWriter.saveDocument(document, to: url, markDeploy: false)
    }

    // 按词库路径分开快照，换目录后不沿用另一份词库的基线。
    private static var baseURL: URL? {
        guard let root = AppGroupPaths.containerURL else { return nil }
        let encoded = Data(UserDictWriter.activeURL.path.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return root
            .appendingPathComponent("sync-base", isDirectory: true)
            .appendingPathComponent(encoded + ".yaml")
    }

    private static var storeURL: URL? {
        AppGroupPaths.containerURL?.appendingPathComponent("user-dict-auto-sync.json")
    }

    private static func loadStore() -> Store {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Store()
        }
        return store
    }

    private static func saveStore(_ store: Store) {
        guard let url = storeURL, let data = try? JSONEncoder().encode(store) else { return }
        AppGroupPaths.ensureDirectories()
        try? data.write(to: url, options: .atomic)
    }
}

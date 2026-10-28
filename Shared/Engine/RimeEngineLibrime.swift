import Foundation

/// 基于 librime 的引擎实现（无 Lua）
final class RimeEngineLibrime: RimeEngine {
    private let bridge = RimeBridge.shared()
    private(set) var isReady = false

    func start(forceFullCheck: Bool) throws {
        guard let dirs = RimeResourceDeployer.syncBundledResourcesIfNeeded() else {
            throw NSError(domain: "RimeEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少内置 Rime 资源"])
        }
        // 共享目录单独指向内置预设，避免用户目录没有 default.yaml 时编译不出方案
        let shared = RimeResourceDeployer.resolveSharedDataURL() ?? dirs.user
        RimeResourceDeployer.ensureMissingImportedDicts(at: dirs.user)
        // 关掉方案里旧的 auto_select 后需要重新编译，否则本轮仍会四码唯一自动上屏
        let force = forceFullCheck || UserDictWriter.peekNeedsDeploy()
        try bridge.start(
            withSharedDir: shared.path,
            userDir: dirs.user.path,
            forceFullCheck: force
        )
        if force {
            _ = UserDictWriter.consumeNeedsDeploy()
        }
        // 不强制切换方案，使用该目录 schema_list 里的默认方案
        isReady = true
    }

    func stop() {
        bridge.shutdown()
        isReady = false
    }

    // 全量部署已经 finalize 全局 API，这里只丢掉失效会话，交给 start 重新拉起。
    func noteExternalShutdown() {
        bridge.noteAPIShutdown()
        isReady = false
    }

    func processKey(_ keyCode: Int32, modifiers: Int32) -> Bool {
        bridge.processKey(keyCode, modifiers: modifiers)
    }

    func inputSchema(_ schemaId: String) -> Bool {
        bridge.selectSchema(schemaId)
    }

    func candidates(limit: Int) -> [RimeCandidate] {
        guard let snap = bridge.currentContext() else { return [] }
        return snap.candidates.prefix(limit).map {
            RimeCandidate(text: $0.text, comment: $0.comment ?? "")
        }
    }

    func commitText() -> String? {
        bridge.currentContext()?.commitText
    }

    func clearComposition() {
        bridge.clearComposition()
    }

    // MARK: - 扩展能力

    func snapshot() -> RimeContextSnapshot? {
        bridge.currentContext()
    }

    // 只读组字状态，不取待上屏文字；四码判定时不能吞掉 commit
    func peekSnapshot() -> RimeContextSnapshot? {
        bridge.currentContextPeeking()
    }

    // 原始按键序列。反查的 preedit 可能已经去掉前缀 z，不能用来判断是不是反查。
    func rawInput() -> String {
        bridge.rawInput() ?? ""
    }

    func selectCandidate(index: Int) -> Bool {
        bridge.selectCandidate(at: Int32(index))
    }

    func selectCandidateAbsolute(index: Int) -> Bool {
        bridge.selectCandidateAbsoluteIndex(Int32(index))
    }

    func changePage(backward: Bool) -> Bool {
        bridge.changePage(backward)
    }

    func allCandidateTexts() -> [String] {
        bridge.allCandidates().map(\.text)
    }

    func redeploy() -> Bool {
        let ready = bridge.deploy()
        // 会话重建失败后必须同步失效，避免上层继续把空会话当成可用。
        isReady = ready
        return ready
    }
}

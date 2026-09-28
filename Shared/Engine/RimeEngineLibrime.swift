import Foundation

/// 基于 librime 的引擎实现（无 Lua）
final class RimeEngineLibrime: RimeEngine {
    private let bridge = RimeBridge.shared()
    private(set) var isReady = false

    func start(forceFullCheck: Bool) throws {
        guard let dirs = RimeResourceDeployer.syncBundledResourcesIfNeeded() else {
            throw NSError(domain: "RimeEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少内置 Rime 资源"])
        }
        try bridge.start(
            withSharedDir: dirs.shared.path,
            userDir: dirs.user.path,
            forceFullCheck: forceFullCheck
        )
        _ = bridge.selectSchema(RimeResourceDeployer.schemaId)
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

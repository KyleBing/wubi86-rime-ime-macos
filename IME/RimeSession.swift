import Foundation

/// 进程内共享的 Rime 会话（输入法扩展生命周期内复用）
final class RimeSession {
    static let shared = RimeSession()

    private let engine = RimeEngineLibrime()
    private let lock = NSLock()
    private(set) var started = false

    /// 是否缺少编译产物，需要全量 deploy
    private var needsFullBuild: Bool {
        let user = RimeResourceDeployer.resolveUserDataURL()
        let table = user.appendingPathComponent("build/wubi86_jidian.table.bin")
        return !FileManager.default.fileExists(atPath: table.path)
    }

    @discardableResult
    func ensureStarted(forceFullCheck: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let force = forceFullCheck || needsFullBuild
        if started, engine.isReady {
            if UserDictWriter.consumeNeedsDeploy() || needsFullBuild {
                NSLog("[MeifengWubi] redeploy rime (needsFull=%d)", needsFullBuild)
                _ = engine.redeploy()
            }
            return true
        }
        do {
            // 首次或无 build 产物时强制全量编译
            try engine.start(forceFullCheck: force)
            started = true
            NSLog("[MeifengWubi] rime started forceFull=%d user=%@", force, RimeResourceDeployer.resolveUserDataURL().path)
            return true
        } catch {
            NSLog("[MeifengWubi] Rime start failed: %@", error.localizedDescription)
            started = false
            return false
        }
    }

    func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        engine.stop()
        started = false
    }

    var bridgeEngine: RimeEngineLibrime { engine }
}

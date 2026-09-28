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

    /// 造词后重载用户词。走进程内增量部署，不 finalize 正在用的 librime。
    @discardableResult
    func reloadUserDictionary() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _ = UserDictWriter.consumeNeedsDeploy()
        if started, engine.isReady {
            if engine.redeploy() {
                NSLog("[MeifengWubi] user dict reloaded")
                return true
            }
            NSLog("[MeifengWubi] user dict redeploy failed, restarting")
            engine.noteExternalShutdown()
            started = false
        }
        return startLocked(forceFullCheck: false)
    }

    /// `deployNow` 会 finalize 全局 librime。输入法进程里调用后必须重建，否则菜单还在但按键无效。
    @discardableResult
    func restartAfterExternalDeploy() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _ = UserDictWriter.consumeNeedsDeploy()
        engine.noteExternalShutdown()
        started = false
        return startLocked(forceFullCheck: false)
    }

    private func startLocked(forceFullCheck: Bool) -> Bool {
        do {
            try engine.start(forceFullCheck: forceFullCheck)
            started = true
            NSLog("[MeifengWubi] rime restarted forceFull=%d", forceFullCheck ? 1 : 0)
            return true
        } catch {
            NSLog("[MeifengWubi] rime restart failed: %@", error.localizedDescription)
            started = false
            return false
        }
    }

    var bridgeEngine: RimeEngineLibrime { engine }
}

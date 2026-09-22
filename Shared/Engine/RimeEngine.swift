import Foundation

/// Rime 引擎抽象；M1-M2 使用 Stub，M3 起接 librime
protocol RimeEngine: AnyObject {
    var isReady: Bool { get }
    func start() throws
    /// 用户词等变更后传 true；日常打开键盘应 false，避免扩展内重编大词库
    func start(forceFullCheck: Bool) throws
    func stop()
    func processKey(_ keyCode: Int32, modifiers: Int32) -> Bool
    func inputSchema(_ schemaId: String) -> Bool
    func candidates(limit: Int) -> [RimeCandidate]
    func commitText() -> String?
    func clearComposition()
}

extension RimeEngine {
    func start() throws {
        try start(forceFullCheck: false)
    }
}

struct RimeCandidate: Equatable {
    let text: String
    let comment: String
}

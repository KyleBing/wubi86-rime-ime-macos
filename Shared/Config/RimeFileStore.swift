import Foundation

/// 清空用户 Rime 目录（复位用）
enum RimeFileStore {
    static var rootURL: URL {
        RimeResourceDeployer.resolveUserDataURL()
    }

    @discardableResult
    static func clearAll() throws -> Int {
        let root = rootURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return 0 }
        let items = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var count = 0
        for item in items {
            try fm.removeItem(at: item)
            count += 1
        }
        return count
    }
}

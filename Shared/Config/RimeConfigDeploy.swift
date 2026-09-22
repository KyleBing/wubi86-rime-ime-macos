import Foundation

/// Swift 侧封装：按当前配置目录部署 Rime，并通知键盘扩展重载会话
enum RimeConfigDeploy {
    enum Result {
        case success
        case failure(String)
    }

    /// 基于 `RimeResourceDeployer.resolveUserDataURL()` 全量部署
    static func deployNow() -> Result {
        let userURL = RimeResourceDeployer.resolveUserDataURL()
        // 上传整个文件夹时常多一层目录，先尝试提升到根
        _ = RimeFileLayout.flattenNestedSchemeIfNeeded(at: userURL)
        if let problem = RimeFileLayout.validateSchemeRoot(at: userURL) {
            return .failure(problem)
        }
        do {
            try RimeMaintenanceDeployer.deploy(withSharedDir: userURL.path, userDir: userURL.path)
            // 部署后检查是否产出了方案编译结果
            let build = userURL.appendingPathComponent("build", isDirectory: true)
            let hasTable = FileManager.default.fileExists(
                atPath: build.appendingPathComponent("wubi86_jidian.table.bin").path
            )
            let hasSchemaBuild = FileManager.default.fileExists(
                atPath: build.appendingPathComponent("wubi86_jidian.schema.yaml").path
            )
            if !hasTable && !hasSchemaBuild {
                return .failure("部署完成但未生成词库，请点「复位原始配置」后重试")
            }
            // 键盘扩展下次出现时整引擎重启
            UserDictWriter.markNeedsDeploy()
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// 清空目录 → 恢复内置全部文件 → 立即部署（真正复位）
    static func resetToFactory() -> Result {
        do {
            _ = try RimeFileStore.clearAll()
            _ = try RimeResourceDeployer.forceSyncBundledResources(overwriteUserDict: true)
            // 清完后必须全量部署，否则键盘无候选
            return deployNow()
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

/// 配置目录布局检查 / 修正（上传整夹时常见多一层）
enum RimeFileLayout {
    /// 根目录缺少 schema，但唯一子目录里有 → 把该子目录内容提升到根
    @discardableResult
    static func flattenNestedSchemeIfNeeded(at root: URL) -> Bool {
        let fm = FileManager.default
        let schemaName = RimeResourceDeployer.schemaFileName
        let rootSchema = root.appendingPathComponent(schemaName)
        if fm.fileExists(atPath: rootSchema.path) { return false }

        guard let items = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        var candidates: [URL] = []
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            guard isDir else { continue }
            let nested = item.appendingPathComponent(schemaName)
            if fm.fileExists(atPath: nested.path) {
                candidates.append(item)
            }
        }
        // 仅当恰好一个子目录含方案时自动提升，避免误伤
        guard candidates.count == 1, let src = candidates.first else { return false }

        guard let children = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else {
            return false
        }
        for child in children {
            let dest = root.appendingPathComponent(child.lastPathComponent)
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: child, to: dest)
        }
        try? fm.removeItem(at: src)
        return true
    }

    /// 部署前检查：必须能在根目录找到本 App 使用的 schema
    static func validateSchemeRoot(at root: URL) -> String? {
        let schema = root.appendingPathComponent(RimeResourceDeployer.schemaFileName)
        if FileManager.default.fileExists(atPath: schema.path) { return nil }

        if let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                guard isDir else { continue }
                let nested = item.appendingPathComponent(RimeResourceDeployer.schemaFileName)
                if FileManager.default.fileExists(atPath: nested.path) {
                    return "方案在子目录「\(item.lastPathComponent)」内，根目录缺少 \(RimeResourceDeployer.schemaFileName)。请重新上传目录内文件，或点「复位原始配置」。"
                }
            }
        }
        return "缺少 \(RimeResourceDeployer.schemaFileName)，无法出候选。请点「复位原始配置」恢复内置方案后再部署。"
    }
}

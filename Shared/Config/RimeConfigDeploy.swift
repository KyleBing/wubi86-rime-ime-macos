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
        // 缺方案时补内置文件；已有主码表不覆盖
        _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
        if let problem = RimeFileLayout.validateSchemeRoot(at: userURL) {
            return .failure(problem)
        }
        do {
            // 用户自己的 Rime 目录同时作为共享目录和用户目录，沿用其中的方案与词库
            try RimeMaintenanceDeployer.deploy(withSharedDir: userURL.path, userDir: userURL.path)
            let build = userURL.appendingPathComponent("build", isDirectory: true)
            let compiled = (try? FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? []
            let hasSchemaBuild = compiled.contains { $0.lastPathComponent.hasSuffix(".schema.yaml") }
            if !hasSchemaBuild {
                return .failure("部署完成但没有编译出方案，请确认目录里有可用的 .schema.yaml")
            }
            // 键盘扩展下次出现时整引擎重启
            UserDictWriter.markNeedsDeploy()
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// 改选 Rime 目录：把当前目录里新目录没有的文件拷过去（不覆盖已有），再切换并部署。
    /// - Parameter newURL: nil 表示恢复默认目录
    static func changeUserDataDirectory(to newURL: URL?) -> Result {
        let fm = FileManager.default
        let oldURL = RimeResourceDeployer.resolveUserDataURL().standardizedFileURL
        guard let target = (newURL ?? AppGroupPaths.defaultRimeUserDataURL)?.standardizedFileURL else {
            return .failure("无法确定目标目录")
        }
        if target == oldURL {
            return .success
        }
        // 选到当前目录的子目录会把自己拷进自己
        if target.path.hasPrefix(oldURL.path + "/") {
            return .failure("不能选择当前词库目录内的子目录")
        }
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            guard fm.isWritableFile(atPath: target.path) else {
                return .failure("目录不可写：\(target.path)")
            }
            // 目标目录已有方案时保持原样。空目录才从当前目录补缺少的文件。
            if !RimeResourceDeployer.containsSchemaFile(at: target) {
                let items = try fm.contentsOfDirectory(at: oldURL, includingPropertiesForKeys: nil)
                for item in items where item.lastPathComponent != "build" {
                    let dest = target.appendingPathComponent(item.lastPathComponent)
                    if !fm.fileExists(atPath: dest.path) {
                        try fm.copyItem(at: item, to: dest)
                    }
                }
            }
            try AppGroupPaths.setCustomRimeUserDataURL(newURL)
        } catch {
            return .failure(error.localizedDescription)
        }
        _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
        return deployNow()
    }

    /// 清空目录 → 恢复内置全部文件 → 立即部署（真正复位）
    static func resetToFactory() -> Result {
        do {
            _ = try RimeFileStore.clearAll()
            _ = try RimeResourceDeployer.forceSyncBundledResources(overwriteUserDict: true)
            // 复位后按当前行为偏好重写 custom.yaml
            if let err = RimeBehaviorPrefs.persist() {
                return .failure(err)
            }
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

    /// 部署前检查：根目录里要有任意一份方案
    static func validateSchemeRoot(at root: URL) -> String? {
        if RimeResourceDeployer.containsSchemaFile(at: root) { return nil }

        if let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                guard isDir else { continue }
                if RimeResourceDeployer.containsSchemaFile(at: item) {
                    return "方案在子目录「\(item.lastPathComponent)」内，请改选该目录本身。"
                }
            }
        }
        return "目录里没有 Rime 方案（.schema.yaml），无法部署。"
    }
}

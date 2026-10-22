import AppKit
import SwiftUI

/// 「程序更新」区块的状态：只在 Sparkle 未启用时使用。
@MainActor
final class UpdateModel: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate(String)
        case available(UpdateManifest)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var autoCheck: Bool {
        didSet { UpdateChecker.autoCheckEnabled = autoCheck }
    }

    private var didAutoCheck = false
    private var isAutomaticCheck = false

    init() {
        autoCheck = UpdateChecker.autoCheckEnabled
    }

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    // 每次启动只尝试一次；间隔由 UpdateChecker 的 24 小时节流控制
    func autoCheckOnLaunch() {
        guard !didAutoCheck else { return }
        didAutoCheck = true
        guard autoCheck, UpdateChecker.isAutoCheckDue else { return }
        check(automatic: true)
    }

    func check(automatic: Bool = false) {
        guard !isChecking else { return }
        isAutomaticCheck = automatic
        state = .checking
        UpdateChecker.check { [weak self] result in
            Task { @MainActor in self?.apply(result) }
        }
    }

    // 自动提示时跳过这一版；手动检查仍然能看到
    func skip() {
        guard case .available(let manifest) = state else { return }
        UpdateChecker.skippedVersion = manifest.version
        state = .upToDate(UpdateChecker.currentVersion)
    }

    func openDownloadPage() {
        guard case .available(let manifest) = state else { return }
        let raw = manifest.downloadURL
        guard let raw, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func apply(_ result: UpdateCheckResult) {
        switch result {
        case .newer(let manifest):
            // 用户明确跳过过这一版时，自动检查不再打扰；手动检查仍会显示
            let skipped = isAutomaticCheck && UpdateChecker.skippedVersion == manifest.version
            state = skipped ? .upToDate(UpdateChecker.currentVersion) : .available(manifest)
        case .upToDate(let version):
            state = .upToDate(version)
        case .failed(let message):
            state = .failed(message)
        }
        isAutomaticCheck = false
    }
}

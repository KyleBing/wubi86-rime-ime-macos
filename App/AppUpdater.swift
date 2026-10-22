import Foundation
import Sparkle

/// Sparkle 自动更新。只有 Info.plist 里配了 EdDSA 公钥的正式包才启用；
/// 开发包 / 未配密钥的构建退回清单检查 + 打开下载页，不会因为缺公钥而报错。
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private var controller: SPUStandardUpdaterController?

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // startingUpdater 为 true 时 Sparkle 会按 Info.plist 的间隔自动检查
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

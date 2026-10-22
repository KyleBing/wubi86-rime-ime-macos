import SwiftUI

@main
struct MeifengWubiApp: App {
    @State private var openPrefs = false

    init() {
        // 启动时就创建 Sparkle 控制器：它负责按 Info.plist 的间隔定时检查，
        // 只放在设置窗口里会变成「打开设置才检查」
        _ = AppUpdater.shared
    }

    var body: some Scene {
        WindowGroup {
            SetupView(preferOpenCandidatePrefs: $openPrefs)
                .onOpenURL { url in
                    if url.host == "prefs" || url.path.contains("prefs") {
                        openPrefs = true
                    }
                }
        }
        .windowResizability(.contentSize)

        // 系统「设置」菜单 / 标准偏好窗口
        Settings {
            CandidatePrefsView()
                .frame(
                    minWidth: IMESettingsControls.minWindowSize.width,
                    idealWidth: IMESettingsControls.preferredWindowSize.width,
                    maxWidth: .infinity,
                    minHeight: IMESettingsControls.minWindowSize.height,
                    idealHeight: IMESettingsControls.preferredWindowSize.height,
                    maxHeight: .infinity
                )
        }
    }
}

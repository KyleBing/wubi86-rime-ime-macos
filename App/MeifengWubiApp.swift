import SwiftUI

@main
struct MeifengWubiApp: App {
    @State private var openPrefs = false

    var body: some Scene {
        WindowGroup {
            SetupView(preferOpenCandidatePrefs: $openPrefs)
                // 主窗口按内容宽度收缩，避免空白两侧过宽。
                .frame(width: 420)
                // 内容已放入滚动视图，窗口高度可在最小值之上自由调整
                .frame(minHeight: 520, idealHeight: 760, maxHeight: .infinity)
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

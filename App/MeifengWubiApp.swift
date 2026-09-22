import SwiftUI

@main
struct MeifengWubiApp: App {
    @State private var openPrefs = false

    var body: some Scene {
        WindowGroup {
            SetupView(preferOpenCandidatePrefs: $openPrefs)
                .frame(minWidth: 560, minHeight: 480)
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
                .frame(width: 440, height: 320)
        }
    }
}

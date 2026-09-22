import PreferencePanes
import AppKit

/// 放入 IME.app/Contents/Resources/Preferences.prefPane，供「系统设置 → 键盘 → 输入法」加载
@objc(MeifengPreferencesPane)
final class MeifengPreferencesPane: NSPreferencePane {
    override func loadMainView() -> NSView {
        let view = IMESettingsControls.makeFormView(width: 468)
        mainView = view
        return view
    }
}

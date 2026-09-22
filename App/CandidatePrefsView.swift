import AppKit
import SwiftUI

/// 主 App 直接承载共享 AppKit 设置页，保证与输入法入口完全一致。
struct CandidatePrefsView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        IMESettingsControls.makeFormView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

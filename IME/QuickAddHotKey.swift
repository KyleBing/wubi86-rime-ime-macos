import AppKit
import Carbon

/// 在输入法进程注册全局造词热键，设置变更后重新注册。
enum QuickAddHotKey {
    private static var hotKeyRef: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    private static var installed = false

    static func install() {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async {
                    // 面板获得焦点后原应用可能清掉选区，先取出完整文本。
                    let selectedText = MeifengInputController.selectedTextFromActiveClient()
                    QuickAddWordPanel.shared.showPanel(prefill: selectedText)
                }
                return noErr
            }, 1, &spec, nil, &handler)
            installed = true
            DistributedNotificationCenter.default().addObserver(
                forName: QuickAddPrefs.changedNotification,
                object: nil,
                queue: .main
            ) { _ in
                registerCurrent()
            }
        }
        registerCurrent()
    }

    private static func registerCurrent() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D46_5742), id: 1)
        let status = RegisterEventHotKey(
            QuickAddPrefs.keyCode,
            QuickAddPrefs.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("[MeifengWubi] 造词热键注册失败 status=%d", status)
        }
    }
}

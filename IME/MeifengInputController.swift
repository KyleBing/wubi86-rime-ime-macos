import AppKit
import Carbon
import InputMethodKit

/// 玫枫五笔 IMK 控制器：inline preedit + 非激活候选条
@objc(MeifengInputController)
final class MeifengInputController: IMKInputController {
    private let panel = CandidatePanelController()
    private var currentClient: (any IMKTextInput)?
    private var asciiMode = false
    private var shiftIsSticky = false
    private var sawOtherKeyWithShift = false

    private func log(_ msg: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MeifengWubi-ime.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url)
            }
        }
        NSLog("[MeifengWubi] %@", msg)
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        currentClient = inputClient as? IMKTextInput
        log("init controller client=\(String(describing: inputClient))")
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // 必须声明，否则部分系统路径不会把按键交给 handle
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        currentClient = (sender as? IMKTextInput) ?? (client() as? IMKTextInput)
        let ok = RimeSession.shared.ensureStarted()
        log("activateServer rime=\(ok) client=\(currentClient != nil)")
    }

    override func deactivateServer(_ sender: Any!) {
        commitOrClearPending()
        panel.hide()
        clearMarkedText()
        super.deactivateServer(sender)
        log("deactivateServer")
    }

    override func hidePalettes() {
        panel.hide()
        super.hidePalettes()
    }

    override func commitComposition(_ sender: Any!) {
        commitOrClearPending(forceCommitRaw: true)
        panel.hide()
        clearMarkedText()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        currentClient = (sender as? IMKTextInput) ?? currentClient

        if event.type == .flagsChanged {
            return handleFlagsChanged(event)
        }
        guard event.type == .keyDown else { return false }

        if event.modifierFlags.contains(.shift) {
            sawOtherKeyWithShift = true
        }

        // 有 Command 交给系统
        if event.modifierFlags.contains(.command) {
            return false
        }

        guard RimeSession.shared.ensureStarted() else {
            log("handle: rime not ready")
            return false
        }

        // 数字选词
        if let snap = RimeSession.shared.bridgeEngine.snapshot(),
           snap.isComposing,
           let chars = event.charactersIgnoringModifiers,
           let ch = chars.first,
           ch >= "1", ch <= "9" {
            let idx = Int(String(ch))! - 1
            if idx < snap.candidates.count {
                return selectCandidate(index: idx)
            }
        }

        if asciiMode {
            return false
        }

        guard let mapped = MacKeyMapper.map(event: event) else {
            return false
        }

        let handled = RimeSession.shared.bridgeEngine.processKey(mapped.keyCode, modifiers: mapped.modifiers)
        log("key=\(mapped.keyCode) handled=\(handled) chars=\(event.characters ?? "")")
        if handled {
            return consumeRimeUpdate()
        }
        if RimeSession.shared.bridgeEngine.snapshot()?.isComposing == true {
            return true
        }
        return false
    }

    // MARK: - Private

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shiftDown = flags.contains(.shift)
        if shiftDown {
            sawOtherKeyWithShift = false
            shiftIsSticky = true
            return false
        }
        if shiftIsSticky, !sawOtherKeyWithShift {
            asciiMode.toggle()
            log("asciiMode=\(asciiMode)")
            if asciiMode {
                commitOrClearPending(forceCommitRaw: true)
                panel.hide()
                clearMarkedText()
            }
            shiftIsSticky = false
            return true
        }
        shiftIsSticky = false
        return false
    }

    @discardableResult
    private func consumeRimeUpdate() -> Bool {
        let engine = RimeSession.shared.bridgeEngine
        guard let snap = engine.snapshot() else { return true }

        if let commit = snap.commitText, !commit.isEmpty {
            insertText(commit)
            clearMarkedText()
        }

        let preedit = snap.preedit ?? ""
        let special = DateTimeCandidates.candidates(for: preedit)
        let texts: [String] = special ?? snap.candidates.map(\.text)

        log("update preedit=\(preedit) candidates=\(texts.prefix(5).joined(separator: ",")) composing=\(snap.isComposing)")

        if snap.isComposing || !texts.isEmpty {
            setMarkedText(preedit)
            showCandidates(texts, preedit: preedit)
        } else {
            panel.hide()
            if snap.commitText == nil || snap.commitText?.isEmpty == true {
                clearMarkedText()
            }
        }
        return true
    }

    private func selectCandidate(index: Int) -> Bool {
        let engine = RimeSession.shared.bridgeEngine
        let preedit = engine.snapshot()?.preedit ?? ""
        if let special = DateTimeCandidates.candidates(for: preedit),
           special.indices.contains(index) {
            insertText(special[index])
            engine.clearComposition()
            panel.hide()
            clearMarkedText()
            return true
        }
        guard engine.selectCandidate(index: index) else { return true }
        return consumeRimeUpdate()
    }

    private func showCandidates(_ texts: [String], preedit: String) {
        guard !texts.isEmpty || !preedit.isEmpty else {
            panel.hide()
            return
        }
        let origin = caretScreenOrigin()
        panel.show(candidates: Array(texts.prefix(IMEAppearancePrefs.pageSize)), preedit: preedit, origin: origin) { [weak self] idx in
            _ = self?.selectCandidate(index: idx)
        }
    }

    private func caretScreenOrigin() -> NSPoint {
        guard let client = currentClient ?? (client() as? IMKTextInput) else {
            return NSEvent.mouseLocation
        }
        var rect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        if rect.origin.x == 0, rect.origin.y == 0, rect.width == 0 {
            return NSEvent.mouseLocation
        }
        return rect.origin
    }

    private func insertText(_ string: String) {
        guard let client = currentClient ?? (client() as? IMKTextInput) else {
            log("insertText FAILED no client: \(string)")
            return
        }
        client.insertText(string, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func setMarkedText(_ string: String) {
        guard let client = currentClient ?? (client() as? IMKTextInput) else {
            log("setMarkedText FAILED no client: \(string)")
            return
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let marked = NSAttributedString(string: string, attributes: attrs)
        client.setMarkedText(
            marked,
            selectionRange: NSRange(location: string.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    private func clearMarkedText() {
        guard let client = currentClient ?? (client() as? IMKTextInput) else { return }
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    private func commitOrClearPending(forceCommitRaw: Bool = false) {
        let engine = RimeSession.shared.bridgeEngine
        guard RimeSession.shared.started else { return }
        if let snap = engine.snapshot() {
            if let commit = snap.commitText, !commit.isEmpty {
                insertText(commit)
            } else if forceCommitRaw, let preedit = snap.preedit, !preedit.isEmpty {
                insertText(preedit.filter { $0.isLetter || $0.isNumber })
            }
        }
        engine.clearComposition()
    }

    @objc private func inputSourceChanged() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let ptr = TISGetInputSourceProperty(current, kTISPropertyBundleID)
        let currentId = ptr.map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
        if currentId != bundleId {
            commitOrClearPending(forceCommitRaw: true)
            panel.hide()
            clearMarkedText()
        }
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "玫枫五笔")

        let mode = NSMenuItem(
            title: asciiMode ? "切换到中文" : "切换到英文",
            action: #selector(toggleAscii),
            keyEquivalent: ""
        )
        mode.target = self
        menu.addItem(mode)
        menu.addItem(.separator())

        // 候选方向（对齐系统输入法菜单快捷项）
        let orient = NSMenuItem(title: "候选方向", action: nil, keyEquivalent: "")
        let orientMenu = NSMenu(title: "候选方向")
        let hItem = NSMenuItem(title: "水平", action: #selector(setOrientationHorizontal), keyEquivalent: "")
        hItem.target = self
        hItem.state = IMEAppearancePrefs.orientation == .horizontal ? .on : .off
        let vItem = NSMenuItem(title: "垂直", action: #selector(setOrientationVertical), keyEquivalent: "")
        vItem.target = self
        vItem.state = IMEAppearancePrefs.orientation == .vertical ? .on : .off
        orientMenu.addItem(hItem)
        orientMenu.addItem(vItem)
        orient.submenu = orientMenu
        menu.addItem(orient)

        let larger = NSMenuItem(title: "增大字号", action: #selector(increaseFont), keyEquivalent: "")
        larger.target = self
        menu.addItem(larger)
        let smaller = NSMenuItem(title: "减小字号", action: #selector(decreaseFont), keyEquivalent: "")
        smaller.target = self
        menu.addItem(smaller)
        menu.addItem(.separator())

        // showPreferences: 由 IMK 调用 PreferencesWindowController
        let prefs = NSMenuItem(
            title: "玫枫五笔设置…",
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        menu.addItem(prefs)
        return menu
    }

    @objc private func toggleAscii() {
        asciiMode.toggle()
        if asciiMode {
            commitOrClearPending(forceCommitRaw: true)
            panel.hide()
            clearMarkedText()
        }
    }

    @objc private func setOrientationHorizontal() {
        IMEAppearancePrefs.orientation = .horizontal
    }

    @objc private func setOrientationVertical() {
        IMEAppearancePrefs.orientation = .vertical
    }

    @objc private func increaseFont() {
        IMEAppearancePrefs.fontSize = min(24, IMEAppearancePrefs.fontSize + 1)
    }

    @objc private func decreaseFont() {
        IMEAppearancePrefs.fontSize = max(11, IMEAppearancePrefs.fontSize - 1)
    }

}

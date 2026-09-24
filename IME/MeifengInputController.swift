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
    // 预置候选（date / time）由输入法自行分页，记录当前页与所属编码。
    private var specialPage = 0
    private var specialPreedit = ""
    // 强引用，避免设置窗口闪一下被释放
    private var preferencesWindowController: MeifengPreferencesWindowController?

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

        // 预置候选不在 Rime 菜单里，选词 / 翻页键需自行处理。
        if !asciiMode, let handled = handleSpecialCandidateKey(event) {
            return handled
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

    // 当前编码命中预置候选时，按设置里的选词 / 翻页键操作；返回 nil 表示交给 Rime 继续处理。
    private func handleSpecialCandidateKey(_ event: NSEvent) -> Bool? {
        guard let snap = RimeSession.shared.bridgeEngine.snapshot(),
              snap.isComposing,
              let preedit = snap.preedit,
              let special = DateTimeCandidates.candidates(for: preedit),
              !special.isEmpty,
              event.modifierFlags.intersection([.control, .option]).isEmpty,
              let ch = event.charactersIgnoringModifiers?.first else {
            return nil
        }
        let pageSize = IMEAppearancePrefs.pageSize
        let pageCount = (special.count + pageSize - 1) / pageSize
        syncSpecialPage(preedit: preedit)

        // 选中当前页第 n 个（0 起）。
        func pick(_ n: Int) -> Bool {
            let index = specialPage * pageSize + n
            guard n < pageSize, special.indices.contains(index) else { return true }
            commitSpecial(special[index])
            return true
        }

        // 翻页到头 / 到尾即停，不循环。
        func turn(_ delta: Int) -> Bool {
            let target = min(max(specialPage + delta, 0), pageCount - 1)
            if target != specialPage {
                specialPage = target
                showCandidates(special, preedit: preedit)
            }
            return true
        }

        if let digit = ch.wholeNumberValue, (1...9).contains(digit) {
            return pick(digit - 1)
        }
        if ch == " " {
            return pick(0)
        }
        if RimeBehaviorPrefs.secondThirdKeys == .semicolonApostrophe {
            if ch == ";" { return pick(1) }
            if ch == "'" { return pick(2) }
        }

        let paging = RimeBehaviorPrefs.pagingKeys
        let minusEqual = paging == .minusEqual || paging == .minusAndComma
        let commaPeriod = paging == .commaPeriod || paging == .minusAndComma
        let brackets = paging == .brackets
        switch ch {
        case "-" where minusEqual, "," where commaPeriod, "[" where brackets:
            return turn(-1)
        case "=" where minusEqual, "." where commaPeriod, "]" where brackets:
            return turn(1)
        default:
            break
        }
        // PageUp / PageDown 也可翻页。
        switch Int(event.keyCode) {
        case kVK_PageUp:
            return turn(-1)
        case kVK_PageDown:
            return turn(1)
        default:
            return nil
        }
    }

    // 编码变化时回到预置候选第一页。
    private func syncSpecialPage(preedit: String) {
        if preedit != specialPreedit {
            specialPreedit = preedit
            specialPage = 0
        }
    }

    // 预置候选上屏并清空 Rime 编码。
    private func commitSpecial(_ text: String) {
        insertText(text)
        RimeSession.shared.bridgeEngine.clearComposition()
        panel.hide()
        clearMarkedText()
        specialPreedit = ""
        specialPage = 0
    }

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
        if let special = DateTimeCandidates.candidates(for: preedit) {
            // index 为当前页内序号，换算到整张预置列表。
            syncSpecialPage(preedit: preedit)
            let absolute = specialPage * IMEAppearancePrefs.pageSize + index
            if special.indices.contains(absolute) {
                commitSpecial(special[absolute])
            }
            return true
        }
        guard engine.selectCandidate(index: index) else { return true }
        return consumeRimeUpdate()
    }

    private func showCandidates(_ texts: [String], preedit: String) {
        // 没有候选时只保留编码下划线，不弹出空候选窗。
        guard !texts.isEmpty else {
            panel.hide()
            return
        }
        // 用整段编码的屏幕范围定位，让候选窗从编码左侧正下方开始
        let caret = markedTextScreenRect(preedit: preedit)
        let pageSize = IMEAppearancePrefs.pageSize
        var page = Array(texts.prefix(pageSize))
        if DateTimeCandidates.candidates(for: preedit) != nil {
            // 预置候选按当前页切片；Rime 候选本身已是当前页。
            syncSpecialPage(preedit: preedit)
            let start = min(specialPage * pageSize, max(texts.count - 1, 0))
            page = Array(texts[start..<min(start + pageSize, texts.count)])
        }
        panel.show(candidates: page, preedit: preedit, caretRect: caret) { [weak self] idx in
            _ = self?.selectCandidate(index: idx)
        }
    }

    /// 当前下划线编码（marked text）的屏幕矩形，供候选窗定位到编码下方
    private func markedTextScreenRect(preedit: String) -> NSRect {
        guard let client = currentClient ?? (client() as? IMKTextInput) else {
            let p = NSEvent.mouseLocation
            return NSRect(x: p.x, y: p.y, width: 0, height: 16)
        }

        var start = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &start)

        // 无有效几何时退回鼠标
        if start.origin.x == 0, start.origin.y == 0, start.width == 0, start.height == 0 {
            let p = NSEvent.mouseLocation
            return NSRect(x: p.x, y: p.y, width: 0, height: 16)
        }

        // 取编码末字符位置，拼出整段 preedit 宽度
        let utf16Len = preedit.utf16.count
        if utf16Len > 1 {
            var end = NSRect.zero
            _ = client.attributes(forCharacterIndex: utf16Len - 1, lineHeightRectangle: &end)
            if end.width > 0 || end.height > 0 {
                let minX = min(start.origin.x, end.origin.x)
                let maxX = max(start.origin.x + max(start.width, 1), end.origin.x + max(end.width, 1))
                let minY = min(start.origin.y, end.origin.y)
                let maxY = max(start.origin.y + start.height, end.origin.y + end.height)
                return NSRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 16))
            }
        }
        return start
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
        let deploy = NSMenuItem(
            title: "部署",
            action: #selector(deployFromMenu(_:)),
            keyEquivalent: ""
        )
        deploy.target = self
        menu.addItem(deploy)
        let prefs = NSMenuItem(
            title: "玫枫五笔设置…",
            action: #selector(openPreferences(_:)),
            keyEquivalent: ","
        )
        prefs.target = self
        menu.addItem(prefs)
        return menu
    }

    // 菜单栏手动全量部署，并让当前输入法进程立刻重载
    @objc func deployFromMenu(_ sender: Any?) {
        let result = RimeConfigDeploy.deployNow()
        _ = RimeSession.shared.ensureStarted()
        let alert = NSAlert()
        switch result {
        case .success:
            alert.messageText = "部署完成"
            alert.informativeText = "当前词库配置已重新部署。"
        case .failure(let message):
            alert.messageText = "部署失败"
            alert.informativeText = message
            alert.alertStyle = .warning
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// 菜单栏「设置」入口（绕过仅依赖 nib / 空 window 的默认实现）
    @objc func openPreferences(_ sender: Any?) {
        log("openPreferences")
        showPreferences(sender)
    }

    override func showPreferences(_ sender: Any!) {
        log("showPreferences")
        if preferencesWindowController == nil {
            preferencesWindowController = MeifengPreferencesWindowController()
        }
        preferencesWindowController?.showWindow(sender)
    }

    @objc private func toggleAscii() {
        asciiMode.toggle()
        if asciiMode {
            commitOrClearPending(forceCommitRaw: true)
            panel.hide()
            clearMarkedText()
        }
    }
}

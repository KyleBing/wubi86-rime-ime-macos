import AppKit
import Carbon
import InputMethodKit

/// 玫枫五笔 IMK 控制器：inline preedit + 非激活候选条
@objc(MeifengInputController)
final class MeifengInputController: IMKInputController {
    private static weak var activeController: MeifengInputController?
    private let panel = CandidatePanelController()
    private let modeHint = ModeHintController()
    private var currentClient: (any IMKTextInput)?
    private var asciiMode = false
    // 取消已经排上、但输入框已经失焦的光标提示。
    private var caretHintToken = 0
    // 这段时间内系统清浮层时，保留刚出现的中/英提示。
    private var caretHintArmedUntil: Date?
    private var shiftIsSticky = false
    private var sawOtherKeyWithShift = false
    // 预置候选（date / time）由输入法自行分页，记录当前页与所属编码。
    private var specialPage = 0
    private var specialPreedit = ""
    // 输入法自己的标点候选，不交给 Rime。
    private var punctSymbols: [String] = []
    private var punctPage = 0
    // 强引用，避免设置窗口闪一下被释放
    private var preferencesWindowController: MeifengPreferencesWindowController?
    // 菜单交给另一个进程绘制，必须自己留着，否则项会被释放掉
    private var inputMenu: NSMenu?

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
        Self.activeController = self
        let ok = RimeSession.shared.ensureStarted()
        log("activateServer rime=\(ok) client=\(currentClient != nil)")
        // 光标出现时先标出当前中/英，避免打字后才发现要切换。可在设置里关闭。
        if IMEAppearancePrefs.showCaretModeHint {
            scheduleModeHintAtCaret()
        }
    }

    override func deactivateServer(_ sender: Any!) {
        caretHintToken += 1
        caretHintArmedUntil = nil
        commitOrClearPending()
        clearPunctuation()
        panel.hide()
        // 输入框失焦后提示不再属于当前会话，立刻收掉，避免残留在别的窗口上。
        modeHint.hide()
        clearMarkedText()
        super.deactivateServer(sender)
        log("deactivateServer")
    }

    override func hidePalettes() {
        clearPunctuation()
        // 光标提示刚排上时，有的客户端会顺手清一次浮层，这时别把提示清掉。
        if let until = caretHintArmedUntil, Date() < until {
            super.hidePalettes()
            return
        }
        modeHint.hide()
        super.hidePalettes()
    }

    override func commitComposition(_ sender: Any!) {
        commitOrClearPending(forceCommitRaw: true)
        clearPunctuation()
        clearMarkedText()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        currentClient = (sender as? IMKTextInput) ?? currentClient
        Self.activeController = self

        if event.type == .flagsChanged {
            // 删除确认框开着时，Shift 不要切成英文。
            if DeleteCandidatePanel.shared.isOpen {
                return true
            }
            // 造词框里的 Shift 用来选字，不要当成中英切换
            if QuickAddWordPanel.shared.isOpen {
                return true
            }
            return handleFlagsChanged(event)
        }
        guard event.type == .keyDown else { return false }
        if DeleteCandidatePanel.shared.isOpen {
            return DeleteCandidatePanel.shared.handleKey(event)
        }
        // 开始输入后收起模式提示，避免盖住编码或候选。
        modeHint.hide()

        if event.modifierFlags.contains(.shift) {
            sawOtherKeyWithShift = true
        }

        if let editing = QuickAddWordPanel.shared.claimEditingKey(event) {
            return editing
        }

        // 候选出现时：造词那组修饰键 + 数字，删除对应候选。要放在 Command 提前返回之前。
        if handleDeleteCandidateShortcut(event) {
            return true
        }

        // 有 Command 交给系统
        if event.modifierFlags.contains(.command) {
            return false
        }

        guard RimeSession.shared.ensureStarted() else {
            log("handle: rime not ready")
            return false
        }

        // 标点在输入法里处理。编码过程中仍交给 Rime，避免打断翻页和选词。
        if !asciiMode, let handled = handlePunctuationKey(event) {
            return handled
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

    // 必须在造词面板成为关键窗口前读取，否则原应用的选区可能已经收起。
    static func selectedTextFromActiveClient() -> String? {
        guard let controller = activeController,
              let client = controller.currentClient ?? (controller.client() as? IMKTextInput) else {
            return nil
        }
        let range = client.selectedRange()
        guard range.location != NSNotFound, range.length > 0,
              let selected = client.attributedSubstring(from: range)?.string else {
            return nil
        }
        let text = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

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

    // 未组字时拦截标点。返回 nil 表示这颗键继续交给 Rime。
    private func handlePunctuationKey(_ event: NSEvent) -> Bool? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) || flags.contains(.option) {
            return nil
        }
        let composing = RimeSession.shared.bridgeEngine.snapshot()?.isComposing == true
        let ch = event.characters

        if !punctSymbols.isEmpty {
            if event.keyCode == 53 {
                clearPunctuation()
                return true
            }
            if let ch, handlePunctuationNavigation(ch, keyCode: event.keyCode) {
                return true
            }
            // 标点候选开着时再按标点，改输出这一颗。
            if let ch, !composing, let item = PunctuationPrefs.item(for: ch) {
                applyPunctuation(item)
                return true
            }
            clearPunctuation()
            return nil
        }

        guard !composing, let ch, let item = PunctuationPrefs.item(for: ch) else {
            return nil
        }
        applyPunctuation(item)
        return true
    }

    // 标点候选的选词和翻页。处理了返回 true。
    private func handlePunctuationNavigation(_ ch: String, keyCode: UInt16) -> Bool {
        let pageSize = IMEAppearancePrefs.pageSize
        let pageCount = max((punctSymbols.count + pageSize - 1) / pageSize, 1)
        func pick(_ n: Int) -> Bool {
            let index = punctPage * pageSize + n
            guard n < pageSize, punctSymbols.indices.contains(index) else { return true }
            commitPunctuation(punctSymbols[index])
            return true
        }
        func turn(_ delta: Int) -> Bool {
            let target = min(max(punctPage + delta, 0), pageCount - 1)
            if target != punctPage {
                punctPage = target
                showPunctuationPage()
            }
            return true
        }
        if let digit = Int(ch), (1...9).contains(digit) {
            return pick(digit - 1)
        }
        if ch == " " {
            return pick(0)
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
        switch Int(keyCode) {
        case kVK_PageUp:
            return turn(-1)
        case kVK_PageDown:
            return turn(1)
        default:
            return false
        }
    }

    private func applyPunctuation(_ item: PunctuationPrefs.Item) {
        let symbols = PunctuationPrefs.symbols(for: item.key)
        let mode = PunctuationPrefs.mode(for: item.key)
        if mode == .direct {
            commitPunctuation(symbols.first ?? item.key)
            return
        }
        punctSymbols = symbols
        punctPage = 0
        showPunctuationPage()
    }

    private func showPunctuationPage() {
        let pageSize = IMEAppearancePrefs.pageSize
        let start = min(punctPage * pageSize, max(punctSymbols.count - 1, 0))
        let page = Array(punctSymbols[start..<min(start + pageSize, punctSymbols.count)])
        panel.show(candidates: page, codes: [], caretRect: insertionCaretRect()) { [weak self] idx in
            guard let self else { return }
            let index = self.punctPage * pageSize + idx
            guard self.punctSymbols.indices.contains(index) else { return }
            self.commitPunctuation(self.punctSymbols[index])
        }
    }

    private func commitPunctuation(_ text: String) {
        insertText(text)
        clearPunctuation()
    }

    private func clearPunctuation() {
        punctSymbols = []
        punctPage = 0
        panel.hide()
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
            let caret = insertionCaretRect()
            if asciiMode {
                commitOrClearPending(forceCommitRaw: true)
                panel.hide()
                clearMarkedText()
            }
            modeHint.show(asciiMode: asciiMode, caretRect: caret)
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
        let codes = candidateCodes(for: page, preedit: preedit)
        panel.show(candidates: page, codes: codes, caretRect: caret) { [weak self] idx in
            _ = self?.selectCandidate(index: idx)
        }
    }

    // 词后编码：普通输入只显示还没打完的后几码；z 反查显示单字五笔码。预置候选没有五笔码。
    private func candidateCodes(for texts: [String], preedit: String) -> [String] {
        guard IMEAppearancePrefs.showPreeditInPanel, DateTimeCandidates.candidates(for: preedit) == nil else {
            return []
        }
        let typed = RimeSession.shared.bridgeEngine.rawInput()
        let input = typed.isEmpty ? preedit : typed
        return DictLexiconIndex.shared.displayCodes(texts: texts, preedit: input)
    }

    // 聚焦后隔一小段再量光标。激活当帧客户端经常还没把插入点算出来。
    private func scheduleModeHintAtCaret() {
        caretHintToken += 1
        let token = caretHintToken
        // 覆盖重试和大约一秒的显示时间。
        caretHintArmedUntil = Date().addingTimeInterval(1.4)
        revealModeHintAtCaret(token: token, attemptsLeft: 8)
    }

    private func revealModeHintAtCaret(token: Int, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, token == self.caretHintToken else { return }
            if let caret = self.focusedInsertionCaretRect() {
                self.modeHint.show(asciiMode: self.asciiMode, caretRect: caret)
                return
            }
            guard attemptsLeft > 1 else { return }
            self.revealModeHintAtCaret(token: token, attemptsLeft: attemptsLeft - 1)
        }
    }

    // 当前插入点的屏幕矩形。段尾用前一个字的右缘，避免下标越界拿到空矩形。
    private func focusedInsertionCaretRect() -> NSRect? {
        guard let client = currentClient ?? (client() as? IMKTextInput) else { return nil }
        let selected = client.selectedRange()
        guard selected.location != NSNotFound else { return nil }

        var index = selected.location
        var atTrailingEdge = false
        if index > 0 {
            index -= 1
            atTrailingEdge = true
        }

        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        if rect.width == 0, rect.height == 0, rect.origin == .zero {
            return nil
        }
        if atTrailingEdge {
            rect.origin.x += max(rect.width, 0)
        }
        rect.size.width = 1
        if rect.height < 1 {
            rect.size.height = 16
        }
        return rect
    }

    /// 当前插入点的屏幕矩形，供模式提示贴在光标旁。
    private func insertionCaretRect() -> NSRect {
        guard let client = currentClient ?? (client() as? IMKTextInput) else {
            let p = NSEvent.mouseLocation
            return NSRect(x: p.x, y: p.y, width: 1, height: 16)
        }
        var caret = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &caret)
        if caret.width == 0, caret.height == 0, caret.origin == .zero {
            let p = NSEvent.mouseLocation
            return NSRect(x: p.x, y: p.y, width: 1, height: 16)
        }
        if caret.height < 1 {
            caret.size.height = 16
        }
        return caret
    }

    /// 当前下划线编码（marked text）的屏幕矩形，供候选窗定位到编码下方
    private func markedTextScreenRect(preedit: String) -> NSRect {
        if let rect = QuickAddWordPanel.shared.compositionScreenRect() {
            return rect
        }
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

    // Control / Option 下 characters 可能为空，数字行和数字键盘都认。
    private func digitIndex(for event: NSEvent) -> Int? {
        if let ch = event.charactersIgnoringModifiers?.first,
           let number = ch.wholeNumberValue,
           (1...9).contains(number) {
            return number - 1
        }
        switch Int(event.keyCode) {
        case kVK_ANSI_1, kVK_ANSI_Keypad1: return 0
        case kVK_ANSI_2, kVK_ANSI_Keypad2: return 1
        case kVK_ANSI_3, kVK_ANSI_Keypad3: return 2
        case kVK_ANSI_4, kVK_ANSI_Keypad4: return 3
        case kVK_ANSI_5, kVK_ANSI_Keypad5: return 4
        case kVK_ANSI_6, kVK_ANSI_Keypad6: return 5
        case kVK_ANSI_7, kVK_ANSI_Keypad7: return 6
        case kVK_ANSI_8, kVK_ANSI_Keypad8: return 7
        case kVK_ANSI_9, kVK_ANSI_Keypad9: return 8
        default: return nil
        }
    }

    // 造词修饰键 + 1–9：弹出删除确认，并说明词库、权重和同编码词。
    private func handleDeleteCandidateShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbon = QuickAddPrefs.carbonModifiers(from: flags)
        guard carbon != 0, carbon == QuickAddPrefs.modifiers else { return false }
        if QuickAddWordPanel.shared.isOpen { return false }
        guard let index = digitIndex(for: event) else { return false }
        guard let snap = RimeSession.shared.bridgeEngine.snapshot(), snap.isComposing else { return false }
        let preedit = snap.preedit ?? ""
        if DateTimeCandidates.candidates(for: preedit) != nil {
            DeleteCandidatePanel.shared.presentUnavailable("这是预置的日期或时间候选，不在词库里，不能删除。")
            return true
        }
        guard index < snap.candidates.count else { return true }
        let text = snap.candidates[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        DeleteCandidatePanel.shared.present(candidate: text, preedit: preedit) { [weak self] code in
            self?.restoreComposition(code)
        }
        return true
    }

    // 删词会重建 Rime 会话，把删除前的编码重新输进去。
    private func restoreComposition(_ preedit: String) {
        let engine = RimeSession.shared.bridgeEngine
        for scalar in preedit.unicodeScalars {
            let value = Int32(scalar.value)
            guard (0x20...0x7E).contains(value) else { continue }
            _ = engine.processKey(value, modifiers: 0)
        }
        _ = consumeRimeUpdate()
    }

    private func insertText(_ string: String) {
        if QuickAddWordPanel.shared.insertComposedText(string) {
            return
        }
        QuickAddWordPanel.noteCommittedWord(string)
        guard let client = currentClient ?? (client() as? IMKTextInput) else {
            log("insertText FAILED no client: \(string)")
            return
        }
        client.insertText(string, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func setMarkedText(_ string: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let marked = NSAttributedString(string: string, attributes: attrs)
        if QuickAddWordPanel.shared.setComposition(
            marked,
            selectionRange: NSRange(location: string.count, length: 0)
        ) {
            return
        }
        guard let client = currentClient ?? (client() as? IMKTextInput) else {
            log("setMarkedText FAILED no client: \(string)")
            return
        }
        client.setMarkedText(
            marked,
            selectionRange: NSRange(location: string.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    private func clearMarkedText() {
        if QuickAddWordPanel.shared.clearComposition() {
            return
        }
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
            caretHintToken += 1
            caretHintArmedUntil = nil
            commitOrClearPending(forceCommitRaw: true)
            panel.hide()
            modeHint.hide()
            clearMarkedText()
        }
    }

    override func menu() -> NSMenu! {
        // 状态栏菜单属于 TextInputMenuAgent。自动启用时它的响应链里没有本控制器，项会被关掉并隐藏。
        let menu = NSMenu(title: "玫枫五笔")
        menu.autoenablesItems = false
        let deploy = NSMenuItem(
            title: "部署",
            action: #selector(deployFromMenu(_:)),
            keyEquivalent: ""
        )
        deploy.target = self
        deploy.isEnabled = true
        menu.addItem(deploy)
        let prefs = NSMenuItem(
            title: "玫枫五笔设置…",
            action: #selector(openPreferences(_:)),
            keyEquivalent: ","
        )
        prefs.target = self
        prefs.isEnabled = true
        menu.addItem(prefs)
        inputMenu = menu
        log("menu built items=\(menu.numberOfItems)")
        return menu
    }

    // 菜单栏手动全量部署，并让当前输入法进程立刻重载
    @objc func deployFromMenu(_ sender: Any?) {
        let outcome = RimeSession.shared.performExternalDeploy {
            RimeConfigDeploy.deployNow()
        }
        let alert = NSAlert()
        switch outcome.result {
        case .success where outcome.restarted:
            alert.messageText = "部署完成"
            alert.informativeText = "当前词库配置已重新部署。"
        case .success:
            alert.messageText = "部署完成，但输入法重载失败"
            alert.informativeText = "请重新切换输入法；若仍无法输入，请重启输入法进程。"
            alert.alertStyle = .warning
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
        let caret = insertionCaretRect()
        if asciiMode {
            commitOrClearPending(forceCommitRaw: true)
            panel.hide()
            clearMarkedText()
        }
        modeHint.show(asciiMode: asciiMode, caretRect: caret)
    }
}

import AppKit
import Carbon

/// 候选出现时弹出：拖动调整顺序，只改被拖动那一条的权重。
final class CandidateRankPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let shared = CandidateRankPanel()

    private let panel: NSPanel
    private let codeLabel = NSTextField(labelWithString: "")
    private let stepControl = NSSegmentedControl(labels: ["5", "10"], trackingMode: .selectOne, target: nil, action: nil)
    private let table = RankReorderTable()
    private let scroll = NSScrollView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let doneButton = NSButton(title: "完成", target: nil, action: nil)
    private let contentWidth: CGFloat = 520

    private var rows: [RankRow] = []
    private var preedit = ""
    private var onClosed: ((String) -> Void)?
    private var lookupGeneration = 0
    private var ready = false
    private var dirty = false
    private var touchedUserDict = false
    private var finishing = false
    private var step = UserDefaults.standard.integer(forKey: Keys.step) == 10 ? 10 : 5

    private var dragOverlay: NSView?
    private var dragSourceRow: Int?
    private var dragTargetRow: Int?
    private var dragGrabOffsetY: CGFloat = 0

    var isOpen: Bool { panel.isVisible }

    private enum Keys {
        static let step = "candidate.rankWeightStep"
    }

    private override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "候选排序"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.delegate = self
        build()
    }

    // 用当前这串编码下的候选打开。关掉窗口时如果改过权重，再把编码交回去重输。
    func present(preedit: String, candidates: [String], onClosed: @escaping (String) -> Void) {
        self.preedit = preedit
        self.onClosed = onClosed
        dirty = false
        touchedUserDict = false
        finishing = false
        ready = false
        rows = []
        lookupGeneration += 1
        let generation = lookupGeneration
        codeLabel.stringValue = preedit.isEmpty ? "—" : preedit
        table.reloadData()
        setStatus("正在读取词库里的权重…", color: .secondaryLabelColor)
        show()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = candidates.map { Self.makeRow(text: $0, preedit: preedit) }
            DispatchQueue.main.async {
                guard let self, generation == self.lookupGeneration, self.isOpen else { return }
                self.rows = loaded
                self.ready = true
                self.table.reloadData()
                let adjustable = loaded.filter { $0.hit != nil }.count
                if loaded.isEmpty {
                    self.setStatus("没有可以排序的候选。", color: .systemOrange)
                } else if adjustable == 0 {
                    self.setStatus("这些候选不在词库里，不能改权重。", color: .systemOrange)
                } else {
                    self.setStatus("拖动一行调整顺序。幅度 \(self.step) 是相对旁边那条候选的权重差。", color: .secondaryLabelColor)
                }
            }
        }
    }

    // 预置候选或反查没有可改的五笔权重时，只说明原因。
    func presentUnavailable(_ reason: String) {
        lookupGeneration += 1
        preedit = ""
        onClosed = nil
        dirty = false
        touchedUserDict = false
        finishing = false
        ready = false
        rows = []
        codeLabel.stringValue = "—"
        table.reloadData()
        setStatus(reason, color: .systemOrange)
        show()
    }

    // 输入法先接到按键。Esc 和回车关掉窗口，其它键不要改当前编码。
    func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter:
            finish()
        default:
            break
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish()
        return false
    }

    // 同一词有多条时，改当前排在前面的那条：权重大的优先，一样大则改用户词。
    private static func makeRow(text: String, preedit: String) -> RankRow {
        let match = DictLexiconIndex.shared.match(text: text, preedit: preedit)
        let hit = match.hits.max { a, b in
            let wa = a.entry.weight ?? Int.min
            let wb = b.entry.weight ?? Int.min
            if wa != wb { return wa < wb }
            return Self.sourceRank(a) > Self.sourceRank(b)
        }
        return RankRow(
            text: text,
            code: hit?.entry.code ?? "—",
            weight: hit?.entry.weight ?? 0,
            hasWeight: hit?.entry.weight != nil,
            source: hit?.sourceTitle ?? "不在词库",
            hit: hit
        )
    }

    // 用户词优先于扩展、Hamster 和主词库。
    private static func sourceRank(_ hit: DictLexiconHit) -> Int {
        switch hit.fileURL.lastPathComponent {
        case "wubi86_jidian_user.dict.yaml": return 0
        case "wubi86_jidian_extra.dict.yaml": return 1
        case "wubi86_jidian_user_hamster.dict.yaml": return 2
        case "wubi86_jidian.dict.yaml": return 3
        default: return 4
        }
    }

    // 设置里的排序快捷键，例如默认的 ⌃⌥0。
    private static func shortcutLabel() -> String {
        RankShortcutPrefs.display
    }

    private func show() {
        panel.title = "候选排序 \(Self.shortcutLabel())"
        stepControl.selectedSegment = step == 10 ? 1 : 0
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    // 松手后把被拖动的那一条写成新权重，并按权重放回它实际会排到的位置。
    private func applyDrag(from: Int, to: Int) {
        guard ready, rows.indices.contains(from), from != to else { return }
        guard let hit = rows[from].hit else {
            setStatus("「\(rows[from].text)」不在词库里，不能改权重。", color: .systemOrange)
            return
        }
        let weights = rows.map(\.weight)
        guard let newWeight = CandidateRankWeight.placed(weights: weights, from: from, to: to, step: step) else {
            return
        }
        let oldWeight = rows[from].weight
        let hadWeight = rows[from].hasWeight
        guard newWeight != oldWeight || !hadWeight else {
            setStatus("幅度 \(step) 没有拉开「\(rows[from].text)」和旁边候选的差距。", color: .systemOrange)
            return
        }
        let text = rows[from].text
        do {
            try DictLexiconIndex.shared.updateWeight(hit, to: newWeight)
        } catch {
            setStatus(error.localizedDescription, color: .systemRed)
            return
        }
        if hit.fileURL.lastPathComponent == "wubi86_jidian_user.dict.yaml" {
            touchedUserDict = true
        }
        dirty = true
        var moving = rows.remove(at: from)
        moving.weight = newWeight
        moving.hasWeight = true
        moving.edited = true
        let others = rows.map(\.weight)
        let index = CandidateRankWeight.index(for: newWeight, among: others)
        rows.insert(moving, at: index)
        table.reloadData()
        table.scrollRowToVisible(index)
        if index == to {
            let shownOld = hadWeight ? String(oldWeight) : "无"
            setStatus("「\(text)」权重 \(shownOld) → \(newWeight)。关闭窗口后重新加载词库。", color: .secondaryLabelColor)
        } else {
            setStatus("幅度 \(step) 大于和旁边候选的差距，「\(text)」现在是第 \(index + 1) 位，权重 \(newWeight)。", color: .systemOrange)
        }
    }

    // 改过的权重已经写进码表。这里重新编译，再把原来的编码交回去。
    private func finish() {
        guard !finishing else { return }
        finishing = true
        lookupGeneration += 1
        ready = false
        panel.orderOut(nil)
        let code = preedit
        let shouldReload = dirty
        let syncUserDict = touchedUserDict
        let callback = onClosed
        dirty = false
        touchedUserDict = false
        onClosed = nil
        preedit = ""
        if shouldReload {
            _ = RimeSession.shared.reloadUserDictionary()
            callback?(code)
        }
        if syncUserDict {
            UserDictAutoSync.noteLocalEdit()
        }
    }

    @objc private func stepChanged() {
        step = stepControl.selectedSegment == 1 ? 10 : 5
        UserDefaults.standard.set(step, forKey: Keys.step)
        if ready {
            setStatus("接下来拖动时，权重按 \(step) 调整。", color: .secondaryLabelColor)
        }
    }

    @objc private func done() {
        finish()
    }

    // MARK: - 拖动

    // 系统拖放在输入法的浮动窗口里不可靠，改由表格自己跟踪鼠标。
    private func beginReorder(row: Int, at point: NSPoint) {
        guard ready, rows.indices.contains(row), rows[row].hit != nil else {
            if rows.indices.contains(row) {
                setStatus("「\(rows[row].text)」不在词库里，不能改权重。", color: .systemOrange)
            }
            return
        }
        let rowRect = table.rect(ofRow: row)
        let rowView = table.rowView(atRow: row, makeIfNecessary: false)
        let image = rowView.flatMap(snapshot(of:))
        let overlay = RankPassthroughView(frame: rowRect)
        overlay.wantsLayer = true
        overlay.layer?.contents = image
        overlay.layer?.contentsGravity = .resize
        overlay.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        overlay.layer?.cornerRadius = 6
        overlay.layer?.borderWidth = 1
        overlay.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        overlay.layer?.shadowColor = NSColor.black.cgColor
        overlay.layer?.shadowOpacity = 0.25
        overlay.layer?.shadowRadius = 8
        overlay.layer?.shadowOffset = CGSize(width: 0, height: -3)
        table.addSubview(overlay)
        dragOverlay = overlay
        dragSourceRow = row
        dragTargetRow = row
        dragGrabOffsetY = point.y - rowRect.minY
        rowView?.alphaValue = 0
        updateReorder(at: point)
    }

    // 浮层跟着鼠标，中心落到哪一行，松手后就以那一行为目标。
    private func updateReorder(at point: NSPoint) {
        guard let overlay = dragOverlay else { return }
        var frame = overlay.frame
        let maxY = max(0, table.bounds.height - frame.height)
        frame.origin.y = min(max(0, point.y - dragGrabOffsetY), maxY)
        overlay.frame = frame
        let count = table.numberOfRows
        guard count > 0 else { return }
        let hit = table.row(at: NSPoint(x: frame.midX, y: frame.midY))
        let target = hit >= 0 ? hit : (frame.midY <= 0 ? 0 : count - 1)
        guard target != dragTargetRow else { return }
        dragTargetRow = target
        layoutReorderGap(animated: true)
    }

    // 原行和目标行之间的行让出一格。
    private func layoutReorderGap(animated: Bool) {
        guard let source = dragSourceRow, let target = dragTargetRow else { return }
        let slot = table.rowHeight + table.intercellSpacing.height
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.16 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            table.enumerateAvailableRowViews { rowView, row in
                var y = table.rect(ofRow: row).minY
                if source < row && row <= target {
                    y -= slot
                } else if target <= row && row < source {
                    y += slot
                }
                guard rowView.frame.origin.y != y else { return }
                if animated {
                    rowView.animator().setFrameOrigin(NSPoint(x: rowView.frame.minX, y: y))
                } else {
                    rowView.setFrameOrigin(NSPoint(x: rowView.frame.minX, y: y))
                }
            }
        }
    }

    private func endReorder(cancelled: Bool) {
        let source = dragSourceRow
        let target = cancelled ? source : dragTargetRow
        dragOverlay?.removeFromSuperview()
        dragOverlay = nil
        dragSourceRow = nil
        dragTargetRow = nil
        table.enumerateAvailableRowViews { rowView, row in
            rowView.layer?.removeAllAnimations()
            rowView.alphaValue = 1
            rowView.setFrameOrigin(NSPoint(x: rowView.frame.minX, y: table.rect(ofRow: row).minY))
        }
        guard let source, let target, !cancelled else { return }
        applyDrag(from: source, to: target)
    }

    private func snapshot(of view: NSView) -> NSImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let item = rows[row]
        let value: String
        let mono: Bool
        switch id {
        case "code":
            value = item.code
            mono = true
        case "weight":
            value = item.hasWeight ? String(item.weight) : "—"
            mono = true
        case "source":
            value = item.source
            mono = false
        default:
            value = item.text
            mono = false
        }
        let key = NSUserInterfaceItemIdentifier(id)
        let cell = (tableView.makeView(withIdentifier: key, owner: self) as? NSTextField) ?? {
            let field = NSTextField(labelWithString: "")
            field.identifier = key
            field.lineBreakMode = .byTruncatingTail
            return field
        }()
        cell.stringValue = value
        cell.font = mono
            ? .monospacedSystemFont(ofSize: 12, weight: item.edited && id == "weight" ? .semibold : .regular)
            : .systemFont(ofSize: 13, weight: id == "text" ? .medium : .regular)
        if item.hit == nil {
            cell.textColor = .tertiaryLabelColor
        } else if item.edited && id == "weight" {
            cell.textColor = .controlAccentColor
        } else if id == "source" || id == "code" {
            cell.textColor = .secondaryLabelColor
        } else {
            cell.textColor = .labelColor
        }
        return cell
    }

    private func build() {
        codeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        stepControl.segmentDistribution = .fillEqually
        stepControl.selectedSegment = step == 10 ? 1 : 0
        stepControl.target = self
        stepControl.action = #selector(stepChanged)
        stepControl.setContentHuggingPriority(.required, for: .horizontal)
        stepControl.toolTip = "被拖动的词相对旁边候选增减的权重"

        let codeCaption = NSTextField(labelWithString: "编码")
        codeCaption.font = .systemFont(ofSize: 12)
        codeCaption.alignment = .right
        let stepCaption = NSTextField(labelWithString: "幅度")
        stepCaption.font = .systemFont(ofSize: 12)
        stepCaption.alignment = .right
        let header = NSStackView(views: [codeCaption, codeLabel, stepCaption, stepControl])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        codeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        table.onReorderBegin = { [weak self] row, point in
            self?.beginReorder(row: row, at: point)
        }
        table.onReorderMove = { [weak self] point in
            self?.updateReorder(at: point)
        }
        table.onReorderEnd = { [weak self] cancelled in
            self?.endReorder(cancelled: cancelled)
        }
        configureTable()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.preferredMaxLayoutWidth = contentWidth - 32

        doneButton.target = self
        doneButton.action = #selector(done)
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        panel.defaultButtonCell = doneButton.cell as? NSButtonCell
        let leading = NSView()
        let trailing = NSView()
        leading.setContentHuggingPriority(.init(1), for: .horizontal)
        trailing.setContentHuggingPriority(.init(1), for: .horizontal)
        let footer = NSStackView(views: [leading, doneButton, trailing])
        footer.orientation = .horizontal
        footer.spacing = 8

        let hint = NSTextField(wrappingLabelWithString: "只改被拖动的那一条。权重更高的排在前面。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2

        let root = NSStackView(views: [header, hint, scroll, status, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView?.addSubview(root)
        guard let content = panel.contentView else { return }
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            hint.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 280),
            status.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            leading.widthAnchor.constraint(equalTo: trailing.widthAnchor),
            codeCaption.widthAnchor.constraint(equalToConstant: 36),
            stepCaption.widthAnchor.constraint(equalToConstant: 36),
            stepControl.widthAnchor.constraint(equalToConstant: 88)
        ])
        panel.setContentSize(NSSize(width: contentWidth, height: 420))
    }

    private func configureTable() {
        table.dataSource = self
        table.delegate = self
        table.headerView = NSTableHeaderView()
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 8, height: 2)
        table.backgroundColor = .clear
        table.style = .inset
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsEmptySelection = true
        let columns: [(String, String, CGFloat)] = [
            ("text", "词条", 150),
            ("code", "编码", 72),
            ("weight", "权重", 64),
            ("source", "词库", 160)
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "source" ? 80 : 48
            if id == "source" {
                column.resizingMask = .autoresizingMask
            }
            table.addTableColumn(column)
        }
    }

    private func setStatus(_ message: String, color: NSColor) {
        status.stringValue = message
        status.textColor = color
    }
}

/// 按幅度 5 或 10，算被拖动候选要写成的权重。
enum CandidateRankWeight {
    // weights 是当前列表从上到下的权重。to 是松手时的目标行号。
    // 上移：比目标位置下方那条高一个幅度；下移：比目标位置上方那条低一个幅度。
    // 两边的空隙比幅度小（常见于权重相同）时，仍按这个幅度跨过邻项。
    static func placed(weights: [Int], from: Int, to: Int, step: Int) -> Int? {
        guard weights.indices.contains(from), from != to, step > 0 else { return nil }
        var others = weights
        others.remove(at: from)
        guard !others.isEmpty else { return nil }
        let dest = min(max(0, to), others.count)
        if dest == 0 {
            return others[0] + step
        }
        if dest >= others.count {
            return others[others.count - 1] - step
        }
        let above = others[dest - 1]
        let below = others[dest]
        if above - step > below {
            return above - step
        }
        if below + step < above {
            return below + step
        }
        if to < from {
            return below + step
        }
        return above - step
    }

    // 权重大于它的排在前面；权重相同的排在它后面。
    static func index(for weight: Int, among others: [Int]) -> Int {
        others.filter { $0 > weight }.count
    }
}

private struct RankRow {
    var text: String
    var code: String
    var weight: Int
    var hasWeight: Bool
    var source: String
    var hit: DictLexiconHit?
    var edited = false
}

// 拖动浮层不吃点击，鼠标事件仍落在表格上。
private final class RankPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// 按下后移动超过阈值才算拖动。坐标都是表格坐标。
private final class RankReorderTable: NSTableView {
    var onReorderBegin: ((Int, NSPoint) -> Void)?
    var onReorderMove: ((NSPoint) -> Void)?
    var onReorderEnd: ((Bool) -> Void)?

    private var tracking = false

    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        let row = row(at: start)
        guard row >= 0, event.clickCount == 1, onReorderBegin != nil, let window else {
            super.mouseDown(with: event)
            return
        }
        tracking = true
        var dragging = false
        while tracking, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            switch next.type {
            case .leftMouseDragged:
                let point = convert(next.locationInWindow, from: nil)
                if !dragging {
                    guard hypot(point.x - start.x, point.y - start.y) >= 4 else { continue }
                    dragging = true
                    onReorderBegin?(row, start)
                }
                autoscroll(with: next)
                onReorderMove?(convert(next.locationInWindow, from: nil))
            case .leftMouseUp:
                onReorderEnd?(!dragging)
                tracking = false
                if !dragging {
                    window.postEvent(next, atStart: true)
                    super.mouseDown(with: event)
                }
                return
            case .keyDown where dragging && next.keyCode == UInt16(kVK_Escape):
                onReorderEnd?(true)
                tracking = false
                return
            default:
                break
            }
        }
    }
}

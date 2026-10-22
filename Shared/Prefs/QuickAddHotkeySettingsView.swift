import AppKit

/// 按键页里的快捷键录制按钮：点一下后按下新的组合键。读取和保存由调用方提供，
/// 造词和排序共用同一套录制界面。
final class HotkeyRecorderView: NSView {
    private let button = NSButton(title: "", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "需包含 ⌃ ⌥ ⇧ ⌘ 之一。Esc 取消。")
    private var monitor: Any?
    private var recording = false
    private let readDisplay: () -> String
    private let save: (UInt32, UInt32, String) -> Void

    init(display: @escaping () -> String, save: @escaping (UInt32, UInt32, String) -> Void) {
        readDisplay = display
        self.save = save
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(beginRecording)
        button.bezelStyle = .rounded
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.isHidden = true
        let row = NSStackView(views: [button, hint])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        showCurrent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stop()
    }

    @objc private func beginRecording() {
        recording = true
        button.title = "请按下快捷键…"
        hint.isHidden = false
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    private func capture(_ event: NSEvent) {
        guard recording else { return }
        if event.keyCode == 53 {
            recording = false
            stop()
            showCurrent()
            return
        }
        let carbon = QuickAddPrefs.carbonModifiers(from: event.modifierFlags)
        guard carbon != 0 else { return }
        let display = QuickAddPrefs.displayString(for: event)
        save(UInt32(event.keyCode), carbon, display)
        recording = false
        stop()
        showCurrent()
    }

    private func showCurrent() {
        button.title = readDisplay()
        hint.isHidden = true
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

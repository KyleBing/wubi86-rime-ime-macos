import AppKit

/// 输入法设置「词库目录」页：路径、拷贝 / 访达、切换目录与部署 / 复位。
final class LexiconDirectorySettingsView: NSView {
    private let dirCaption = NSTextField(labelWithString: "")
    private let dirPathLabel = NSTextField(wrappingLabelWithString: "")
    private let userFileLabel = NSTextField(labelWithString: "")
    private let useDefaultButton = NSButton(title: "切回默认目录", target: nil, action: nil)
    private let useRimeButton = NSButton(title: "切到 Rime 目录", target: nil, action: nil)
    private let bannerIcon = NSImageView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let bannerRow = NSStackView()
    private var isBusy = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refreshDirectoryInfo()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        dirCaption.font = .systemFont(ofSize: 11, weight: .medium)
        dirCaption.textColor = .secondaryLabelColor
        dirPathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        dirPathLabel.isSelectable = true
        dirPathLabel.maximumNumberOfLines = 0
        dirPathLabel.preferredMaxLayoutWidth = 560
        userFileLabel.font = .systemFont(ofSize: 11)
        userFileLabel.textColor = .secondaryLabelColor

        let copyPath = smallButton("复制路径", #selector(copyDataDirPath))
        let reveal = smallButton("在访达中显示", #selector(revealInFinder))
        let changeDir = smallButton("更改目录…", #selector(chooseDataDir))
        useDefaultButton.target = self
        useDefaultButton.action = #selector(restoreDefaultDir)
        useDefaultButton.controlSize = .small
        useRimeButton.target = self
        useRimeButton.action = #selector(useLibraryRimeDir)
        useRimeButton.controlSize = .small

        let pathButtons = NSStackView(views: [copyPath, reveal, changeDir])
        pathButtons.orientation = .horizontal
        pathButtons.spacing = 8
        pathButtons.alignment = .centerY

        let switchButtons = NSStackView(views: [useDefaultButton, useRimeButton])
        switchButtons.orientation = .horizontal
        switchButtons.spacing = 8
        switchButtons.alignment = .centerY

        let deploy = smallButton("部署当前配置", #selector(deployConfig))
        let reset = smallButton("复位原始配置", #selector(resetConfig))
        bannerIcon.imageScaling = .scaleProportionallyUpOrDown
        bannerIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bannerIcon.widthAnchor.constraint(equalToConstant: 14),
            bannerIcon.heightAnchor.constraint(equalToConstant: 14)
        ])
        bannerLabel.font = .systemFont(ofSize: 11)
        bannerLabel.maximumNumberOfLines = 2
        bannerRow.setViews([bannerIcon, bannerLabel], in: .leading)
        bannerRow.orientation = .horizontal
        bannerRow.alignment = .centerY
        bannerRow.spacing = 4
        bannerRow.isHidden = true

        let deployRow = NSStackView(views: [deploy, reset, bannerRow])
        deployRow.orientation = .horizontal
        deployRow.alignment = .centerY
        deployRow.spacing = 8

        let hint = NSTextField(wrappingLabelWithString: "「切到 Rime 目录」使用 \(AppGroupPaths.libraryRimeUserDataURL.path)，与鼠须管等前端相同。「切回默认目录」回到本输入法自己的目录。已有方案的目录不会被改写，空目录才会补上内置五笔。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 560

        let root = NSStackView(views: [dirCaption, dirPathLabel, userFileLabel, pathButtons, switchButtons, deployRow, hint])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 6
        root.setCustomSpacing(10, after: userFileLabel)
        root.setCustomSpacing(8, after: pathButtons)
        root.setCustomSpacing(10, after: switchButtons)
        root.setCustomSpacing(12, after: deployRow)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            pathButtons.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor),
            switchButtons.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor),
            deployRow.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor)
        ])
    }

    private func smallButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .small
        return button
    }

    private func refreshDirectoryInfo() {
        let current = RimeResourceDeployer.resolveUserDataURL().standardizedFileURL
        let library = AppGroupPaths.libraryRimeUserDataURL.standardizedFileURL
        let onDefault = AppGroupPaths.customRimeUserDataURL == nil
        if onDefault {
            dirCaption.stringValue = "词库目录（输入法默认）："
        } else if current == library {
            dirCaption.stringValue = "词库目录（Rime）："
        } else {
            dirCaption.stringValue = "词库目录（自定义）："
        }
        dirPathLabel.stringValue = current.path
        userFileLabel.stringValue = "用户词库文件：\(UserDictWriter.activeURL.lastPathComponent)"
        useDefaultButton.isEnabled = !onDefault
        useRimeButton.isEnabled = current != library
        useDefaultButton.toolTip = AppGroupPaths.defaultRimeUserDataURL?.path
        useRimeButton.toolTip = library.path
    }

    private func showBanner(success: Bool, text: String) {
        let name = success ? "checkmark.circle.fill" : "xmark.circle.fill"
        bannerIcon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        bannerIcon.contentTintColor = success ? .systemGreen : .systemRed
        bannerLabel.stringValue = text
        bannerLabel.textColor = success ? .systemGreen : .systemRed
        bannerRow.isHidden = false
    }

    private func requireActions() -> IMESettingsControls.LexiconActions? {
        guard let actions = IMESettingsControls.lexiconActions else {
            showBanner(success: false, text: "当前设置入口无法部署，请从主 App 或输入法菜单打开设置。")
            return nil
        }
        return actions
    }

    @objc private func copyDataDirPath() {
        let path = RimeResourceDeployer.resolveUserDataURL().path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        showBanner(success: true, text: "已复制词库目录路径")
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.open(RimeResourceDeployer.resolveUserDataURL())
    }

    @objc private func chooseDataDir() {
        guard let actions = requireActions(), !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = RimeResourceDeployer.resolveUserDataURL()
        panel.prompt = "使用此目录"
        panel.message = "选择已有的 Rime 配置目录。目录里已有方案时保持原样。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeDataDir(to: url, actions: actions)
    }

    @objc private func restoreDefaultDir() {
        guard let actions = requireActions(), !isBusy else { return }
        changeDataDir(to: nil, actions: actions)
    }

    @objc private func useLibraryRimeDir() {
        guard let actions = requireActions(), !isBusy else { return }
        changeDataDir(to: AppGroupPaths.libraryRimeUserDataURL, actions: actions)
    }

    private func changeDataDir(to url: URL?, actions: IMESettingsControls.LexiconActions) {
        isBusy = true
        let oldPath = RimeResourceDeployer.resolveUserDataURL().path
        let result = actions.changeDataDirectory(url)
        let newPath = RimeResourceDeployer.resolveUserDataURL().path
        refreshDirectoryInfo()
        if result.ok, newPath != oldPath {
            // 单字字典和用户词表都按目录现读，先丢掉旧缓存。
            WubiDictEncoder.clearCache()
            NotificationCenter.default.post(name: .meifengUserDictDidChange, object: nil)
            NotificationCenter.default.post(name: .meifengRimeDirectoryDidChange, object: nil)
            if actions.restartQuitsSettings {
                promptKeepSettingsOrRestart(actions: actions, message: result.message)
            } else {
                actions.restartIME()
                showBanner(success: true, text: result.message + "。输入法已重启")
            }
        } else {
            showBanner(success: result.ok, text: result.message)
        }
        isBusy = false
    }

    // 设置窗口开在输入法进程里时，直接重启会把窗口关掉。先问用户。
    private func promptKeepSettingsOrRestart(actions: IMESettingsControls.LexiconActions, message: String) {
        let alert = NSAlert()
        alert.messageText = "词库目录已切换"
        alert.informativeText = "\(message)。当前输入法已经改用新目录，设置窗口可以继续留着。若现在重启输入法，这个窗口会关掉，系统会在下次输入时再打开输入法。"
        alert.addButton(withTitle: "保持打开")
        alert.addButton(withTitle: "重启输入法")
        let restart = alert.runModal() != .alertFirstButtonReturn
        if restart {
            actions.restartIME()
            return
        }
        showBanner(success: true, text: message + "。设置窗口保持打开")
    }

    @objc private func deployConfig() {
        guard let actions = requireActions(), !isBusy else { return }
        isBusy = true
        let result = actions.deploy()
        showBanner(success: result.ok, text: result.message)
        isBusy = false
    }

    @objc private func resetConfig() {
        guard let actions = requireActions(), !isBusy else { return }
        let alert = NSAlert()
        alert.messageText = "复位原始配置？"
        alert.informativeText = "将清空当前词库目录中的配置并恢复内置文件，然后重新部署。"
        alert.addButton(withTitle: "复位")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isBusy = true
        let result = actions.reset()
        refreshDirectoryInfo()
        showBanner(success: result.ok, text: result.message)
        isBusy = false
    }
}

/// 词库目录页里的单字字典：选择参考码表并生成，供自动编码使用。
final class CharMapSettingsView: NSView {
    private let dictPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var directoryObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        dictPopup.controlSize = .small
        dictPopup.target = self
        dictPopup.action = #selector(dictSelectionChanged)
        dictPopup.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let generate = NSButton(title: "生成单字字典", target: self, action: #selector(generateCharMap))
        generate.controlSize = .small
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = 480
        let row = NSStackView(views: [dictPopup, generate])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let root = NSStackView(views: [row, statusLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        reloadDictPopup()
        directoryObserver = NotificationCenter.default.addObserver(
            forName: .meifengRimeDirectoryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadDictPopup()
        }
    }

    deinit {
        if let directoryObserver {
            NotificationCenter.default.removeObserver(directoryObserver)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func reloadDictPopup() {
        let names = WubiDictEncoder.availableDictFileNames()
        dictPopup.removeAllItems()
        if names.isEmpty {
            dictPopup.addItem(withTitle: "未找到码表")
            dictPopup.isEnabled = false
            statusLabel.stringValue = "词库目录里没有可用的 .dict.yaml"
            statusLabel.textColor = .systemOrange
            return
        }
        dictPopup.isEnabled = true
        for name in names {
            dictPopup.addItem(withTitle: name)
        }
        let selected = WubiDictEncoder.selectedMainDictName
        if names.contains(selected) {
            dictPopup.selectItem(withTitle: selected)
        } else if let first = names.first {
            dictPopup.selectItem(withTitle: first)
            WubiDictEncoder.selectedMainDictName = first
            WubiDictEncoder.clearCache()
        }
        if WubiDictEncoder.charMapStatus().exists {
            refreshStatus()
        } else {
            statusLabel.stringValue = "正在从参考码表生成…"
            generateCharMap()
        }
    }

    @objc private func dictSelectionChanged() {
        guard let title = dictPopup.titleOfSelectedItem, title.hasSuffix(".dict.yaml") else { return }
        WubiDictEncoder.selectedMainDictName = title
        WubiDictEncoder.clearCache()
        generateCharMap()
    }

    @objc private func generateCharMap() {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在生成…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let count = try WubiDictEncoder.rebuildCharMap()
                DispatchQueue.main.async {
                    self.statusLabel.textColor = .secondaryLabelColor
                    self.statusLabel.stringValue = "已生成 \(count) 个单字"
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.textColor = .systemRed
                    self.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func refreshStatus() {
        let status = WubiDictEncoder.charMapStatus()
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = status.exists ? "已生成 \(status.count) 个单字" : "尚未生成"
    }
}

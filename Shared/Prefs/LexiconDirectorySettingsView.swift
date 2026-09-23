import AppKit

/// 输入法设置「词库目录」页：路径、拷贝 / 访达、切换目录与部署 / 复位。
final class LexiconDirectorySettingsView: NSView {
    private let dirCaption = NSTextField(labelWithString: "")
    private let dirPathLabel = NSTextField(wrappingLabelWithString: "")
    private let userFileLabel = NSTextField(labelWithString: "")
    private let restoreDefaultButton = NSButton(title: "恢复默认", target: nil, action: nil)
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
        restoreDefaultButton.target = self
        restoreDefaultButton.action = #selector(restoreDefaultDir)
        restoreDefaultButton.controlSize = .small

        let pathButtons = NSStackView(views: [copyPath, reveal, changeDir, restoreDefaultButton])
        pathButtons.orientation = .horizontal
        pathButtons.spacing = 8
        pathButtons.alignment = .centerY

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

        let hint = NSTextField(wrappingLabelWithString: "更改目录会把现有配置与用户词拷贝到新位置（不覆盖同名文件）。部署后输入法即可使用最新词库。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 560

        let root = NSStackView(views: [dirCaption, dirPathLabel, userFileLabel, pathButtons, deployRow, hint])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 6
        root.setCustomSpacing(10, after: userFileLabel)
        root.setCustomSpacing(10, after: pathButtons)
        root.setCustomSpacing(12, after: deployRow)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            pathButtons.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor),
            deployRow.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor)
        ])
    }

    private func smallButton(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .small
        return button
    }

    private func refreshDirectoryInfo() {
        let custom = AppGroupPaths.customRimeUserDataURL != nil
        let path = RimeResourceDeployer.resolveUserDataURL().path
        dirCaption.stringValue = custom ? "词库目录（自定义）：" : "词库目录："
        dirPathLabel.stringValue = path
        userFileLabel.stringValue = "用户词库文件：\(UserDictWriter.activeURL.lastPathComponent)"
        restoreDefaultButton.isHidden = !custom
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
        panel.message = "选择词库目录，现有配置与用户词会拷贝到新目录（不覆盖同名文件）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeDataDir(to: url, actions: actions)
    }

    @objc private func restoreDefaultDir() {
        guard let actions = requireActions(), !isBusy else { return }
        changeDataDir(to: nil, actions: actions)
    }

    private func changeDataDir(to url: URL?, actions: IMESettingsControls.LexiconActions) {
        isBusy = true
        let oldPath = RimeResourceDeployer.resolveUserDataURL().path
        let result = actions.changeDataDirectory(url)
        let newPath = RimeResourceDeployer.resolveUserDataURL().path
        if newPath != oldPath {
            actions.restartIME()
        }
        refreshDirectoryInfo()
        showBanner(success: result.ok, text: result.message)
        isBusy = false
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

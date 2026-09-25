import AppKit

extension Notification.Name {
    // 同步把用户词写回本地后，词条表据此刷新。
    static let meifengUserDictDidChange = Notification.Name("cn.kylebing.inputmethod.meifengwubi.userDictDidChange")
}

/// 账户页：只负责登录。同步和扩展词库在用户词页。
final class AccountSyncSettingsView: NSView {
    private let baseField = NSTextField(string: "")
    private let emailField = NSTextField(string: "")
    private let passwordField = NSSecureTextField(string: "")
    private let accountLabel = NSTextField(wrappingLabelWithString: "")
    private let loginButton = NSButton(title: "登录", target: nil, action: nil)
    private let logoutButton = NSButton(title: "退出登录", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let loginForm = NSStackView()

    private var busy = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 从用户词页返回时刷新登录状态。
    override func viewDidUnhide() {
        super.viewDidUnhide()
        refresh()
    }

    private func build() {
        baseField.placeholderString = WubiCloudConfig.defaultBaseURL
        emailField.placeholderString = "邮箱"
        passwordField.placeholderString = "密码"
        for field in [baseField, emailField, passwordField] {
            field.font = .systemFont(ofSize: 13)
        }

        loginButton.target = self
        loginButton.action = #selector(loginClicked)
        loginButton.bezelStyle = .rounded
        logoutButton.target = self
        logoutButton.action = #selector(logoutClicked)
        logoutButton.bezelStyle = .rounded

        accountLabel.font = .systemFont(ofSize: 13)
        accountLabel.preferredMaxLayoutWidth = 460
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = 460
        statusLabel.maximumNumberOfLines = 3

        loginForm.orientation = .vertical
        loginForm.alignment = .leading
        loginForm.spacing = 8
        loginForm.addArrangedSubview(labeled("请求地址", baseField))
        loginForm.addArrangedSubview(labeled("邮箱", emailField))
        loginForm.addArrangedSubview(labeled("密码", passwordField))
        loginForm.addArrangedSubview(buttonRow([loginButton]))

        let hint = NSTextField(wrappingLabelWithString: "登录后到「用户词」页同步用户词，或获取扩展词库。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 460

        let root = NSStackView(views: [
            sectionTitle("登录"),
            accountLabel,
            loginForm,
            logoutButton,
            hint,
            statusLabel
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            baseField.widthAnchor.constraint(equalToConstant: 320),
            emailField.widthAnchor.constraint(equalToConstant: 320),
            passwordField.widthAnchor.constraint(equalToConstant: 320)
        ])
    }

    private func refresh() {
        let loggedIn = WubiCloudConfig.isLoggedIn
        baseField.stringValue = WubiCloudConfig.baseURL
        if emailField.stringValue.isEmpty {
            emailField.stringValue = WubiCloudConfig.userInfo?.email ?? ""
        }
        if let user = WubiCloudConfig.userInfo, user.isLoggedIn {
            let name = user.nickname.isEmpty ? user.email : user.nickname
            accountLabel.stringValue = "已登录：\(name)"
        } else {
            accountLabel.stringValue = "未登录。与码表助手、iOS 共用 portal 账号。"
        }
        loginForm.isHidden = loggedIn
        logoutButton.isHidden = !loggedIn
        loginButton.isEnabled = !busy
    }

    @objc private func loginClicked() {
        let mail = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        guard !mail.isEmpty, !password.isEmpty else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "请填写邮箱和密码"
            return
        }
        let base = baseField.stringValue
        guard !busy else { return }
        busy = true
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "登录中…"
        refresh()
        Task {
            do {
                let info = try await WubiCloudAPI.login(email: mail, password: password, baseURL: base)
                let name = info.nickname.isEmpty ? info.email : info.nickname
                await MainActor.run {
                    self.passwordField.stringValue = ""
                    self.statusLabel.textColor = .secondaryLabelColor
                    self.statusLabel.stringValue = "登录成功：\(name)"
                    self.busy = false
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.textColor = .systemRed
                    self.statusLabel.stringValue = error.localizedDescription
                    self.busy = false
                    self.refresh()
                }
            }
        }
    }

    @objc private func logoutClicked() {
        WubiCloudConfig.logout()
        passwordField.stringValue = ""
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "已退出登录"
        refresh()
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func labeled(_ title: String, _ field: NSTextField) -> NSView {
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 12)
        caption.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let row = NSStackView(views: [caption, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func buttonRow(_ buttons: [NSButton]) -> NSView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }
}

/// 用户词页顶部一条：用户词同步和扩展词库的状态与按钮，高度不随窗口拉伸。
final class UserLexiconCloudBar: NSView {
    private let accountMeta = NSTextField(labelWithString: "")
    private let extraMeta = NSTextField(labelWithString: "")
    private let compareButton = NSButton(title: "对比差异", target: nil, action: nil)
    private let mergeButton = NSButton(title: "增量合并", target: nil, action: nil)
    // 箭头指向被覆盖的一侧：本地 → 云端，本地 ← 云端。
    private let uploadButton = NSButton(title: "本地 → 云端", target: nil, action: nil)
    private let downloadButton = NSButton(title: "本地 ← 云端", target: nil, action: nil)
    private let extraButton = NSButton(title: "获取扩展词库", target: nil, action: nil)
    private let syncStatus = NSTextField(labelWithString: "")
    private let extraStatus = NSTextField(labelWithString: "")
    private let syncIdleLoggedOut = "请先在「账户」页登录"
    private let syncIdleLoggedIn = "先对比，再合并或覆盖"
    private let extraIdle = "获取后覆盖本地"

    private var busy = false
    private var remoteYaml: String?
    private var remoteDocument: UserDictDocument?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 从账户页登录后切回来时更新按钮可用状态。
    override func viewDidUnhide() {
        super.viewDidUnhide()
        refresh()
    }

    private func build() {
        wire(compareButton, #selector(compareClicked), tip: "拉取云端用户词，只对比不改词库")
        wire(mergeButton, #selector(mergeClicked), tip: "保留本地词条，并入云端多出的词")
        wire(uploadButton, #selector(uploadClicked), tip: "用本地用户词覆盖云端")
        wire(downloadButton, #selector(downloadClicked), tip: "用云端用户词覆盖本地")
        wire(extraButton, #selector(extraClicked), tip: "用线上扩展词库覆盖本地文件，不在此查看或编辑")

        styleStatus(syncStatus)
        styleStatus(extraStatus)

        let syncRow = makeRow(
            symbol: "arrow.triangle.2.circlepath",
            title: "用户词同步",
            meta: accountMeta,
            buttons: [compareButton, mergeButton, uploadButton, downloadButton],
            status: syncStatus
        )
        let extraRow = makeRow(
            symbol: "square.and.arrow.down",
            title: "扩展词库",
            meta: extraMeta,
            buttons: [extraButton],
            status: extraStatus
        )
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let stack = NSStackView(views: [syncRow, divider, extraRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        // 必须按内容定高。交给 NSBox 时会被父视图拉高，词条表就被挤没。
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in [syncRow, divider, extraRow] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        applyChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChrome()
    }

    // 边框和底色跟着亮暗外观走。
    private func applyChrome() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    private func refresh() {
        let loggedIn = WubiCloudConfig.isLoggedIn
        if let user = WubiCloudConfig.userInfo, user.isLoggedIn {
            let name = user.nickname.isEmpty ? user.email : user.nickname
            accountMeta.stringValue = name
            accountMeta.textColor = .secondaryLabelColor
        } else {
            accountMeta.stringValue = "未登录"
            accountMeta.textColor = .secondaryLabelColor
        }
        let count = ExtraDictUpdater.localEntryCount()
        extraMeta.stringValue = "\(count) 条"
        let enabled = loggedIn && !busy
        for button in [compareButton, mergeButton, uploadButton, downloadButton, extraButton] {
            button.isEnabled = enabled
        }
        if !loggedIn {
            setStatus(syncStatus, syncIdleLoggedOut)
        } else if syncStatus.stringValue.isEmpty || syncStatus.stringValue == syncIdleLoggedOut {
            setStatus(syncStatus, syncIdleLoggedIn)
        }
        if extraStatus.stringValue.isEmpty || extraStatus.stringValue == extraIdle {
            setStatus(extraStatus, extraIdle)
        }
    }

    @objc private func compareClicked() {
        run("对比中…") {
            try await CloudDictSync.compare()
        } apply: { [weak self] outcome in
            guard let self else { return }
            self.remoteYaml = outcome.remoteYaml
            self.remoteDocument = outcome.remoteDocument
            self.setStatus(self.syncStatus, outcome.summary)
        }
    }

    @objc private func mergeClicked() {
        let remote = remoteDocument
        run("合并中…") {
            try await CloudDictSync.merge(remote: remote)
        } done: { [weak self] in
            self?.finishWrite(userDictChanged: true)
        }
    }

    @objc private func uploadClicked() {
        run("上传中…") {
            try await CloudDictSync.uploadLocal()
        }
    }

    @objc private func downloadClicked() {
        let cached = remoteYaml
        run("下载中…") {
            try await CloudDictSync.download(cachedYaml: cached)
        } done: { [weak self] in
            self?.finishWrite(userDictChanged: true)
        }
    }

    @objc private func extraClicked() {
        run("正在获取扩展词库…", status: extraStatus) {
            let result = try await CloudDictSync.pullExtra()
            if result.added == 0 {
                return "没有新增，扩展词库共 \(result.wordCount) 条"
            }
            return "新增 \(result.added) 条，扩展词库共 \(result.wordCount) 条"
        } done: { [weak self] in
            self?.finishWrite(status: self?.extraStatus, userDictChanged: false)
            self?.extraMeta.stringValue = "\(ExtraDictUpdater.localEntryCount()) 条"
        }
    }

    // 写回本地后立刻部署；没有引擎时提示从菜单部署。
    private func finishWrite(status: NSTextField? = nil, userDictChanged: Bool) {
        let target = status ?? syncStatus
        let deployNote = deployNow()
        let text = target.stringValue.isEmpty ? deployNote : "\(target.stringValue)。\(deployNote)"
        setStatus(target, text, error: false)
        if userDictChanged {
            NotificationCenter.default.post(name: .meifengUserDictDidChange, object: nil)
        }
    }

    private func deployNow() -> String {
        guard let actions = IMESettingsControls.lexiconActions else {
            return "请从输入法菜单选择「部署」使其生效"
        }
        return actions.deploy().message
    }

    private func run<T>(
        _ pending: String,
        status: NSTextField? = nil,
        work: @escaping () async throws -> T,
        apply: ((T) -> Void)? = nil,
        done: (() -> Void)? = nil
    ) {
        guard !busy else { return }
        busy = true
        let label = status ?? syncStatus
        setStatus(label, pending)
        refresh()
        Task {
            do {
                let value = try await work()
                await MainActor.run {
                    if let text = value as? String {
                        self.setStatus(label, text)
                    }
                    apply?(value)
                    done?()
                    self.busy = false
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.setStatus(label, error.localizedDescription, error: true)
                    self.busy = false
                    self.refresh()
                }
            }
        }
    }

    private func wire(_ button: NSButton, _ action: Selector, tip: String) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.toolTip = tip
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func styleStatus(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.cell?.truncatesLastVisibleLine = true
    }

    private func setStatus(_ label: NSTextField, _ text: String, error: Bool = false) {
        label.textColor = error ? .systemRed : .secondaryLabelColor
        label.stringValue = text
        label.toolTip = text
    }

    // 一行：名称和条数在左，按钮居中靠左，状态占剩余宽度并截断。
    private func makeRow(symbol: String, title: String, meta: NSTextField, buttons: [NSButton], status: NSTextField) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14)
        ])

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true

        meta.font = .systemFont(ofSize: 11)
        meta.textColor = .secondaryLabelColor
        meta.lineBreakMode = .byTruncatingTail
        meta.setContentHuggingPriority(.required, for: .horizontal)
        meta.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        meta.widthAnchor.constraint(lessThanOrEqualToConstant: 96).isActive = true

        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 6
        buttonRow.setContentHuggingPriority(.required, for: .horizontal)
        buttonRow.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [icon, titleLabel, meta, buttonRow, status])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.setContentHuggingPriority(.required, for: .vertical)
        return row
    }
}

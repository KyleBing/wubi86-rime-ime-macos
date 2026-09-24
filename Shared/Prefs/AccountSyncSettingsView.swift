import AppKit

/// 账户页：登录、用户词同步、扩展词库拉取（不展示词条）。
final class AccountSyncSettingsView: NSView {
    private let baseField = NSTextField(string: "")
    private let emailField = NSTextField(string: "")
    private let passwordField = NSSecureTextField(string: "")
    private let accountLabel = NSTextField(wrappingLabelWithString: "")
    private let loginButton = NSButton(title: "登录", target: nil, action: nil)
    private let logoutButton = NSButton(title: "退出登录", target: nil, action: nil)
    private let compareButton = NSButton(title: "对比差异", target: nil, action: nil)
    private let mergeButton = NSButton(title: "增量合并", target: nil, action: nil)
    private let uploadButton = NSButton(title: "本地覆盖云端", target: nil, action: nil)
    private let downloadButton = NSButton(title: "云端覆盖本地", target: nil, action: nil)
    private let extraButton = NSButton(title: "从线上更新扩展词库", target: nil, action: nil)
    private let syncStatus = NSTextField(wrappingLabelWithString: "")
    private let extraStatus = NSTextField(wrappingLabelWithString: "")
    private let loginForm = NSStackView()

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

    private func build() {
        baseField.placeholderString = WubiCloudConfig.defaultBaseURL
        emailField.placeholderString = "邮箱"
        passwordField.placeholderString = "密码"
        for field in [baseField, emailField, passwordField] {
            field.font = .systemFont(ofSize: 13)
        }

        wire(loginButton, #selector(loginClicked))
        wire(logoutButton, #selector(logoutClicked))
        wire(compareButton, #selector(compareClicked))
        wire(mergeButton, #selector(mergeClicked))
        wire(uploadButton, #selector(uploadClicked))
        wire(downloadButton, #selector(downloadClicked))
        wire(extraButton, #selector(extraClicked))

        accountLabel.font = .systemFont(ofSize: 13)
        accountLabel.preferredMaxLayoutWidth = 460
        syncStatus.font = .systemFont(ofSize: 12)
        syncStatus.textColor = .secondaryLabelColor
        syncStatus.preferredMaxLayoutWidth = 460
        syncStatus.maximumNumberOfLines = 6
        extraStatus.font = .systemFont(ofSize: 12)
        extraStatus.textColor = .secondaryLabelColor
        extraStatus.preferredMaxLayoutWidth = 460
        extraStatus.maximumNumberOfLines = 3

        loginForm.orientation = .vertical
        loginForm.alignment = .leading
        loginForm.spacing = 8
        loginForm.addArrangedSubview(labeled("请求地址", baseField))
        loginForm.addArrangedSubview(labeled("邮箱", emailField))
        loginForm.addArrangedSubview(labeled("密码", passwordField))
        loginForm.addArrangedSubview(buttonRow([loginButton]))

        let syncButtons = buttonRow([compareButton, mergeButton, uploadButton, downloadButton])
        let extraNote = note("扩展词库只从线上覆盖到本地，这里不查看、不编辑词条。")
        let syncNote = note("同步对象是用户词库。推荐先对比差异，再选择合并或覆盖。")

        let root = NSStackView(views: [
            sectionTitle("登录"),
            accountLabel,
            loginForm,
            logoutButton,
            sectionTitle("用户词库同步"),
            syncNote,
            syncButtons,
            syncStatus,
            sectionTitle("扩展词库"),
            extraNote,
            extraButton,
            extraStatus
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.setCustomSpacing(16, after: logoutButton)
        root.setCustomSpacing(16, after: syncStatus)
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
        let enabled = loggedIn && !busy
        for button in [compareButton, mergeButton, uploadButton, downloadButton, extraButton] {
            button.isEnabled = enabled
        }
        loginButton.isEnabled = !busy
        if extraStatus.stringValue.isEmpty {
            let count = ExtraDictUpdater.localEntryCount()
            extraStatus.stringValue = "本地扩展词库 \(count) 条"
            extraStatus.textColor = .secondaryLabelColor
        }
    }

    @objc private func loginClicked() {
        let mail = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        guard !mail.isEmpty, !password.isEmpty else {
            setSync("请填写邮箱和密码", error: true)
            return
        }
        let base = baseField.stringValue
        run("登录中…") {
            let info = try await WubiCloudAPI.login(email: mail, password: password, baseURL: base)
            let name = info.nickname.isEmpty ? info.email : info.nickname
            return "登录成功：\(name)"
        } done: { [weak self] in
            self?.passwordField.stringValue = ""
        }
    }

    @objc private func logoutClicked() {
        WubiCloudConfig.logout()
        passwordField.stringValue = ""
        remoteYaml = nil
        remoteDocument = nil
        setSync("已退出登录", error: false)
        refresh()
    }

    @objc private func compareClicked() {
        run("对比中…") {
            let outcome = try await CloudDictSync.compare()
            return outcome
        } apply: { [weak self] outcome in
            self?.remoteYaml = outcome.remoteYaml
            self?.remoteDocument = outcome.remoteDocument
            self?.setSync(outcome.summary, error: false)
        }
    }

    @objc private func mergeClicked() {
        let remote = remoteDocument
        run("合并中…") {
            try await CloudDictSync.merge(remote: remote)
        } done: { [weak self] in
            self?.finishWrite()
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
            self?.finishWrite()
        }
    }

    @objc private func extraClicked() {
        run("正在拉取扩展词库…", status: extraStatus) {
            let result = try await CloudDictSync.pullExtra()
            return "新增 \(result.added) 条，扩展词库共 \(result.wordCount) 条"
        } done: { [weak self] in
            self?.finishWrite(status: self?.extraStatus)
        }
    }

    private func finishWrite(status: NSTextField? = nil) {
        let target = status ?? syncStatus
        let deployNote = deployNow()
        if target.stringValue.isEmpty {
            target.stringValue = deployNote
        } else {
            target.stringValue += "。\(deployNote)"
        }
    }

    // 能部署就立刻部署；系统设置里的偏好面板没有引擎，提示用菜单部署
    private func deployNow() -> String {
        guard let actions = IMESettingsControls.lexiconActions else {
            return "请从输入法菜单选择「部署」使其生效"
        }
        let result = actions.deploy()
        return result.ok ? result.message : result.message
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
        label.textColor = .secondaryLabelColor
        label.stringValue = pending
        refresh()
        Task {
            do {
                let value = try await work()
                await MainActor.run {
                    if let text = value as? String {
                        label.textColor = .secondaryLabelColor
                        label.stringValue = text
                    }
                    apply?(value)
                    done?()
                    self.busy = false
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    label.textColor = .systemRed
                    label.stringValue = error.localizedDescription
                    self.busy = false
                    self.refresh()
                }
            }
        }
    }

    private func setSync(_ text: String, error: Bool) {
        syncStatus.textColor = error ? .systemRed : .secondaryLabelColor
        syncStatus.stringValue = text
    }

    private func wire(_ button: NSButton, _ action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 460
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

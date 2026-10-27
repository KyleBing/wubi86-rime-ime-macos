import AppKit

extension Notification.Name {
    // 同步把用户词写回本地后，词条表据此刷新。
    static let meifengUserDictDidChange = Notification.Name("cn.kylebing.inputmethod.meifengwubi.userDictDidChange")
    // 词库目录切换后，单字字典列表据此重读。
    static let meifengRimeDirectoryDidChange = Notification.Name("cn.kylebing.inputmethod.meifengwubi.rimeDirectoryDidChange")
    // 自动同步开关或一轮同步结束。App 与输入法进程都要收到。
    static let meifengAutoSyncSettingChanged = Notification.Name("cn.kylebing.inputmethod.meifengwubi.autoSyncSettingChanged")
    static let meifengAutoSyncDidFinish = Notification.Name("cn.kylebing.inputmethod.meifengwubi.autoSyncDidFinish")
    // 用户词文件比上次加载新。输入法空闲时增量部署，正在打字则等编码结束。
    static let meifengUserDictNeedsReload = Notification.Name("cn.kylebing.inputmethod.meifengwubi.userDictNeedsReload")
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
    private let registerInfoLabel = NSTextField(wrappingLabelWithString: "")
    private let registerApplyButton = NSButton(title: "在浏览器中申请注册", target: nil, action: nil)
    private let loginForm = NSStackView()
    // 账号数据区：删除线上同步数据 / 注销账号
    private let accountDataSection = NSStackView()
    private let accountDataInfo = NSTextField(wrappingLabelWithString: "")
    private let clearSyncButton = NSButton(title: "删除线上同步数据", target: nil, action: nil)
    private let destroyAccountButton = NSButton(title: "注销账号", target: nil, action: nil)

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

        registerInfoLabel.font = .systemFont(ofSize: 12)
        registerInfoLabel.textColor = .secondaryLabelColor
        registerInfoLabel.preferredMaxLayoutWidth = 460
        registerInfoLabel.stringValue = RegistrationApplyCopy.hint

        registerApplyButton.target = self
        registerApplyButton.action = #selector(openRegisterApplyPage)
        registerApplyButton.bezelStyle = .rounded

        clearSyncButton.target = self
        clearSyncButton.action = #selector(clearSyncClicked)
        clearSyncButton.bezelStyle = .rounded
        destroyAccountButton.target = self
        destroyAccountButton.action = #selector(destroyAccountClicked)
        destroyAccountButton.bezelStyle = .rounded
        accountDataInfo.font = .systemFont(ofSize: 12)
        accountDataInfo.textColor = .secondaryLabelColor
        accountDataInfo.preferredMaxLayoutWidth = 460
        accountDataInfo.stringValue = "删除线上同步数据：清空云端备份的个人词库，同步次数归零；本机词库和账号资料不受影响。\n注销账号：永久删除账号及全部线上数据（个人词库备份、本人提交的词条、邀请码、邮箱验证记录、本人提交的注册申请），无法登录也无法恢复；本机词库仍保留在本地。\n两项操作都需要输入完整账号邮箱后才能执行。"
        accountDataSection.orientation = .vertical
        accountDataSection.alignment = .leading
        accountDataSection.spacing = 8
        accountDataSection.addArrangedSubview(sectionTitle("账号数据"))
        accountDataSection.addArrangedSubview(accountDataInfo)
        accountDataSection.addArrangedSubview(buttonRow([clearSyncButton, destroyAccountButton]))

        let root = NSStackView(views: [
            sectionTitle("登录"),
            accountLabel,
            loginForm,
            logoutButton,
            statusLabel,
            sectionTitle("申请注册"),
            registerInfoLabel,
            buttonRow([registerApplyButton]),
            // 账号数据区放在申请注册下方
            accountDataSection
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
        // 账号数据只在已登录时展示
        accountDataSection.isHidden = !loggedIn
        loginButton.isEnabled = !busy
    }

    @objc private func openRegisterApplyPage() {
        guard let url = WubiCloudConfig.registerApplyURL else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "无法打开申请页面，请检查请求地址"
            return
        }
        NSWorkspace.shared.open(url)
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
                    if UserDictAutoSync.isEnabled {
                        UserDictAutoSync.syncSoon()
                    }
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

    // 删除线上同步数据：只清空云端个人词库，账号保持登录；需输入完整账号邮箱确认
    @objc private func clearSyncClicked() {
        guard !busy else { return }
        guard let mail = confirmByEmail(
            title: "删除线上同步数据",
            message: "云端备份的个人词库会被删除，同步次数归零。本机词库和账号资料不受影响，下次自动同步时会重新上传本机词库。",
            confirmTitle: "删除"
        ) else { return }
        busy = true
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在删除线上同步数据…（\(mail)）"
        refresh()
        Task {
            do {
                let message = try await WubiCloudAPI.clearSyncData()
                await MainActor.run {
                    self.statusLabel.textColor = .systemGreen
                    self.statusLabel.stringValue = message
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

    // 注销账号：先输入完整邮箱，再在服务端删除全部用户数据并清本地登录态
    @objc private func destroyAccountClicked() {
        guard !busy else { return }
        guard confirmByEmail(
            title: "注销账号",
            message: "注销会永久删除账号资料、云端个人词库、本人提交的词条、邀请码、邮箱验证记录和本人提交的注册申请。注销后无法登录，也无法恢复；本机词库仍保留在本地。",
            confirmTitle: "永久注销"
        ) != nil else { return }
        busy = true
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在注销…"
        refresh()
        Task {
            do {
                let message = try await WubiCloudAPI.destroyAccount()
                await MainActor.run {
                    WubiCloudConfig.logout()
                    self.passwordField.stringValue = ""
                    self.statusLabel.textColor = .secondaryLabelColor
                    self.statusLabel.stringValue = message
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

    // 破坏性操作确认：要求完整输入当前账号邮箱，一致才返回输入的邮箱，否则返回 nil
    private func confirmByEmail(title: String, message: String, confirmTitle: String) -> String? {
        let expected = (WubiCloudConfig.userInfo?.email ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "没有读到账号邮箱，请重新登录后再试"
            return nil
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message + "\n\n请输入账号邮箱 \(expected) 以确认。"
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        // 邮箱输入框放在按钮下方，和系统确认框的输入习惯一致
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "输入账号邮箱"
        field.font = .systemFont(ofSize: 13)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.lowercased() == expected.lowercased() else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "邮箱不一致，操作已取消"
            return nil
        }
        return typed
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
    private let autoSyncCheck = NSButton(checkboxWithTitle: "自动同步", target: nil, action: nil)
    private let syncStatus = NSTextField(labelWithString: "")
    private let extraStatus = NSTextField(labelWithString: "")
    private let syncIdleLoggedOut = "请先在「账户」页登录"
    private let syncIdleLoggedIn = "先对比，再合并或覆盖"
    private let syncIdleAuto = "自动同步：启动时、改词约 3 秒后、每 10 分钟；词库有变化就重新加载"
    private let extraIdle = "获取后覆盖本地"

    private var busy = false
    private var autoSyncObserver: NSObjectProtocol?
    private var remoteYaml: String?
    private var remoteDocument: UserDictDocument?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
        autoSyncObserver = DistributedNotificationCenter.default().addObserver(
            forName: .meifengAutoSyncDidFinish,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showStoredAutoSyncResult()
        }
    }

    deinit {
        if let autoSyncObserver {
            DistributedNotificationCenter.default().removeObserver(autoSyncObserver)
        }
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
        autoSyncCheck.target = self
        autoSyncCheck.action = #selector(autoSyncChanged(_:))
        autoSyncCheck.controlSize = .small
        autoSyncCheck.toolTip = "打开后：输入法启动时同步一次；本地用户词改动约 3 秒后同步；运行中每 10 分钟同步一次。本地词库比上次加载新时会重新加载，正在输入则等这次打完。两边都改过的同一条不会自动覆盖。"
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
            buttons: [autoSyncCheck, compareButton, mergeButton, uploadButton, downloadButton],
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
        let syncEnabled = loggedIn && !busy
        for button in [compareButton, mergeButton, uploadButton, downloadButton] {
            button.isEnabled = syncEnabled
        }
        extraButton.isEnabled = !busy
        autoSyncCheck.state = UserDictAutoSync.isEnabled ? .on : .off
        if !loggedIn {
            setStatus(syncStatus, syncIdleLoggedOut)
        } else if isIdleSyncStatus(syncStatus.stringValue) {
            if UserDictAutoSync.isEnabled, UserDictAutoSync.lastResult != nil {
                showStoredAutoSyncResult()
            } else {
                setStatus(syncStatus, UserDictAutoSync.isEnabled ? syncIdleAuto : syncIdleLoggedIn)
            }
        }
        if extraStatus.stringValue.isEmpty || extraStatus.stringValue == extraIdle {
            setStatus(extraStatus, extraIdle)
        }
    }

    @objc private func autoSyncChanged(_ sender: NSButton) {
        UserDictAutoSync.install()
        UserDictAutoSync.isEnabled = sender.state == .on
        if sender.state == .on {
            let text = WubiCloudConfig.isLoggedIn
                ? "自动同步已打开"
                : "自动同步已打开，登录后才会开始"
            setStatus(syncStatus, text, tone: WubiCloudConfig.isLoggedIn ? .success : .idle)
        } else {
            setStatus(syncStatus, "自动同步已关闭")
        }
    }

    // 别盖住刚做完的手动同步结果；只刷新空闲说明和上一轮自动同步。
    private func isIdleSyncStatus(_ text: String) -> Bool {
        text.isEmpty || text == syncIdleLoggedOut || text == syncIdleLoggedIn || text == syncIdleAuto
    }

    private func showStoredAutoSyncResult() {
        guard isIdleSyncStatus(syncStatus.stringValue) || syncStatus.stringValue.hasPrefix("自动同步"),
              let last = UserDictAutoSync.lastResult else { return }
        switch last.tone {
        case .success:
            setStatus(syncStatus, last.text, tone: .success)
        case .error:
            setStatus(syncStatus, last.text, tone: .error)
        case .attention:
            setStatus(syncStatus, last.text, tone: .attention)
        }
    }

    @objc private func compareClicked() {
        run("对比中…") {
            try await CloudDictSync.compare()
        } apply: { [weak self] outcome in
            guard let self else { return }
            self.remoteYaml = outcome.remoteYaml
            self.remoteDocument = outcome.remoteDocument
            self.setStatus(self.syncStatus, "对比完成：\(outcome.summary)", tone: .success)
            self.presentCompare(outcome)
        }
    }

    // 差异放进可滚动弹窗，并在这里选择合并或覆盖。
    private func presentCompare(_ outcome: CloudDictSync.CompareOutcome) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "用户词差异"
        alert.informativeText = outcome.summary
        let report = outcome.diff.detailReport()
        if !report.isEmpty {
            alert.accessoryView = diffTextView(report)
        }

        let steps = compareSteps(for: outcome.diff)
        for step in steps {
            alert.addButton(withTitle: step.title)
        }
        alert.addButton(withTitle: "关闭")

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            guard steps.indices.contains(index) else { return }
            switch steps[index].action {
            case .merge: self.mergeClicked()
            case .upload: self.uploadClicked()
            case .download: self.downloadClicked()
            }
        }
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            let response = alert.runModal()
            DispatchQueue.main.async { finish(response) }
        }
    }

    private enum CompareAction {
        case merge, upload, download
    }

    // 没有云端备份时只能上传；完全一致时只留关闭。
    private func compareSteps(for diff: DictSyncDiff.Result) -> [(title: String, action: CompareAction)] {
        if !diff.hasRemote {
            return [("上传到云端", .upload)]
        }
        if diff.isIdentical {
            return []
        }
        return [
            ("增量合并", .merge),
            ("本地 → 云端", .upload),
            ("本地 ← 云端", .download)
        ]
    }

    private func diffTextView(_ text: String) -> NSView {
        let lineCount = text.components(separatedBy: "\n").count
        let height = min(260, max(64, CGFloat(lineCount) * 18 + 20))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: height))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 508, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        return scroll
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
                return "获取完成：没有新增，扩展词库共 \(result.wordCount) 条"
            }
            return "获取完成：新增 \(result.added) 条，扩展词库共 \(result.wordCount) 条"
        } done: { [weak self] in
            self?.finishWrite(status: self?.extraStatus, userDictChanged: false)
            self?.extraMeta.stringValue = "\(ExtraDictUpdater.localEntryCount()) 条"
        }
    }

    // 写回本地后立刻部署；没有引擎时提示从菜单部署。
    private func finishWrite(status: NSTextField? = nil, userDictChanged: Bool) {
        let target = status ?? syncStatus
        let deploy = deployNow()
        let text = target.stringValue.isEmpty ? deploy.message : "\(target.stringValue)。\(deploy.message)"
        // 写入已经成功时用绿色；部署失败则改成红色，避免看起来像已经生效。
        setStatus(target, text, tone: deploy.ok ? .success : .error)
        if userDictChanged {
            NotificationCenter.default.post(name: .meifengUserDictDidChange, object: nil)
        }
    }

    private func deployNow() -> (ok: Bool, message: String) {
        guard let actions = IMESettingsControls.lexiconActions else {
            return (false, "请从输入法菜单选择「部署」使其生效")
        }
        let result = actions.deploy()
        return (result.ok, result.message)
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
                        self.setStatus(label, text, tone: .success)
                    }
                    apply?(value)
                    done?()
                    self.busy = false
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.setStatus(label, error.localizedDescription, tone: .error)
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
        label.alignment = .left
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
        // 先给一个够用的宽度，layout 里再按实际行宽收紧。
        label.preferredMaxLayoutWidth = 640
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        let click = NSClickGestureRecognizer(target: self, action: #selector(statusClicked(_:)))
        label.addGestureRecognizer(click)
    }

    override func layout() {
        super.layout()
        let width = max(160, bounds.width - 24)
        syncStatus.preferredMaxLayoutWidth = width
        extraStatus.preferredMaxLayoutWidth = width
    }

    // 一行放不下时点文字，弹出完整说明。
    @objc private func statusClicked(_ gesture: NSClickGestureRecognizer) {
        guard let label = gesture.view as? NSTextField else { return }
        let text = label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let pop = NSPopover()
        pop.behavior = .transient
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 12)
        field.preferredMaxLayoutWidth = 340
        let measured = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 340, height: 2000)).height ?? 40
        let height = min(200, max(36, measured))
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 364, height: height + 16))
        field.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -12),
            field.topAnchor.constraint(equalTo: host.topAnchor, constant: 8),
            field.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8)
        ])
        let controller = NSViewController()
        controller.view = host
        pop.contentSize = host.frame.size
        pop.contentViewController = controller
        pop.show(relativeTo: label.bounds, of: label, preferredEdge: .maxY)
    }

    private enum StatusTone {
        case idle, success, error, attention
    }

    // 闲置灰色，成功绿色，失败红色，需要处理的冲突用橙色。
    private func setStatus(_ label: NSTextField, _ text: String, tone: StatusTone = .idle) {
        switch tone {
        case .idle:
            label.textColor = .secondaryLabelColor
        case .success:
            label.textColor = .systemGreen
        case .error:
            label.textColor = .systemRed
        case .attention:
            label.textColor = .systemOrange
        }
        label.stringValue = text
        label.toolTip = text.isEmpty ? nil : text + "\n点击查看全文"
    }

    // 切到用户词页或窗口再次显示时调用。
    func refreshForDisplay() {
        refresh()
    }

    // 按钮占上面一行，说明独占下面整行，点文字可看全文。
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

        let controls = NSStackView(views: [icon, titleLabel, meta, buttonRow])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8

        let column = NSStackView(views: [controls, status])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        column.setContentHuggingPriority(.required, for: .vertical)
        controls.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        status.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }
}

import AppKit
import SwiftUI

struct SetupView: View {
    @Binding var preferOpenCandidatePrefs: Bool
    @State private var status = IMEInstaller.statusText()
    @State private var message = ""
    @State private var isBusy = false
    // Sparkle 未启用时，由这个模型读 update.json 做轻量检查
    @StateObject private var updates = UpdateModel()

    // 版本号取自 Info.plist：营销版本 + 构建号
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "v\(version) (\(build))"
    }
    var body: some View {
        // 不用 ScrollView / Spacer 撑高，窗口高度跟内容走（配合 .contentSize）
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                // 主页用透明枫叶 Logo，不用 AppIcon / 圆角图标。
                if let brand = BrandIcon.settingsImage() {
                    Image(nsImage: brand)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("玫枫五笔")
                            .font(.system(size: 28, weight: .bold))
                        Text(Self.versionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("原生 macOS 输入法 · 明暗皮肤 · 可分享配置")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox("输入法安装") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(status)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("安装 / 更新输入法") { install() }
                            .disabled(isBusy)
                        Button("打开系统设置·输入法") { IMEInstaller.openInputSourcesPrefs() }
                        // 完整扫描仅在注册异常或出现重复项时手动执行。
                        Button("修复 / 清理重复项") {
                            isBusy = true
                            // 扫构建目录很慢，放到后台；TIS 仍回主线程
                            DispatchQueue.global(qos: .userInitiated).async {
                                IMEInstaller.unregisterStaleBuildCopies()
                                DispatchQueue.main.async {
                                    IMEInstaller.reassertInstalledIME()
                                    status = IMEInstaller.statusText()
                                    isBusy = false
                                }
                            }
                        }
                            .help("完整扫描构建目录，清除重复或错误注册；通常不需要执行")
                    }
                    if !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("程序更新") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(updateStatusText)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    if AppUpdater.shared.isAvailable {
                        // 正式包：Sparkle 负责下载、校验、替换与重启
                        HStack(spacing: 12) {
                            Button("检查更新…") { AppUpdater.shared.checkForUpdates() }
                            Toggle("自动检查更新", isOn: Binding(
                                get: { AppUpdater.shared.automaticallyChecksForUpdates },
                                set: { AppUpdater.shared.automaticallyChecksForUpdates = $0 }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    } else {
                        // 开发包 / 未配 EdDSA 公钥：只提示版本并打开下载页
                        HStack(spacing: 12) {
                            Button("检查更新") { updates.check() }
                                .disabled(updates.isChecking)
                            Toggle("启动时自动检查", isOn: $updates.autoCheck)
                                .toggleStyle(.checkbox)
                        }
                        if case .available(let manifest) = updates.state {
                            if let notes = manifest.notes, !notes.isEmpty {
                                ScrollView {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 96)
                            }
                            HStack(spacing: 8) {
                                Button("打开发布页") { updates.openDownloadPage() }
                                Button("以后再说") { updates.skip() }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("输入法设置") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观、按键、用户词与词库目录等，在设置窗口中统一管理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // 完整设置页自带左侧栏，必须用独立大尺寸窗口承载。
                    Button("打开输入法设置") {
                        CandidateSettingsWindow.show()
                    }
                }
                .padding(4)
            }

            GroupBox("使用说明") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. 点「安装 / 更新输入法」后，到「系统设置 → 键盘 → 输入法」。")
                    Text("2. 已启用则可直接切换；若没有：点「+」→ 简体中文 → 玫枫五笔。")
                    Text("3. 菜单栏输入法图标 →「玫枫五笔设置…」。")
                    Text("4. 单独按 Shift 切换中/英；数字 1–9 选词。")
                }
                .font(.callout)
                // 说明文字按窗口宽度换行，完整显示
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            // 反馈渠道：邮箱可直接唤起邮件，QQ 群号提供一键复制。
            GroupBox("反馈与联系") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("邮箱：")
                        Link("kylebing@163.com", destination: URL(string: "mailto:kylebing@163.com")!)
                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("kylebing@163.com", forType: .string)
                            message = "已复制邮箱"
                        }
                        .controlSize(.small)
                    }
                    HStack(spacing: 4) {
                        Text("QQ 群：")
                        Text("1064664481").textSelection(.enabled)
                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("1064664481", forType: .string)
                            message = "已复制 QQ 群号"
                        }
                        .controlSize(.small)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            // 开源引用说明：librime 为 BSD 3-Clause 许可，需保留版权声明。
            GroupBox("开源致谢") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("输入引擎：")
                        Link("librime", destination: URL(string: "https://github.com/rime/librime")!)
                        Text("· 中州韵输入法引擎")
                            .foregroundStyle(.secondary)
                    }
                    Text("Copyright © RIME Developers，基于 BSD 3-Clause License 发布。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("五笔码表：")
                        Link("rime-wubi86-jidian", destination: URL(string: "https://github.com/KyleBing/rime-wubi86-jidian")!)
                        Text("· 86 极点码表")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            UserDictAutoSync.install()
            _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
            // Sparkle 更新宿主后，已安装的输入法副本还是旧版；没在打字时直接换掉
            _ = IMEInstaller.applyComponentUpdateIfIdle()
            status = IMEInstaller.statusText()
            // Sparkle 自己会按 24 小时间隔检查；只有它没启用时才跑清单检查
            if !AppUpdater.shared.isAvailable {
                updates.autoCheckOnLaunch()
            }
            if preferOpenCandidatePrefs {
                CandidateSettingsWindow.show()
                preferOpenCandidatePrefs = false
            }
            // 清 payload 放到后台。主线程上扫盘 + 重注册会卡住十余秒，并且把当前输入法 disable 掉。
            DispatchQueue.global(qos: .utility).async {
                IMEInstaller.unregisterKnownGhostCopies()
                DispatchQueue.main.async {
                    IMEInstaller.ensureEnabledOnMain()
                    status = IMEInstaller.statusText()
                }
            }
        }
        .onChange(of: preferOpenCandidatePrefs) { new in
            if new {
                CandidateSettingsWindow.show()
                preferOpenCandidatePrefs = false
            }
        }
    }

    // 更新区块的说明文字：Sparkle 启用时由它接管，否则显示清单检查结果
    private var updateStatusText: String {
        if AppUpdater.shared.isAvailable {
            return "已启用自动更新，每 24 小时检查一次；也可以随时手动检查。"
        }
        switch updates.state {
        case .idle:
            return "每 24 小时最多自动检查一次。下载后请打开安装包手动安装。"
        case .checking:
            return "正在检查更新…"
        case .upToDate(let version):
            return "已是最新版本（v\(version)）。"
        case .available(let manifest):
            let mandatory = UpdateChecker.isNewer(
                manifest.minimumVersion ?? "",
                than: UpdateChecker.currentVersion
            )
            return "\(mandatory ? "需要更新到" : "发现新版本") v\(manifest.version)（当前 \(Self.versionText)）。"
        case .failed(let message):
            return "检查更新失败：\(message)"
        }
    }

    private func install() {
        isBusy = true
        message = ""
        // 拷贝可后台；TISCreateInputSourceList 必须主线程，否则 SIGTRAP 闪退
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try IMEInstaller.copyEmbeddedIME()
                DispatchQueue.main.async {
                    IMEInstaller.finishInstallOnMain()
                    status = IMEInstaller.statusText()
                    message = "已安装到 ~/Library/Input Methods，并尝试加入菜单栏。若列表仍没有，请到系统设置 → 键盘 → 输入法里删掉再添加一次「玫枫五笔」。"
                    isBusy = false
                }
            } catch {
                DispatchQueue.main.async {
                    message = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }
}

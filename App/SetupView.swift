import AppKit
import SwiftUI

struct SetupView: View {
    @Binding var preferOpenCandidatePrefs: Bool
    @State private var status = IMEInstaller.statusText()
    @State private var message = ""
    @State private var isBusy = false
    @State private var lexiconRefresh = 0
    @State private var goCandidatePrefs = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
            Text("玫枫五笔")
                .font(.system(size: 28, weight: .bold))
            Text("原生 macOS 输入法 · 无皮肤配置 · 系统朴素候选条")
                .foregroundStyle(.secondary)

            GroupBox("输入法安装") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(status)
                        .font(.callout)
                    HStack {
                        Button("安装 / 更新输入法") { install() }
                            .disabled(isBusy)
                        Button("打开系统设置·输入法") { IMEInstaller.openInputSourcesPrefs() }
                        Button("刷新状态") { status = IMEInstaller.statusText() }
                    }
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }

            GroupBox("候选栏") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("方向、字号、序号等（类似系统中文输入法选项）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink("打开候选栏设置") {
                        CandidatePrefsView()
                    }
                }
                .padding(4)
            }

            GroupBox("词库") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("用户词库：\(UserDictWriter.activeURL.path)")
                        .font(.caption)
                        .lineLimit(2)
                    HStack {
                        Button("部署当前配置") { deploy() }
                        Button("复位原始配置") { reset() }
                        NavigationLink("管理用户词") {
                            UserLexiconMacView()
                        }
                    }
                }
                .padding(4)
            }

            GroupBox("使用说明") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. 点「安装 / 更新输入法」后，到「系统设置 → 键盘 → 输入法」。")
                    Text("2. 列表里找「玫枫五笔」或英文名「Meifeng Wubi」（不是鼠须管）。")
                    Text("3. 菜单栏输入法图标 →「玫枫五笔设置…」；或 系统设置 → 键盘 → 输入法。")
                    Text("4. 单独按 Shift 切换中/英；数字 1–9 选词。")
                }
                .font(.callout)
                .padding(4)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .sheet(isPresented: $goCandidatePrefs) {
            NavigationStack {
                CandidatePrefsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { goCandidatePrefs = false }
                        }
                    }
            }
            .frame(width: 460, height: 340)
        }
        }
        .onAppear {
            _ = RimeResourceDeployer.syncBundledResourcesIfNeeded()
            status = IMEInstaller.statusText()
            if preferOpenCandidatePrefs {
                goCandidatePrefs = true
                preferOpenCandidatePrefs = false
            }
        }
        .onChange(of: preferOpenCandidatePrefs) { new in
            if new {
                goCandidatePrefs = true
                preferOpenCandidatePrefs = false
            }
        }
        .id(lexiconRefresh)
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
                    message = "已安装到 ~/Library/Input Methods。请用 Fn/地球键切到「玫枫五笔」试打。"
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

    private func deploy() {
        let result = RimeConfigDeploy.deployNow()
        switch result {
        case .success:
            message = "部署成功"
            lexiconRefresh += 1
        case .failure(let err):
            message = err
        }
    }

    private func reset() {
        let result = RimeConfigDeploy.resetToFactory()
        switch result {
        case .success:
            message = "已复位并部署"
            lexiconRefresh += 1
        case .failure(let err):
            message = err
        }
    }
}

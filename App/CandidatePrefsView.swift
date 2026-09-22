import SwiftUI

/// 候选栏外观设置（对齐系统中文输入法常见选项）
struct CandidatePrefsView: View {
    @State private var orientation = IMEAppearancePrefs.orientation
    @State private var fontSize = IMEAppearancePrefs.fontSize
    @State private var fontName = IMEAppearancePrefs.fontName
    @State private var showPreedit = IMEAppearancePrefs.showPreeditInPanel
    @State private var pageSize = IMEAppearancePrefs.pageSize
    @State private var showIndex = IMEAppearancePrefs.showIndex

    private let fonts = IMESettingsControls.preferredFonts

    var body: some View {
        Form {
            Section(header: Text("候选窗口")) {
                Picker("方向", selection: $orientation) {
                    ForEach(IMEAppearancePrefs.Orientation.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: orientation) { new in
                    IMEAppearancePrefs.orientation = new
                }

                Picker("字体", selection: $fontName) {
                    ForEach(0..<fonts.count, id: \.self) { idx in
                        Text(fonts[idx].title).tag(fonts[idx].name)
                    }
                }
                .onChange(of: fontName) { new in
                    IMEAppearancePrefs.fontName = new
                }

                HStack {
                    Text("字体大小")
                    Slider(value: $fontSize, in: 11...24, step: 1) { _ in
                        IMEAppearancePrefs.fontSize = fontSize
                    }
                    Text("\(Int(fontSize))")
                        .frame(width: 28, alignment: .trailing)
                        .monospacedDigit()
                }

                Toggle("显示编码（候选条内）", isOn: $showPreedit)
                    .onChange(of: showPreedit) { new in
                        IMEAppearancePrefs.showPreeditInPanel = new
                    }

                Toggle("显示序号", isOn: $showIndex)
                    .onChange(of: showIndex) { new in
                        IMEAppearancePrefs.showIndex = new
                    }

                Stepper("每页候选数：\(pageSize)", value: $pageSize, in: 3...9)
                    .onChange(of: pageSize) { new in
                        IMEAppearancePrefs.pageSize = new
                    }
            }

            Section {
                Text("系统设置 → 键盘 → 输入法 中选中「玫枫五笔」也可看到同样选项。修改后立即生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 300)
        .navigationTitle("候选栏设置")
        .onAppear {
            orientation = IMEAppearancePrefs.orientation
            fontSize = IMEAppearancePrefs.fontSize
            fontName = IMEAppearancePrefs.fontName
            showPreedit = IMEAppearancePrefs.showPreeditInPanel
            pageSize = IMEAppearancePrefs.pageSize
            showIndex = IMEAppearancePrefs.showIndex
        }
    }
}

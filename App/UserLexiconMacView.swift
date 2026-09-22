import SwiftUI

/// 简易用户词管理（对齐 iOS 词库核心能力）
struct UserLexiconMacView: View {
    @State private var entries: [UserDictEntry] = []
    @State private var code = ""
    @State private var text = ""
    @State private var tip = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("编码", text: $code)
                    .frame(width: 100)
                TextField("词条", text: $text)
                Button("添加") { add() }
                Button("重新加载") { reload() }
            }
            if !tip.isEmpty {
                Text(tip).font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                    HStack {
                        Text(e.code).frame(width: 72, alignment: .leading).font(.system(.body, design: .monospaced))
                        Text(e.text)
                        Spacer()
                        Button("删") {
                            try? UserDictWriter.removeEntry(e)
                            UserDictWriter.markNeedsDeploy()
                            reload()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding()
        .navigationTitle("用户词库")
        .onAppear(perform: reload)
        .frame(minWidth: 480, minHeight: 360)
    }

    private func reload() {
        entries = UserDictWriter.loadActiveEntries()
    }

    private func add() {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !t.isEmpty, c.count <= 4 else {
            tip = "编码需 1–4 位，词条非空"
            return
        }
        do {
            try UserDictWriter.addEntry(UserDictEntry(code: c, text: t, weight: 100_000))
            UserDictWriter.markNeedsDeploy()
            _ = RimeConfigDeploy.deployNow()
            code = ""
            text = ""
            tip = "已添加并部署"
            reload()
        } catch {
            tip = error.localizedDescription
        }
    }
}

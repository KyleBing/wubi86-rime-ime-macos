import Foundation

/// 标点由输入法处理，不走 Rime 的标点表。
/// 符号内容与 default.custom.yaml 的 half_shape 一致。默认全部直接上屏第一项。
enum PunctuationPrefs {
    enum Mode: String, CaseIterable {
        case direct
        case candidates

        var title: String {
            switch self {
            case .direct: return "直接上屏"
            case .candidates: return "候选列表"
            }
        }
    }

    struct Item {
        let key: String
        let symbols: [String]
        let defaultMode: Mode
    }

    // 符号表与 Resources/Rime/default.custom.yaml 的 half_shape 一致。方式默认全部直接上屏第一项。
    static let items: [Item] = [
        Item(key: ",", symbols: ["，"], defaultMode: .direct),
        Item(key: ".", symbols: ["。"], defaultMode: .direct),
        Item(key: "<", symbols: ["《"], defaultMode: .direct),
        Item(key: ">", symbols: ["》"], defaultMode: .direct),
        Item(key: "/", symbols: ["/"], defaultMode: .direct),
        Item(key: "?", symbols: ["？"], defaultMode: .direct),
        Item(key: ";", symbols: ["；"], defaultMode: .direct),
        Item(key: ":", symbols: ["："], defaultMode: .direct),
        Item(key: "'", symbols: ["‘", "’"], defaultMode: .direct),
        Item(key: "\"", symbols: ["“", "”"], defaultMode: .direct),
        Item(key: "\\", symbols: ["、"], defaultMode: .direct),
        Item(key: "|", symbols: ["|"], defaultMode: .direct),
        Item(key: "`", symbols: ["`"], defaultMode: .direct),
        Item(key: "~", symbols: ["~"], defaultMode: .direct),
        Item(key: "!", symbols: ["！"], defaultMode: .direct),
        Item(key: "@", symbols: ["@"], defaultMode: .direct),
        Item(key: "#", symbols: ["#"], defaultMode: .direct),
        Item(key: "%", symbols: ["%", "％", "°", "℃"], defaultMode: .direct),
        Item(key: "$", symbols: ["￥"], defaultMode: .direct),
        Item(key: "^", symbols: ["……"], defaultMode: .direct),
        Item(key: "&", symbols: ["&"], defaultMode: .direct),
        Item(key: "*", symbols: ["*"], defaultMode: .direct),
        Item(key: "(", symbols: ["（"], defaultMode: .direct),
        Item(key: ")", symbols: ["）"], defaultMode: .direct),
        Item(key: "-", symbols: ["-"], defaultMode: .direct),
        Item(key: "_", symbols: ["——"], defaultMode: .direct),
        Item(key: "+", symbols: ["+"], defaultMode: .direct),
        Item(key: "=", symbols: ["="], defaultMode: .direct),
        Item(key: "[", symbols: ["【"], defaultMode: .direct),
        Item(key: "]", symbols: ["】"], defaultMode: .direct),
        Item(key: "{", symbols: ["「"], defaultMode: .direct),
        Item(key: "}", symbols: ["」"], defaultMode: .direct)
    ]

    private static let suiteName = "cn.kylebing.inputmethod.meifengwubi.prefs"
    private static let storageKey = "punct.outputMode"
    private static let symbolsKey = "punct.symbols"

    static func item(for key: String) -> Item? {
        items.first { $0.key == key }
    }

    static func mode(for key: String) -> Mode {
        let stored = defaults.dictionary(forKey: storageKey) as? [String: String]
        if let raw = stored?[key], let mode = Mode(rawValue: raw) {
            return mode
        }
        return item(for: key)?.defaultMode ?? .direct
    }

    static func setMode(_ mode: Mode, for key: String) {
        var stored = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        stored[key] = mode.rawValue
        defaults.set(stored, forKey: storageKey)
        defaults.synchronize()
    }

    // 用户改过的输出；没改过则用默认符号表。空内容视为不保存，继续用默认。
    static func symbols(for key: String) -> [String] {
        let stored = defaults.dictionary(forKey: symbolsKey) as? [String: [String]]
        if let list = stored?[key]?.filter({ !$0.isEmpty }), !list.isEmpty {
            return list
        }
        return item(for: key)?.symbols ?? [key]
    }

    // 丢掉已保存的输出和方式，下次读取回到默认：每键直接上屏第一项。
    static func restoreDefaults() {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: symbolsKey)
        defaults.synchronize()
    }

    static func setSymbols(_ symbols: [String], for key: String) {
        var stored = defaults.dictionary(forKey: symbolsKey) as? [String: [String]] ?? [:]
        let cleaned = symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if cleaned.isEmpty {
            stored.removeValue(forKey: key)
        } else {
            stored[key] = cleaned
        }
        defaults.set(stored, forKey: symbolsKey)
        defaults.synchronize()
    }

    // 按空白拆成多项，一项里的符号可以是多个字，例如「……」。
    static func parseSymbols(_ text: String) -> [String] {
        text.split { $0.isWhitespace }.map(String.init)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}

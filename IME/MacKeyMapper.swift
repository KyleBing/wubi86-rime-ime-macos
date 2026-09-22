import AppKit
import Carbon
import Foundation

/// macOS 虚拟键码 / 修饰键 → Rime（X11 keysym）按键
enum MacKeyMapper {
    // Rime modifier masks（与 rime key_table 一致）
    static let shiftMask: Int32 = 1 << 0
    static let lockMask: Int32 = 1 << 1
    static let controlMask: Int32 = 1 << 2
    static let altMask: Int32 = 1 << 3
    static let superMask: Int32 = 1 << 4

    struct MappedKey {
        let keyCode: Int32
        let modifiers: Int32
    }

    static func map(event: NSEvent) -> MappedKey? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: Int32 = 0
        if flags.contains(.shift) { mods |= shiftMask }
        if flags.contains(.capsLock) { mods |= lockMask }
        if flags.contains(.control) { mods |= controlMask }
        if flags.contains(.option) { mods |= altMask }
        if flags.contains(.command) { mods |= superMask }

        // 有 Command 的组合键交给系统（复制粘贴等）
        if flags.contains(.command) {
            return nil
        }

        let vk = Int(event.keyCode)
        if let special = specialKeycode(vk) {
            return MappedKey(keyCode: special, modifiers: mods)
        }

        // 可打印字符：优先用 charactersIgnoringModifiers 的小写字母
        if let chars = event.charactersIgnoringModifiers, let ch = chars.unicodeScalars.first {
            let v = Int32(ch.value)
            if (0x20...0x7E).contains(v) {
                // Shift+字母交给 Rime 处理大小写；数字行符号用 characters
                if flags.contains(.shift), let shifted = event.characters?.unicodeScalars.first {
                    let sv = Int32(shifted.value)
                    if (0x20...0x7E).contains(sv) {
                        return MappedKey(keyCode: sv, modifiers: 0)
                    }
                }
                return MappedKey(keyCode: v, modifiers: mods)
            }
        }
        return nil
    }

    private static func specialKeycode(_ vk: Int) -> Int32? {
        switch vk {
        case kVK_Space: return 0x20
        case kVK_Return, kVK_ANSI_KeypadEnter: return 0xff0d // XK_Return
        case kVK_Delete: return 0xff08 // XK_BackSpace
        case kVK_ForwardDelete: return 0xffff // XK_Delete
        case kVK_Escape: return 0xff1b
        case kVK_Tab: return 0xff09
        case kVK_LeftArrow: return 0xff51
        case kVK_RightArrow: return 0xff53
        case kVK_UpArrow: return 0xff52
        case kVK_DownArrow: return 0xff54
        case kVK_PageUp: return 0xff55
        case kVK_PageDown: return 0xff56
        case kVK_Home: return 0xff50
        case kVK_End: return 0xff57
        default: return nil
        }
    }
}

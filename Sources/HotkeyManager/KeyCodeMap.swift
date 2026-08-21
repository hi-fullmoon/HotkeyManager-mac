import Carbon

/// 组合键解析："cmd+shift+1" → Carbon 修饰键位掩码 + keyCode
enum KeyCodeMap {
    /// 解析结果：Carbon 注册参数 + 展示字符串
    struct KeyCombo {
        let keyCode: UInt32
        let modifiers: UInt32
        let display: String
    }

    // MARK: - 组合键解析

    /// 解析 "cmd+1"、"ctrl+alt+a" 形式的组合键：最后一段为按键，其余为修饰键。
    /// 按键名无效时返回 nil。
    static func parse(_ combo: String) -> KeyCombo? {
        let parts = combo.components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        // 空片段（如 "cmd++1"）和未知修饰键都应视为配置错误，不能静默降级成裸按键。
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        guard let keyName = parts.last, let keyCode = keyCodeTable[keyName] else { return nil }
        let modifierNames = parts.dropLast()
        guard modifierNames.allSatisfy({ modifierMap[$0] != nil }) else { return nil }
        let modifiers = modifierNames.reduce(UInt32(0)) { $0 | modifierMap[$1]! }
        // 普通裸按键会劫持正常输入；仅功能键允许不带修饰键独立注册。
        guard modifiers != 0 || unmodifiedKeyNames.contains(keyName) else { return nil }
        return KeyCombo(
            keyCode: keyCode,
            modifiers: modifiers,
            display: displayString(modifiers: modifiers, key: keyName)
        )
    }

    // MARK: - 键名 → keyCode

    private static let keyCodeTable: [String: UInt32] = {
        var table: [String: UInt32] = [
            // 字母
            "a": 0,  "b": 11, "c": 8,  "d": 2, "e": 14,
            "f": 3,  "g": 5,  "h": 4,  "i": 34, "j": 38,
            "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
            "p": 35, "q": 12, "r": 15, "s": 1,  "t": 17,
            "u": 32, "v": 9,  "w": 13, "x": 7,  "y": 16, "z": 6,
            // 数字
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
            "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
            // 特殊键
            "space":      49,
            "return":     36,
            "enter":      36,
            "tab":        48,
            "escape":     53,
            "esc":        53,
            "delete":     51,
            "backspace":  51,
            "up":         126,
            "down":       125,
            "left":       123,
            "right":      124,
        ]
        // 功能键 F1–F15
        let fKeys: [String: UInt32] = [
            "f1": 122, "f2": 120,  "f3": 99,  "f4": 118,
            "f5": 96,  "f6": 97,   "f7": 98,  "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            "f13": 105, "f14": 107, "f15": 113,
        ]
        for (k, v) in fKeys { table[k] = v }
        // Windows 版键名习惯：D0–D9（与直接写 "0"–"9" 等价）
        for digit in 0...9 {
            table["d\(digit)"] = table["\(digit)"]
        }
        return table
    }()

    // MARK: - "Ctrl+Alt" → Carbon 修饰键

    private static let modifierMap: [String: UInt32] = [
        "ctrl":    UInt32(controlKey),
        "control": UInt32(controlKey),
        "alt":     UInt32(optionKey),
        "option":  UInt32(optionKey),
        "opt":     UInt32(optionKey),
        "shift":   UInt32(shiftKey),
        "cmd":     UInt32(cmdKey),
        "command": UInt32(cmdKey),
        "win":     UInt32(cmdKey), // Windows 版的 Win 键习惯映射到 Cmd
    ]

    private static let unmodifiedKeyNames = Set((1...15).map { "f\($0)" })

    // MARK: - keyCode → 键名（录制快捷键用）

    /// 由 keyCode + Carbon 修饰键生成配置字符串，如 "ctrl+shift+a"；无法识别的 keyCode 返回 nil
    static func comboString(keyCode: UInt32, modifiers: UInt32) -> String? {
        guard let keyName = keyCodeToName[keyCode] else { return nil }
        let mods = modifierNameOrder.filter { modifiers & $0.1 != 0 }.map(\.0)
        let combo = (mods + [keyName]).joined(separator: "+")
        return parse(combo) == nil ? nil : combo
    }

    private static let modifierNameOrder: [(String, UInt32)] = [
        ("ctrl", UInt32(controlKey)),
        ("alt", UInt32(optionKey)),
        ("shift", UInt32(shiftKey)),
        ("cmd", UInt32(cmdKey)),
    ]

    /// keyCodeTable 的反向映射，重复 keyCode 取规范名（跳过 enter/esc/backspace/d0–d9 等别名）
    private static let keyCodeToName: [UInt32: String] = {
        let aliases: Set<String> = ["enter", "esc", "backspace"]
        var table: [UInt32: String] = [:]
        for (name, code) in keyCodeTable where !aliases.contains(name) {
            if name.hasPrefix("d"), name.count == 2, name.last?.isNumber == true { continue }
            if table[code] == nil { table[code] = name }
        }
        return table
    }()

    // MARK: - 展示

    private static let displayOrder: [(String, UInt32)] = [
        ("⌃", UInt32(controlKey)),
        ("⌥", UInt32(optionKey)),
        ("⇧", UInt32(shiftKey)),
        ("⌘", UInt32(cmdKey)),
    ]

    /// 菜单/日志展示用快捷键字符串，如 "⌥1"
    private static func displayString(modifiers: UInt32, key: String) -> String {
        let mods = displayOrder.filter { modifiers & $0.1 != 0 }.map(\.0).joined()
        var keyName = key
        let lowered = key.lowercased()
        // "D1" 显示为 "1"
        if lowered.hasPrefix("d"), lowered.count == 2, lowered.last?.isNumber == true {
            keyName = String(lowered.last!)
        }
        return mods + keyName.uppercased()
    }
}

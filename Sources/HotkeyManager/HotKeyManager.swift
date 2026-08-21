import Carbon

/// 基于 Carbon RegisterEventHotKey 的全局热键管理器
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private struct Entry {
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
        var ref: EventHotKeyRef?
    }

    private var entries: [UInt32: Entry] = [:]
    private var eventHandlerRef: EventHandlerRef?

    /// 暂停状态：true 时所有热键已真正注销（UnregisterEventHotKey）
    private(set) var isSuspended = false

    private init() {}

    /// 安装全局事件分发器（只需一次）
    func installGlobalHandler() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                DispatchQueue.main.async {
                    HotKeyManager.shared.entries[hotKeyID.id]?.handler()
                }
            }
            return noErr
        }

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        if status != noErr {
            eventHandlerRef = nil
            NSLog("[HotkeyManager] 全局事件处理器安装失败（status: \(status)）")
        }
    }

    /// 注册一个全局热键，返回是否成功（失败多为与系统/其他应用冲突）
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) -> Bool {
        entries[id] = Entry(keyCode: keyCode, modifiers: modifiers, handler: handler, ref: nil)
        // 暂停期间只记录，恢复时再真正注册
        guard !isSuspended else { return true }
        return carbonRegister(id: id)
    }

    /// 清空全部热键（配置重载前调用）
    func removeAll() {
        unregisterCarbonAll()
        entries.removeAll()
    }

    /// 暂停：真正注销所有热键（对齐 Windows 版暂停行为）
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterCarbonAll()
    }

    /// 恢复：重新注册所有热键，返回注册失败的 id 列表
    @discardableResult
    func resume() -> [UInt32] {
        guard isSuspended else { return [] }
        isSuspended = false
        return entries.keys.sorted().filter { !carbonRegister(id: $0) }
    }

    // MARK: - Carbon 注册/注销

    private func carbonRegister(id: UInt32) -> Bool {
        guard var entry = entries[id] else { return false }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x484B_4D47), // 'HKMG'
            id: id
        )
        let status = RegisterEventHotKey(
            entry.keyCode,
            entry.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            OptionBits(kEventHotKeyNoOptions),
            &ref
        )
        if status == noErr {
            entry.ref = ref
            entries[id] = entry
            return true
        }
        NSLog("[HotkeyManager] 快捷键注册失败（id: \(id), status: \(status)），可能被系统保留或已被独占注册")
        return false
    }

    /// 注销全部 Carbon 热键（保留记录，供恢复时用）
    private func unregisterCarbonAll() {
        for id in entries.keys {
            if let ref = entries[id]?.ref {
                UnregisterEventHotKey(ref)
            }
            entries[id]?.ref = nil
        }
    }
}

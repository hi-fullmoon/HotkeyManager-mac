import AppKit
import Carbon

/// 快捷键录制器：捕获下一次按键并转为配置字符串（如 "alt+1"），
/// 录制期间挂起全局热键，避免按下的组合键触发应用切换
final class HotkeyRecorder {
    /// 录制结束回调：成功为组合键字符串，取消（Esc / 主动取消）为 nil
    var onFinish: ((String?) -> Void)?
    /// 按键无法识别时回调（录制继续）
    var onUnrecognized: (() -> Void)?

    private var eventMonitor: Any?
    /// 录制开始时热键是否处于激活状态（结束后需要恢复）
    private var resumeAfterRecording = false
    private(set) var isRecording = false

    func start() {
        guard !isRecording else { return }
        isRecording = true
        resumeAfterRecording = !HotKeyManager.shared.isSuspended
        if resumeAfterRecording {
            HotKeyManager.shared.suspend()
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil // 消费掉按键，避免传导给菜单等
        }
    }

    func cancel() {
        finish(result: nil)
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)

        // 裸按 Esc 取消录制
        if event.keyCode == 53, modifiers == 0 {
            finish(result: nil)
            return
        }

        guard let combo = KeyCodeMap.comboString(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            onUnrecognized?()
            return
        }
        finish(result: combo)
    }

    private func finish(result: String?) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        if resumeAfterRecording {
            resumeAfterRecording = false
            HotKeyManager.shared.resume()
        }
        onFinish?(result)
    }

    /// NSEvent 修饰键 → Carbon 修饰键位掩码
    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

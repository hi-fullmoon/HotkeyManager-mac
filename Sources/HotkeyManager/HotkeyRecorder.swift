import AppKit
import Carbon

/// 快捷键录制器：捕获下一次按键并转为配置字符串（如 "alt+1"），
/// 录制期间挂起全局热键，避免按下的组合键触发应用切换
@MainActor
final class HotkeyRecorder {
    /// 录制结束回调：成功为组合键字符串，取消（Esc / 主动取消）为 nil
    var onFinish: ((String?) -> Void)?
    /// 按键无法识别时回调（录制继续）
    var onUnrecognized: (() -> Void)?

    private var eventMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
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
        // 本地事件监听在应用失去激活后收不到按键；此时必须恢复全局快捷键。
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancel()
            }
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
        guard isRecording else { return }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            resignActiveObserver = nil
        }
        isRecording = false
        if resumeAfterRecording {
            resumeAfterRecording = false
            let failed = HotKeyManager.shared.resume()
            if !failed.isEmpty {
                Notify.send(title: "部分快捷键恢复失败", body: "快捷键可能被系统保留或其他应用独占，请换一个组合键。")
            }
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

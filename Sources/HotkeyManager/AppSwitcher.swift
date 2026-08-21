import AppKit
import ApplicationServices

/// 切换引擎，语义对齐 Windows 版 WindowService.ToggleCore：
/// 未运行 → 启动；已运行非前台（含已隐藏）→ unhide + 置前；已在前台 → 隐藏
enum AppSwitcher {
    private static let forceRestoreDefaultsKey = "ForceRestoreMinimizedWindows"

    static var isForceRestoreEnabled: Bool {
        UserDefaults.standard.bool(forKey: forceRestoreDefaultsKey)
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 开启时主动请求一次辅助功能权限；未授权期间仍会走普通 reopen，不影响应用激活。
    @discardableResult
    static func setForceRestoreEnabled(_ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: forceRestoreDefaultsKey)
        guard enabled, !AXIsProcessTrusted() else { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func toggle(_ entry: HotkeyEntry) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == entry.bundleId
        }) else {
            // 未运行 → 启动（activates: true 自动到前台）
            launch(entry)
            return
        }

        if !app.isActive {
            // 已运行但非前台（含已隐藏、窗口已最小化）→ 还原并置前
            app.unhide()
            unminimizeIfEnabled(app: app)
            activateWithReopen(entry, fallback: app)  // 等价点击 Dock 图标：置前 + 系统还原最小化窗口
            return
        }

        // 已在前台 → 隐藏
        app.hide()
    }

    /// 用户主动开启且已授权时，通过 AX 可靠地还原目标应用的全部最小化窗口。
    private static func unminimizeIfEnabled(app: NSRunningApplication) {
        guard isForceRestoreEnabled, AXIsProcessTrusted() else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    private static func launch(_ entry: HotkeyEntry) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleId) else {
            Notify.send(
                title: "HotkeyManager",
                body: "找不到应用（\(entry.bundleId)），请检查 bundleId 是否正确、应用是否已安装"
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                DispatchQueue.main.async {
                    Notify.send(
                        title: "HotkeyManager",
                        body: "启动「\(displayName(for: entry))」失败：\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// 通过 reopen 语义激活已运行的应用：openApplication 对已运行应用会发送
    /// kAEReopenApplication，与点击 Dock 图标一致——置前的同时由系统还原最小化窗口，
    /// 不需要辅助功能权限。解析不到应用 URL 时回退为普通 activate。
    private static func activateWithReopen(_ entry: HotkeyEntry, fallback app: NSRunningApplication) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleId) else {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if error != nil {
                DispatchQueue.main.async {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
    }

    /// 通知文案用的应用名：运行中取 localizedName，否则从 .app 包名推导，兜底 bundleId
    private static func displayName(for entry: HotkeyEntry, app: NSRunningApplication? = nil) -> String {
        if let name = app?.localizedName, !name.isEmpty {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleId) {
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            if !name.isEmpty {
                return name
            }
        }
        return entry.bundleId
    }
}

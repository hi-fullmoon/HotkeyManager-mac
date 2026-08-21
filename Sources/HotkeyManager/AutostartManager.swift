import ServiceManagement

/// 开机自启管理（SMAppService，macOS 13+）
enum AutostartManager {
    enum State {
        case disabled
        case enabled
        case requiresApproval
        case unavailable
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// 设置开机自启，返回操作是否成功
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[HotkeyManager] 开机自启设置失败：\(error.localizedDescription)")
            Notify.send(title: "HotkeyManager", body: "开机自启设置失败：\(error.localizedDescription)")
            return false
        }
    }
}

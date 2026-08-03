import AppKit

/// 组装根：加载配置、注册热键、连接菜单与热重载
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private var watcher: ConfigWatcher?
    private var statusBar: StatusBarController?
    private lazy var hotkeyListWindow = HotkeyListWindowController(configStore: configStore)
    private var config = AppConfig()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notify.requestAuthorization()
        configStore.saveDefaultIfNeeded()
        HotKeyManager.shared.installGlobalHandler()

        statusBar = StatusBarController(
            onOpenConfig: { [weak self] in
                self?.configStore.openInEditor()
            },
            onShowHotkeyList: { [weak self] in
                self?.hotkeyListWindow.showWindow(nil)
            },
            onTogglePause: { paused in
                if paused {
                    HotKeyManager.shared.suspend()
                    Notify.send(title: "HotkeyManager", body: "热键已暂停")
                } else {
                    let failed = HotKeyManager.shared.resume()
                    if !failed.isEmpty {
                        Notify.send(
                            title: "部分热键恢复失败",
                            body: "可能被其他应用占用，请调整配置后重新保存。"
                        )
                    } else {
                        Notify.send(title: "HotkeyManager", body: "热键已恢复")
                    }
                }
            }
        )

        reloadConfig()

        // 配置文件保存即热重载
        watcher = ConfigWatcher(fileURL: configStore.fileURL) { [weak self] in
            self?.reloadConfig()
        }
        watcher?.start()
    }

    /// 重新解析配置并全量重注册热键；解析失败保留旧热键并提示
    private func reloadConfig() {
        guard let newConfig = configStore.load() else {
            Notify.send(
                title: "配置解析失败",
                body: ".hotkeymanager.json 格式有误，已保留原有热键，请修正后重新保存。"
            )
            return
        }
        config = newConfig

        let manager = HotKeyManager.shared
        manager.removeAll()
        var failed: [String] = []
        for (index, entry) in config.hotkeys.enumerated() {
            // 窗口里 + 添加但尚未录制的占位条目：跳过注册，不算失败
            guard !entry.key.isEmpty else { continue }
            guard let combo = KeyCodeMap.parse(entry.key) else {
                NSLog("[HotkeyManager] 无法识别的组合键：\(entry.key)")
                failed.append(entry.key)
                continue
            }
            let ok = manager.register(keyCode: combo.keyCode, modifiers: combo.modifiers, id: UInt32(index + 1)) {
                AppSwitcher.toggle(entry)
            }
            if !ok { failed.append(combo.display) }
        }

        if !failed.isEmpty {
            Notify.send(
                title: "部分热键注册失败",
                body: "以下热键键名无效或已被占用：\(failed.joined(separator: "、"))"
            )
        }
    }
}

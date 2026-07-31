import AppKit

/// 菜单栏图标与下拉菜单（对齐 Windows 版托盘菜单）
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let pauseItem = NSMenuItem()
    private let autostartItem = NSMenuItem()
    private var isPaused = false

    private let onOpenConfig: () -> Void
    private let onReload: () -> Void
    private let onTogglePause: (Bool) -> Void

    init(onOpenConfig: @escaping () -> Void,
         onReload: @escaping () -> Void,
         onTogglePause: @escaping (Bool) -> Void) {
        self.onOpenConfig = onOpenConfig
        self.onReload = onReload
        self.onTogglePause = onTogglePause
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = StatusBarController.makeBoltImage()
        buildMenu()
    }

    /// 菜单栏模板图标：与应用图标一致的闪电形状。
    /// template 模式下系统只取 alpha，自动适配深浅色菜单栏。
    private static func makeBoltImage() -> NSImage {
        // 与应用图标相同的 zigzag 顶点（基于 256 逻辑坐标，y 向下）
        let bolt: [(CGFloat, CGFloat)] = [
            (150, 36), (82, 142), (122, 142),
            (102, 214), (176, 106), (132, 106),
        ]
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let s = rect.width / 256
            let path = NSBezierPath()
            for (i, p) in bolt.enumerated() {
                // 翻转 y：图标坐标系 y 向下，AppKit 默认 y 向上
                let point = NSPoint(x: p.0 * s, y: rect.height - p.1 * s)
                i == 0 ? path.move(to: point) : path.line(to: point)
            }
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func buildMenu() {
        let menu = NSMenu()

        menu.addItem(makeItem(title: "打开配置文件", action: #selector(openConfigAction), key: "o"))
        menu.addItem(makeItem(title: "重新加载配置", action: #selector(reloadAction), key: "r"))
        menu.addItem(.separator())

        pauseItem.title = "暂停热键"
        pauseItem.action = #selector(togglePauseAction)
        pauseItem.target = self
        menu.addItem(pauseItem)

        autostartItem.title = AutostartManager.isEnabled ? "关闭开机自启" : "开启开机自启"
        autostartItem.action = #selector(toggleAutostartAction)
        autostartItem.target = self
        menu.addItem(autostartItem)

        menu.addItem(.separator())
        menu.addItem(makeItem(title: "退出", action: #selector(quitAction), key: "q"))

        statusItem.menu = menu
    }

    private func makeItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openConfigAction() { onOpenConfig() }
    @objc private func reloadAction() { onReload() }

    /// 暂停 ⇄ 恢复：暂停时真正注销全部热键（对齐 Windows 版行为）
    @objc private func togglePauseAction() {
        isPaused.toggle()
        pauseItem.title = isPaused ? "恢复热键" : "暂停热键"
        onTogglePause(isPaused)
    }

    /// 开启 ⇄ 关闭开机自启，标题按实际操作结果刷新（失败提示由 AutostartManager 发出）
    @objc private func toggleAutostartAction() {
        let target = !AutostartManager.isEnabled
        if AutostartManager.setEnabled(target) {
            autostartItem.title = AutostartManager.isEnabled ? "关闭开机自启" : "开启开机自启"
            Notify.send(title: "HotkeyManager", body: target ? "开机自启已开启" : "开机自启已关闭")
        }
    }

    @objc private func quitAction() { NSApp.terminate(nil) }
}

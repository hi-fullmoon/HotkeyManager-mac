import AppKit

/// 菜单栏图标与下拉菜单（对齐 Windows 版托盘菜单）
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let pauseItem = NSMenuItem()
    private let autostartItem = NSMenuItem()
    private var isPaused = false

    private let onOpenConfig: () -> Void
    private let onShowHotkeyList: () -> Void
    private let onTogglePause: (Bool) -> Void

    init(onOpenConfig: @escaping () -> Void,
         onShowHotkeyList: @escaping () -> Void,
         onTogglePause: @escaping (Bool) -> Void) {
        self.onOpenConfig = onOpenConfig
        self.onShowHotkeyList = onShowHotkeyList
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
        let side: CGFloat = 20
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            // 按闪电的包围盒等比缩放到画布内（留少许边距），避免形状在画布中显得偏小
            let xs = bolt.map { $0.0 }, ys = bolt.map { $0.1 }
            let minX = xs.min()!, maxX = xs.max()!
            let minY = ys.min()!, maxY = ys.max()!
            let margin: CGFloat = 1.5
            let s = min((rect.width - margin * 2) / (maxX - minX),
                        (rect.height - margin * 2) / (maxY - minY))
            let offsetX = (rect.width - (maxX - minX) * s) / 2
            let offsetY = (rect.height - (maxY - minY) * s) / 2
            let path = NSBezierPath()
            for (i, p) in bolt.enumerated() {
                // 翻转 y：图标坐标系 y 向下，AppKit 默认 y 向上
                let point = NSPoint(x: offsetX + (p.0 - minX) * s,
                                    y: rect.height - (offsetY + (p.1 - minY) * s))
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
        menu.addItem(makeItem(title: "设置快捷键", action: #selector(showHotkeyListAction), key: "l"))
        menu.addItem(.separator())

        pauseItem.title = "暂停快捷键"
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
    @objc private func showHotkeyListAction() { onShowHotkeyList() }

    /// 暂停 ⇄ 恢复：暂停时真正注销全部热键（对齐 Windows 版行为）
    @objc private func togglePauseAction() {
        isPaused.toggle()
        pauseItem.title = isPaused ? "恢复快捷键" : "暂停快捷键"
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

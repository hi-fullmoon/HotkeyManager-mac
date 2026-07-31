import AppKit

// 纯代码启动，无 Storyboard、无主窗口
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 菜单栏应用，不出现在 Dock
app.run()

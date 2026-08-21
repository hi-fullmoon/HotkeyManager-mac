import UserNotifications

/// 用户通知封装：UNUserNotificationCenter 不可用时退化为 NSLog 打印
enum Notify {
    /// 点击状态栏菜单时 App 处于前台，系统默认不显示前台 App 的横幅，
    /// 需在 delegate 中显式返回 .banner 才能弹出提示
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }

    private static let delegate = Delegate()

    /// 启动时请求一次通知授权
    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("[HotkeyManager] 通知授权失败：\(error.localizedDescription)")
            } else if !granted {
                NSLog("[HotkeyManager] 通知权限未授予，请到 系统设置 → 通知 → HotkeyManager 中开启")
            }
        }
    }

    static func send(title: String, body: String) {
        // 日志兜底：通知中心不可用时仍可从 Console / log stream 看到
        NSLog("[HotkeyManager] %@：%@", title, body)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[HotkeyManager] 通知发送失败：\(error.localizedDescription)")
            }
        }
    }
}

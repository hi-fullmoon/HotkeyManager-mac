import UserNotifications

/// 用户通知封装：UNUserNotificationCenter 不可用时退化为 NSLog 打印
enum Notify {
    /// 启动时请求一次通知授权
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("[HotkeyManager] 通知授权失败：\(error.localizedDescription)")
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

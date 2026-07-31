import AppKit

// MARK: - 配置模型（小驼峰 schema：组合键 + bundleId，其余信息运行时推导）

/// 单个热键配置
/// - key: 组合键字符串，如 "cmd+1"、"ctrl+alt+a"，最后一段为按键，其余为修饰键
/// - bundleId: 目标应用 Bundle Identifier（运行中查找、未运行启动、展示名称均由它推导）
/// - hideMode: 前台再按时的行为，"hide"（默认）或 "minimize"
struct HotkeyEntry: Codable {
    var key: String = ""
    var bundleId: String = ""
    var hideMode: String = "hide"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId) ?? ""
        hideMode = try c.decodeIfPresent(String.self, forKey: .hideMode) ?? "hide"
    }
}

struct AppConfig: Codable {
    var hotkeys: [HotkeyEntry] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkeys = try c.decodeIfPresent([HotkeyEntry].self, forKey: .hotkeys) ?? []
    }
}

// MARK: - 配置文件存取

/// 配置文件存取：~/.hotkeymanager.json（个人目录下的隐藏文件）
final class ConfigStore {
    let fileURL: URL

    init() {
        fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hotkeymanager.json")
    }

    /// 首次运行时写入默认模板（内容与仓库根目录 config.json 一致）
    func saveDefaultIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try Self.defaultTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
            NSLog("[HotkeyManager] 已创建默认配置：\(fileURL.path)")
        } catch {
            NSLog("[HotkeyManager] 写入默认配置失败：\(error.localizedDescription)")
        }
    }

    /// 读取配置；文件缺失或格式错误返回 nil，由调用方决定保留旧配置
    func load() -> AppConfig? {
        guard let data = try? Data(contentsOf: fileURL) else {
            NSLog("[HotkeyManager] 配置文件不可读：\(fileURL.path)")
            return nil
        }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            NSLog("[HotkeyManager] 配置解析失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 用默认编辑器打开配置文件
    func openInEditor() {
        NSWorkspace.shared.open(fileURL)
    }

    /// 默认配置模板（与仓库根目录 config.json 保持一致）
    static let defaultTemplate = """
    {
      "hotkeys": [
        { "key": "alt+1", "bundleId": "com.tencent.xinWeChat", "hideMode": "hide" },
        { "key": "alt+2", "bundleId": "com.google.Chrome", "hideMode": "hide" },
        { "key": "alt+3", "bundleId": "com.apple.Terminal", "hideMode": "hide" },
        { "key": "alt+4", "bundleId": "com.microsoft.VSCode", "hideMode": "hide" },
        { "key": "alt+5", "bundleId": "md.obsidian", "hideMode": "hide" }
      ]
    }
    """
}

// MARK: - 配置文件热重载监听

/// 监听 config.json 变化并防抖触发回调（编辑器保存 → 300ms 后重载）
final class ConfigWatcher {
    private let fileURL: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounceItem: DispatchWorkItem?

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    func start() {
        openAndWatch()
    }

    private func openAndWatch() {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            // 文件暂时不存在（原子保存的间隙），稍后重试
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openAndWatch()
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleEvent()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    private func handleEvent() {
        // 无论何种事件都重建监听：编辑器原子保存会替换文件，旧 fd 已失效
        source?.cancel()
        source = nil
        openAndWatch()

        // 300ms 防抖：连续多次保存只触发一次重载
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}

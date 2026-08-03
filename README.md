# HotkeyManager (macOS)

macOS 全局热键工具（Windows 版 [HotkeyManager](../HotkeyManager) 的移植）：按一个快捷键切换任意应用的显示/隐藏。例如 `⌘1` 呼出微信，再按一次隐藏回去。

纯 Swift + AppKit，Swift Package 构建，零第三方依赖。菜单栏运行，无 Dock 图标。

## 功能

- 任意数量的「热键 → 应用」映射，全部写在 `~/.hotkeymanager.json` 里
- 应用未运行时自动按配置路径启动
- 已运行未前台（含已隐藏）→ 还原并置前；已在前台 → 隐藏
- 配置文件保存即热重载（300ms 防抖，解析失败保留旧热键并提示）
- 「设置快捷键」图形窗口：点击录制快捷键、文件选择器添加应用、移除、拖拽排序，保存后自动生效
- 菜单栏菜单：打开配置文件 / 设置快捷键 / 暂停快捷键 / 开关开机自启 / 退出

## 构建与运行

```bash
./build.sh
open HotkeyManager.app
```

`build.sh` 会执行 `swift build -c release`，把产物组装成 `HotkeyManager.app` 并做 ad-hoc 签名（让辅助功能等 TCC 授权记录在重编译后保持稳定）。

开发调试也可以直接：

```bash
swift build
swift run
```

## 配置说明（~/.hotkeymanager.json）

配置文件位于 `~/.hotkeymanager.json`（个人目录下的隐藏文件），首次运行自动写入默认模板。菜单栏图标 →「打开配置文件」可直接编辑，保存后自动热重载。

```json
{
  "hotkeys": [
    { "key": "cmd+1", "bundleId": "com.tencent.xinWeChat" }
  ]
}
```

| 字段 | 说明 |
|------|------|
| `key` | 组合键，`+` 分隔，最后一段为按键、其余为修饰键。修饰键：`ctrl`（⌃）/ `alt`（⌥）/ `shift`（⇧）/ `cmd`（⌘，兼容 `win` 写法）；按键名：`0`~`9`（兼容 `D0`~`D9` 写法）、`F1`~`F15`、`A`~`Z`、`Space`、`Return`、`Tab`、`Escape`、方向键 `Up`/`Down`/`Left`/`Right` 等。例：`"cmd+1"`、`"ctrl+alt+a"` |
| `bundleId` | 应用 Bundle Identifier：查找运行中应用、未运行时解析路径启动、通知展示名均由它推导 |

查询应用 BundleId：

```bash
osascript -e 'id of app "WeChat"'
```

常用：`com.tencent.xinWeChat`（微信）、`com.google.Chrome`（Chrome）、`com.microsoft.VSCode`（VS Code）、`md.obsidian`（Obsidian）、`com.apple.Terminal`（终端）。

## 注意事项

- 热键被系统或其他应用先注册时会失败，菜单栏会弹通知提示，换一个组合即可
- 全局热键用 Carbon `RegisterEventHotKey` 实现，**不需要**辅助功能权限；只有「还原其他应用被最小化的窗口」需要（首次触发会弹授权引导，未授权时仅跳过还原，不影响置前）
- 「暂停热键」会真正注销所有热键（`UnregisterEventHotKey`），恢复时重新注册
- 开机自启基于 `SMAppService`，开关状态可在 系统设置 → 通用 → 登录项 中查看
- 修改代码后重新执行 `./build.sh` 即可，ad-hoc 签名保持授权记录不失效

## 项目结构

```
├── Package.swift
├── Sources/HotkeyManager/
│   ├── main.swift               # 入口，.accessory 激活策略
│   ├── AppDelegate.swift        # 组装各服务，配置变更 → 全量重注册
│   ├── Config.swift             # Codable 模型 + 存取 + DispatchSource 热重载
│   ├── KeyCodeMap.swift         # 组合键 ⇄ Carbon 修饰键 + keyCode（含录制用反向映射）
│   ├── HotKeyManager.swift      # Carbon RegisterEventHotKey 注册/注销/暂停/恢复
│   ├── AppSwitcher.swift        # 切换核心：启动 / 置前 / 隐藏 / AX 还原最小化窗口
│   ├── HotkeyListWindowController.swift # 设置快捷键窗口（重录 / 添加 / 移除 / 拖拽排序）
│   ├── HotkeyRecorder.swift     # 录制按键 → 组合键字符串（录制期间挂起全局热键）
│   ├── StatusBarController.swift# 菜单栏图标与中文菜单
│   ├── AutostartManager.swift   # SMAppService 开机自启
│   └── Notify.swift             # UNUserNotificationCenter 通知（失败 NSLog 兜底）
├── Resources/Info.plist         # LSUIElement = true
├── config.json                  # 默认配置模板（与首启写入的内容一致）
└── build.sh                     # Release 构建 + 组装 .app + ad-hoc 签名
```

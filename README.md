# HotkeyManager for macOS

macOS 全局快捷键工具。按下快捷键即可启动、显示或隐藏指定应用，例如按 `⌘1` 呼出微信，再按一次将其隐藏。

使用 Swift、AppKit 和 Carbon 实现，无第三方依赖。应用常驻菜单栏，不显示 Dock 图标。

## 功能

- 为应用录制全局快捷键
- 启动、激活或隐藏目标应用
- 添加、移除及拖拽排序应用
- 配置文件热重载
- 暂停快捷键、开机自启
- 可选强制还原最小化窗口

## 要求

- macOS 13.0 或更高版本
- Swift 5.9 或兼容版本

## 构建与安装

```bash
./build.sh
open HotkeyManager.app
```

`build.sh` 会执行 Release 构建、组装应用并进行 ad-hoc 签名。长期使用可复制到应用程序目录：

```bash
ditto HotkeyManager.app /Applications/HotkeyManager.app
open /Applications/HotkeyManager.app
```

开发和测试：

```bash
swift run
swift test
```

## 使用

点击菜单栏闪电图标：

- **设置快捷键**：添加应用、录制快捷键、移除或拖拽排序
- **打开配置文件**：编辑 `~/.hotkeymanager.json`
- **暂停快捷键**：注销或恢复全部快捷键
- **强制还原最小化窗口**：使用辅助功能权限还原窗口
- **开启开机自启**：通过 macOS 登录项启动

## 配置

配置文件位于 `~/.hotkeymanager.json`，首次启动时自动创建：

```json
{
  "hotkeys": [
    { "key": "cmd+1", "bundleId": "com.tencent.xinWeChat" },
    { "key": "cmd+2", "bundleId": "com.google.Chrome" }
  ]
}
```

- `key`：以 `+` 分隔的组合键，例如 `cmd+1`、`ctrl+alt+a`
- `bundleId`：目标应用的 Bundle Identifier

支持 `ctrl`、`alt`、`shift`、`cmd` 修饰键，以及字母、数字、`F1`～`F15`、方向键和常用功能键。普通按键至少需要一个修饰键，功能键可以单独使用。

查询应用 Bundle Identifier：

```bash
osascript -e 'id of app "WeChat"'
```

配置保存后自动生效；JSON 格式错误时会保留上一份有效配置。

## 权限

- 常规快捷键和应用切换不需要辅助功能权限。
- 开启“强制还原最小化窗口”后，需要在“系统设置 → 隐私与安全性 → 辅助功能”中授权。
- 开机自启状态可在“系统设置 → 通用 → 登录项”中管理。

## 打包

```bash
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent \
  HotkeyManager.app dist/HotkeyManager-0.1.0-macOS-arm64.zip
```

`HotkeyManager.app/` 和 `dist/` 已加入 `.gitignore`。

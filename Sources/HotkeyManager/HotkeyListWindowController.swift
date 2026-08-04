import AppKit
import UniformTypeIdentifiers

/// 设置快捷键窗口：展示当前配置的热键
/// 快捷键列内点击按钮即可重新录制；表格下方 + / - 按钮添加 / 移除条目；支持拖拽排序
final class HotkeyListWindowController: NSWindowController {
    private struct Row {
        let name: String
        let keyDisplay: String
        let icon: NSImage?
        /// 对应 config.hotkeys 的下标
        let entryIndex: Int
    }

    /// 窗口关闭回调：AppDelegate 借此释放窗口控制器，关闭后不常驻内存
    var onWindowClose: (() -> Void)?

    private let configStore: ConfigStore
    private let recorder = HotkeyRecorder()
    private var config = AppConfig()
    private var rows: [Row] = []
    private var visibleRows: [Row] = []

    /// 正在录制的 config.hotkeys 下标，nil 表示未在录制
    private var recordingIndex: Int?

    /// 行内拖拽排序用的私有粘贴板类型
    private static let rowDragType = NSPasteboard.PasteboardType("dev.hotkeymanager.row")

    /// 正在拖拽的条目下标（validateDrop 过滤原地放置用），nil 表示未在拖拽
    private var dragSourceEntryIndex: Int?

    private let tableView = NSTableView()

    /// 表格下方的 + / - 分段控件（对齐 macOS 系统列表样式）
    private lazy var addRemoveControl: NSSegmentedControl = {
        let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加快捷键")
        let minus = NSImage(systemSymbolName: "minus", accessibilityDescription: "移除快捷键")
        let control = NSSegmentedControl(
            images: [plus, minus].compactMap { $0 },
            trackingMode: .momentary,
            target: self,
            action: #selector(addRemoveClicked(_:))
        )
        control.segmentStyle = .smallSquare
        control.setEnabled(false, forSegment: 1) // 未选中行时 - 不可用
        return control
    }()

    init(configStore: ConfigStore) {
        self.configStore = configStore
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 304, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置快捷键"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 不可用")
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        // LSUIElement 应用需显式激活，窗口才能置前并接收键盘输入
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    // MARK: - UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let appColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        appColumn.title = "应用"
        appColumn.width = 150
        let keyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        keyColumn.title = "快捷键"
        keyColumn.width = 100

        // 不允许用户拖动调列宽，但保留表格自动伸缩（配合 uniformColumnAutoresizingStyle 让列始终填满表格宽度）
        for column in [appColumn, keyColumn] {
            column.resizingMask = .autoresizingMask
        }

        tableView.addTableColumn(appColumn)
        tableView.addTableColumn(keyColumn)
        tableView.rowHeight = 26
        tableView.dataSource = self
        tableView.delegate = self
        // 列随表格宽度等比伸缩，避免出现横向滚动或右侧空白
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        // 行内拖拽排序
        tableView.registerForDraggedTypes([Self.rowDragType])
        tableView.draggingDestinationFeedbackStyle = .gap

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        addRemoveControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addRemoveControl)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            addRemoveControl.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            addRemoveControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            addRemoveControl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - 数据

    private func reload() {
        config = configStore.load() ?? AppConfig()
        rows = config.hotkeys.enumerated().map { index, entry in
            let (name, icon) = Self.resolve(bundleId: entry.bundleId)
            let display = KeyCodeMap.parse(entry.key)?.display ?? (entry.key.isEmpty ? "未设置" : entry.key)
            return Row(name: name, keyDisplay: display, icon: icon, entryIndex: index)
        }
        applyFilter()
    }

    /// 应用名与图标由 bundleId 推导：运行中取实时信息，未运行从 .app 包推导
    private static func resolve(bundleId: String) -> (name: String, icon: NSImage?) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return (app.localizedName ?? bundleId, downscaledIcon(app.icon))
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            return (name.isEmpty ? bundleId : name, downscaledIcon(NSWorkspace.shared.icon(forFile: url.path)))
        }
        return (bundleId, nil)
    }

    /// app.icon / icon(forFile:) 返回的 NSImage 最大带 1024×1024 位图（单张数 MB），
    /// 而单元格里只显示 20pt。统一重绘为 40×40 px（20pt @2x）再交给行缓存，
    /// 避免每条配置常驻一张全尺寸图标
    private static func downscaledIcon(_ icon: NSImage?) -> NSImage? {
        guard let icon else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 40, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return icon }
        rep.size = NSSize(width: 20, height: 20)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // rep.size 为 20pt 时上下文按 2x 映射到 40px，这里要按点坐标绘制
        icon.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20),
                  from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let scaled = NSImage(size: NSSize(width: 20, height: 20))
        scaled.addRepresentation(rep)
        return scaled
    }

    private func applyFilter() {
        visibleRows = rows
        tableView.reloadData()
    }

    /// 组合键与其他条目的 keyCode + 修饰键是否冲突（excluding 为编辑中的条目下标）
    private func hasKeyConflict(_ combo: String, excluding index: Int?) -> Bool {
        guard let newCombo = KeyCodeMap.parse(combo) else { return false }
        return config.hotkeys.enumerated().contains { i, entry in
            if let index, i == index { return false }
            guard let existing = KeyCodeMap.parse(entry.key) else { return false }
            return existing.keyCode == newCombo.keyCode && existing.modifiers == newCombo.modifiers
        }
    }

    /// 只刷新某行的快捷键列（录制开始/结束时切换按钮文案）
    private func refreshKeyCell(_ entryIndex: Int) {
        guard let row = visibleRows.firstIndex(where: { $0.entryIndex == entryIndex }),
              let column = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == "key" }) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: column))
    }

    // MARK: - 动作

    /// 点击快捷键列按钮：录制中再点为取消；录制其他行时先取消再切换
    @objc private func keyCellClicked(_ sender: NSButton) {
        let entryIndex = sender.tag
        let wasRecordingThis = recorder.isRecording && recordingIndex == entryIndex
        if recorder.isRecording {
            recorder.cancel()
        }
        if wasRecordingThis { return }

        if let row = visibleRows.firstIndex(where: { $0.entryIndex == entryIndex }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        startRecording(entryIndex: entryIndex)
    }

    // MARK: - 重新录制

    private func startRecording(entryIndex: Int) {
        recordingIndex = entryIndex
        refreshKeyCell(entryIndex)

        recorder.onUnrecognized = { /* 按键无法识别：继续等待下一次按键 */ }
        recorder.onFinish = { [weak self] combo in
            guard let self else { return }
            self.recordingIndex = nil
            self.refreshKeyCell(entryIndex)
            guard let combo else { return } // Esc / 再点按钮取消
            self.applyRecorded(combo, to: entryIndex)
        }
        recorder.start()
    }

    private func applyRecorded(_ combo: String, to entryIndex: Int) {
        guard entryIndex < config.hotkeys.count else { return }

        if hasKeyConflict(combo, excluding: entryIndex) {
            let display = KeyCodeMap.parse(combo)?.display ?? combo
            Notify.send(title: "快捷键冲突", body: "\(display) 已被其他条目占用，请换一个")
            return
        }

        config.hotkeys[entryIndex].key = combo
        let entry = config.hotkeys[entryIndex]
        let display = KeyCodeMap.parse(combo)?.display ?? combo
        guard configStore.save(config) else {
            Notify.send(title: "HotkeyManager", body: "保存配置失败，详见日志")
            return
        }

        // 保存后 ConfigWatcher 会自动热重载热键
        Notify.send(title: "HotkeyManager", body: "「\(Self.resolve(bundleId: entry.bundleId).name)」快捷键已更新为 \(display)")
        reload()
        // 重新选中刚才的条目
        if let row = visibleRows.firstIndex(where: { $0.entryIndex == entryIndex }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    // MARK: - 添加 / 移除

    /// + / - 分段控件：0 = 添加，1 = 移除
    @objc private func addRemoveClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            addButtonClicked()
        } else {
            removeButtonClicked()
        }
    }

    /// + ：系统文件选择器选择 .app，读取 bundleId 后新增一行（快捷键留空，点击「未设置」录制）
    @objc private func addButtonClicked() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.addApp(url: url)
        }
    }

    private func addApp(url: URL) {
        guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else {
            Notify.send(title: "HotkeyManager", body: "无法读取该应用的 Bundle ID")
            return
        }

        // 已存在相同 bundleId 的条目：选中它而不是重复添加
        if let existing = config.hotkeys.firstIndex(where: { $0.bundleId == bundleId }) {
            if let row = visibleRows.firstIndex(where: { $0.entryIndex == existing }) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
            }
            return
        }

        var entry = HotkeyEntry()
        entry.bundleId = bundleId
        config.hotkeys.append(entry)
        guard configStore.save(config) else {
            Notify.send(title: "HotkeyManager", body: "保存配置失败，详见日志")
            return
        }

        let newIndex = config.hotkeys.count - 1
        reload()
        if let row = visibleRows.firstIndex(where: { $0.entryIndex == newIndex }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
    }

    /// - ：确认后移除选中条目的快捷键
    @objc private func removeButtonClicked() {
        let row = tableView.selectedRow
        guard row >= 0, row < visibleRows.count, let window else { return }
        let item = visibleRows[row]

        let alert = NSAlert()
        alert.messageText = "移除快捷键？"
        alert.informativeText = "将移除「\(item.name)」的快捷键 \(item.keyDisplay)。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.config.hotkeys.remove(at: item.entryIndex)
            guard self.configStore.save(self.config) else {
                Notify.send(title: "HotkeyManager", body: "保存配置失败，详见日志")
                return
            }
            Notify.send(title: "HotkeyManager", body: "已移除「\(item.name)」快捷键")
            self.reload()
        }
    }
}

// MARK: - NSTableViewDataSource / NSTableViewDelegate

extension HotkeyListWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleRows.count
    }

    /// 显式提供行高：.gap 拖拽反馈需要 delegate 方法，仅设置 rowHeight 属性会导致拖拽时行抖动
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        26
    }

    /// 拖拽起点：把条目的 config.hotkeys 下标写入粘贴板
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row < visibleRows.count else { return nil }
        dragSourceEntryIndex = visibleRows[row].entryIndex
        let item = NSPasteboardItem()
        item.setString(String(visibleRows[row].entryIndex), forType: Self.rowDragType)
        return item
    }

    /// 自定义拖拽图像：PDF 快照整行（默认实现在本表格上只渲染出应用图标）
    func tableView(_ tableView: NSTableView, draggingImageForRowsAt rowIndexes: IndexSet, with event: NSEvent, offset dragImageOffset: NSPointPointer) -> NSImage {
        guard let row = rowIndexes.first,
              let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { return NSImage() }
        let rowFrame = tableView.rect(ofRow: row)
        let image = NSImage(data: rowView.dataWithPDF(inside: rowView.bounds)) ?? NSImage(size: rowFrame.size)

        // 让图像相对光标的位置与抓取点一致（表格为翻转坐标，grabY 自行顶向下量）
        let mouseInTable = tableView.convert(event.locationInWindow, from: nil)
        let grabX = mouseInTable.x - rowFrame.minX
        let grabY = mouseInTable.y - rowFrame.minY
        dragImageOffset.pointee = NSPoint(x: -grabX, y: grabY - rowFrame.height)
        return image
    }

    /// 只允许来自本表格的拖拽，且插入到行间隙（不允许覆盖到行上）；
    /// 落回原地（源行自身或紧邻其后）返回 []，不显示插入间隙——避免拖拽一开始间隙开阖导致列表抖动
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView else { return [] }
        if dropOperation == .on {
            tableView.setDropRow(row, dropOperation: .above)
        }
        if let from = dragSourceEntryIndex {
            let to = row < visibleRows.count ? visibleRows[row].entryIndex : config.hotkeys.count
            if to == from || to == from + 1 { return [] }
        }
        return .move
    }

    /// 落点：调整 config.hotkeys 顺序并保存（ConfigWatcher 自动热重载），重新选中移动的条目
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let pasteboardItem = info.draggingPasteboard.pasteboardItems?.first,
              let from = pasteboardItem.string(forType: Self.rowDragType).flatMap(Int.init),
              from < config.hotkeys.count else { return false }
        dragSourceEntryIndex = nil

        // 落回原地：不改动、不保存
        let toInOriginal = row < visibleRows.count ? visibleRows[row].entryIndex : config.hotkeys.count
        guard toInOriginal != from, toInOriginal != from + 1 else { return false }

        // 顺序变化会使录制中的条目下标失效，先取消录制
        if recorder.isRecording { recorder.cancel() }

        let entry = config.hotkeys.remove(at: from)
        let to = toInOriginal > from ? toInOriginal - 1 : toInOriginal // 先删除导致目标下标前移
        config.hotkeys.insert(entry, at: to)

        guard configStore.save(config) else {
            Notify.send(title: "HotkeyManager", body: "保存配置失败，详见日志")
            reload()
            return false
        }
        reload()
        if let newRow = visibleRows.firstIndex(where: { $0.entryIndex == to }) {
            tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(newRow)
        }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier, row < visibleRows.count else { return nil }
        let item = visibleRows[row]
        let cell = tableView.makeView(withIdentifier: identifier, owner: self)
            ?? makeCell(identifier: identifier)
        switch identifier.rawValue {
        case "app":
            let cell = cell as? NSTableCellView
            cell?.textField?.stringValue = item.name
            cell?.imageView?.image = item.icon
        default:
            // 快捷键列：按钮形式，点击进入录制；录制中显示小号字体的提示文案
            if let button = cell.subviews.compactMap({ $0 as? NSButton }).first {
                button.tag = item.entryIndex
                if recordingIndex == item.entryIndex {
                    button.title = "录制中…"
                    button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                } else {
                    button.title = item.keyDisplay
                    button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                }
            }
        }
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSView {
        // 快捷键列：按钮单元格
        if identifier.rawValue == "key" {
            let container = NSView()
            container.identifier = identifier

            let button = NSButton(title: "", target: self, action: #selector(keyCellClicked(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            button.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(button)
            NSLayoutConstraint.activate([
                // 撑满列宽：普通 / 录制中两种状态按钮宽度一致，不随文案变化
                button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            return container
        }

        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = DragSnapshotTextField(labelWithString: "")
        textField.wantsLayer = true
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = textField
        cell.addSubview(textField)

        if identifier.rawValue == "app" {
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.imageView = imageView
            cell.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 20),
                imageView.heightAnchor.constraint(equalToConstant: 20),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        addRemoveControl.setEnabled(row >= 0 && row < visibleRows.count, forSegment: 1)
    }
}

// MARK: - NSWindowDelegate

extension HotkeyListWindowController: NSWindowDelegate {
    /// 关闭窗口时若仍在录制，按取消处理（恢复热键，不保存）
    func windowWillClose(_ notification: Notification) {
        if recorder.isRecording {
            recorder.cancel()
        }
        onWindowClose?()
    }
}

// MARK: - DragSnapshotTextField

/// 使用普通 backing layer 的文本框
/// 默认 NSTextField 的文本走 NSTextLayer，在表格拖拽快照/拖拽中行渲染里会被跳过（文本空白），
/// 改用普通 layer 后拖拽过程中文本可正常渲染
private final class DragSnapshotTextField: NSTextField {
    override func makeBackingLayer() -> CALayer {
        CALayer()
    }
}

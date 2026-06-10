import AppKit

// Go2Term — 在终端中打开 Finder 当前目录（Go2Shell 的 ARM 原生替代品）
//
// 行为：
//   - 未安装到 Finder 工具栏时打开 → 显示安装/设置窗口
//   - 已安装时点击（或打开）→ 直接在终端打开 Finder 当前目录
//   - 按住 ⌥ 打开，或 `open -a Go2Term --args config` → 强制显示设置窗口
//   - `--args install` / `--args uninstall` → 命令行安装/卸载工具栏项
//
// Finder 工具栏存储格式（macOS 26/27 实测）：
//   NSToolbar Configuration Browser → TB Item Identifiers 里第三方项是
//   "com.apple.finder.loc"+若干尾部空格；TB Item Plists 以该项的**数组下标**
//   （字符串形式）为 key，值为 {_CFURLAliasData, _CFURLString, _CFURLStringType}。

let kTerminalKey = "TerminalApp"
let kFinderDomain = "com.apple.finder"
let kToolbarKey = "NSToolbar Configuration Browser"
let kLocBase = "com.apple.finder.loc"

// MARK: - 本地化（跟随系统语言）

enum L10n {
    static let zh = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false

    static var subtitle: String { zh
        ? "安装到 Finder 工具栏后，点击图标即可在终端打开当前目录。"
        : "Install to the Finder toolbar, then click the icon to open the current folder in your terminal." }
    static var terminalLabel: String { zh ? "终端：" : "Terminal:" }
    static var installButton: String { zh ? "一键安装到 Finder 工具栏" : "Install to Finder Toolbar" }
    static var removeButton: String { zh ? "从 Finder 工具栏移除" : "Remove from Finder Toolbar" }
    static var installedStatus: String { zh
        ? "已安装 ✓  点击工具栏图标即可使用"
        : "Installed ✓  Click the toolbar icon to use" }
    static var notInstalledStatus: String { zh
        ? "也可以打开「自定工具栏…」后把 Go2Term 拖进去"
        : "Or drag Go2Term into the toolbar via \u{201C}Customize Toolbar…\u{201D}" }
    static var installAlertTitle: String { zh ? "安装到 Finder 工具栏？" : "Install to the Finder toolbar?" }
    static var removeAlertTitle: String { zh ? "从 Finder 工具栏移除？" : "Remove from the Finder toolbar?" }
    static var alertInfo: String { zh
        ? "需要重启 Finder 才能生效（已打开的 Finder 窗口会重新打开，不影响文件）。"
        : "Finder needs to relaunch for this to take effect. Open Finder windows will reopen; your files are not affected." }
    static var installConfirm: String { zh ? "安装并重启 Finder" : "Install & Relaunch Finder" }
    static var removeConfirm: String { zh ? "移除并重启 Finder" : "Remove & Relaunch Finder" }
    static var cancel: String { zh ? "取消" : "Cancel" }
    static var quit: String { zh ? "退出 Go2Term" : "Quit Go2Term" }
}

// MARK: - Finder 工具栏配置读写

func toolbarConfig() -> [String: Any] {
    CFPreferencesCopyAppValue(kToolbarKey as CFString, kFinderDomain as CFString) as? [String: Any] ?? [:]
}

func saveToolbarConfig(_ config: [String: Any]) {
    CFPreferencesSetAppValue(kToolbarKey as CFString, config as CFDictionary, kFinderDomain as CFString)
    CFPreferencesAppSynchronize(kFinderDomain as CFString)
}

/// 把工具栏项的 plist 数据解析回文件路径（支持 file-id URL 和 alias/bookmark 数据）
func resolvedPath(of itemPlist: Any?) -> String? {
    guard let item = itemPlist as? [String: Any] else { return nil }
    if let s = item["_CFURLString"] as? String, let u = URL(string: s) {
        // file:///.file/id=... 这类 file-reference URL 转回真实路径
        if let fp = (u as NSURL).filePathURL { return fp.path }
        if u.isFileURL { return u.path }
    }
    if let data = item["_CFURLAliasData"] as? Data {
        var stale = false
        // 现代 bookmark 数据
        if let u = try? URL(resolvingBookmarkData: data, options: .withoutUI,
                            relativeTo: nil, bookmarkDataIsStale: &stale) {
            return u.path
        }
        // 旧式 AliasRecord → 转成 bookmark 再解析
        if let bm = CFURLCreateBookmarkDataFromAliasRecord(nil, data as CFData)?.takeRetainedValue() {
            if let u = try? URL(resolvingBookmarkData: bm as Data, options: .withoutUI,
                                relativeTo: nil, bookmarkDataIsStale: &stale) {
                return u.path
            }
        }
    }
    return nil
}

/// 工具栏项的 (标识符, 项数据) 有序列表；TB Item Plists 以下标字符串为 key
func toolbarItems(of config: [String: Any]) -> [(id: String, plist: Any?)] {
    let ids = config["TB Item Identifiers"] as? [String] ?? []
    let plists = config["TB Item Plists"] as? [String: Any] ?? [:]
    return ids.enumerated().map { (i, id) in (id, plists[String(i)]) }
}

func rebuildConfig(_ config: inout [String: Any], items: [(id: String, plist: Any?)]) {
    config["TB Item Identifiers"] = items.map(\.id)
    var plists: [String: Any] = [:]
    for (i, item) in items.enumerated() where item.plist != nil {
        plists[String(i)] = item.plist
    }
    if plists.isEmpty {
        config.removeValue(forKey: "TB Item Plists")
    } else {
        config["TB Item Plists"] = plists
    }
}

func isGo2TermItem(_ item: (id: String, plist: Any?)) -> Bool {
    item.id.hasPrefix(kLocBase) && resolvedPath(of: item.plist)?.contains("Go2Term.app") == true
}

func isInstalledInToolbar() -> Bool {
    toolbarItems(of: toolbarConfig()).contains(where: isGo2TermItem)
}

func restartFinder() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    p.arguments = ["Finder"]
    try? p.run()
}

func installToToolbar() {
    var config = toolbarConfig()
    var items = toolbarItems(of: config)
    if items.isEmpty {
        let defaults = config["TB Default Item Identifiers"] as? [String]
            ?? ["com.apple.finder.BACK", "com.apple.finder.SWCH", "NSToolbarSpaceItem",
                "com.apple.finder.ARNG", "com.apple.finder.SHAR", "com.apple.finder.LABL",
                "com.apple.finder.ACTN", "NSToolbarSpaceItem", "com.apple.finder.SRCH"]
        items = defaults.map { ($0, nil) }
    }
    items.removeAll(where: isGo2TermItem)

    let appURL = Bundle.main.bundleURL
    guard let bookmark = try? appURL.bookmarkData() else { return }

    // 标识符要在现有 loc 项中唯一（Finder 用尾部空格区分）
    var loc = kLocBase + " "
    while items.contains(where: { $0.id == loc }) { loc += " " }

    let itemPlist: [String: Any] = [
        "_CFURLAliasData": bookmark,
        "_CFURLString": appURL.absoluteString.hasSuffix("/") ? appURL.absoluteString : appURL.absoluteString + "/",
        "_CFURLStringType": 15,
    ]
    let idx = items.firstIndex { $0.id == "com.apple.finder.SRCH" } ?? items.count
    items.insert((loc, itemPlist), at: idx)

    rebuildConfig(&config, items: items)
    saveToolbarConfig(config)
    restartFinder()
}

func removeFromToolbar() {
    var config = toolbarConfig()
    var items = toolbarItems(of: config)
    items.removeAll(where: isGo2TermItem)
    rebuildConfig(&config, items: items)
    saveToolbarConfig(config)
    restartFinder()
}

// MARK: - 打开终端

func finderCurrentPath() -> String {
    // insertion location = 最前面 Finder 窗口的目录；没有窗口时是桌面
    let source = """
    tell application "Finder"
        try
            return POSIX path of (insertion location as alias)
        on error
            return POSIX path of (path to desktop)
        end try
    end tell
    """
    var error: NSDictionary?
    if let result = NSAppleScript(source: source)?.executeAndReturnError(&error),
       let path = result.stringValue {
        return path
    }
    return NSHomeDirectory()
}

func openTerminal() {
    let terminal = UserDefaults.standard.string(forKey: kTerminalKey) ?? "iTerm"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-a", terminal, finderCurrentPath()]
    try? p.run()
    p.waitUntilExit()
}

// MARK: - 设置窗口

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var installButton: NSButton!
    var statusLabel: NSTextField!

    static let knownTerminals: [(name: String, bundleID: String)] = [
        ("iTerm", "com.googlecode.iterm2"),
        ("Terminal", "com.apple.Terminal"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("Ghostty", "com.mitchellh.ghostty"),
        ("kitty", "net.kovidgoyal.kitty"),
        ("Alacritty", "org.alacritty"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("install") {
            installToToolbar()
            NSApp.terminate(nil)
            return
        }
        if args.contains("uninstall") {
            removeFromToolbar()
            NSApp.terminate(nil)
            return
        }
        let wantsConfig = args.contains("config") || NSEvent.modifierFlags.contains(.option)
        if isInstalledInToolbar() && !wantsConfig {
            openTerminal()
            NSApp.terminate(nil)
            return
        }
        showWindow()
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        buildMenu()

        let icon = NSApp.applicationIconImage ?? NSImage()
        let iconView = NSImageView(image: icon)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let title = NSTextField(labelWithString: "Go2Term")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let subtitle = NSTextField(wrappingLabelWithString: L10n.subtitle)
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.preferredMaxLayoutWidth = 320

        // 终端选择
        let terminalLabel = NSTextField(labelWithString: L10n.terminalLabel)
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        let installed = Self.knownTerminals.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
        popup.addItems(withTitles: installed.map(\.name))
        let current = UserDefaults.standard.string(forKey: kTerminalKey) ?? "iTerm"
        popup.selectItem(withTitle: current)
        if popup.selectedItem == nil { popup.selectItem(at: 0) }
        popup.target = self
        popup.action = #selector(terminalChanged(_:))
        // 保证默认值落盘
        if let t = popup.selectedItem?.title { UserDefaults.standard.set(t, forKey: kTerminalKey) }

        let terminalRow = NSStackView(views: [terminalLabel, popup])
        terminalRow.orientation = .horizontal
        terminalRow.spacing = 8

        installButton = NSButton(title: "", target: self, action: #selector(toggleInstall(_:)))
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = "\r"
        installButton.controlSize = .large

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .center

        refreshInstallState()

        let stack = NSStackView(views: [iconView, title, subtitle, terminalRow, installButton, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 36, bottom: 24, right: 36)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Go2Term"
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshInstallState() {
        if isInstalledInToolbar() {
            installButton.title = L10n.removeButton
            statusLabel.stringValue = L10n.installedStatus
        } else {
            installButton.title = L10n.installButton
            statusLabel.stringValue = L10n.notInstalledStatus
        }
    }

    @objc func terminalChanged(_ sender: NSPopUpButton) {
        if let t = sender.selectedItem?.title {
            UserDefaults.standard.set(t, forKey: kTerminalKey)
        }
    }

    @objc func toggleInstall(_ sender: NSButton) {
        let installing = !isInstalledInToolbar()
        let alert = NSAlert()
        alert.messageText = installing ? L10n.installAlertTitle : L10n.removeAlertTitle
        alert.informativeText = L10n.alertInfo
        alert.addButton(withTitle: installing ? L10n.installConfirm : L10n.removeConfirm)
        alert.addButton(withTitle: L10n.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if installing { installToToolbar() } else { removeFromToolbar() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.refreshInstallState()
        }
    }

    func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

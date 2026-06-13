import AppKit
import ApplicationServices

// Go2Term — 在终端中打开 Finder 当前目录（Go2Shell 的 ARM 原生替代品）
//
// 行为：
//   - 未安装到 Finder 工具栏时打开 → 显示安装/设置窗口
//   - 已安装时点击（或打开）→ 弹出菜单：在此处打开终端 / 在此处新建文件 / 设置…
//     （设置里可关掉菜单，恢复单击直接开终端）
//   - 按住 ⌥ 打开，或 `open -a Go2Term --args config` → 强制显示设置窗口
//   - `--args install` / `--args uninstall` → 命令行安装/卸载工具栏项
//
// Finder 工具栏存储格式（macOS 26/27 实测）：
//   NSToolbar Configuration Browser → TB Item Identifiers 里第三方项是
//   "com.apple.finder.loc"+若干尾部空格；TB Item Plists 以该项的**数组下标**
//   （字符串形式）为 key，值为 {_CFURLAliasData, _CFURLString, _CFURLStringType}。

let kTerminalKey = "TerminalApp"
let kShowMenuKey = "ShowActionMenu"
let kAXPromptedKey = "DidPromptAccessibility"
let kAutoCheckKey = "AutoCheckUpdates"
let kLastCheckKey = "LastUpdateCheck"
let kFinderDomain = "com.apple.finder"
let kToolbarKey = "NSToolbar Configuration Browser"
let kLocBase = "com.apple.finder.loc"

// 更新相关常量
let kRepo = "BuGTEa/Go2Term"
let kTeamID = "8KT244CY2B"
let kReleasePage = "https://github.com/\(kRepo)/releases/latest"
let kUpdateCheckInterval: TimeInterval = 24 * 60 * 60  // 24h 节流

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
    static var menuOpenTerminal: String { zh ? "在此处打开终端" : "Open Terminal Here" }
    static var menuOpenVSCode: String { zh ? "在此处打开 VS Code" : "Open in VS Code Here" }
    static var menuNewFile: String { zh ? "在此处新建文件" : "New File Here" }
    static var menuSettings: String { zh ? "设置…" : "Settings…" }
    static var showMenuToggle: String { zh
        ? "点击图标时显示菜单（关闭则直接打开终端）"
        : "Show menu on click (off: open terminal directly)" }
    static var newFileBaseName: String { zh ? "未命名" : "untitled" }
    static var axAlertTitle: String { zh ? "启用自动重命名？" : "Enable auto-rename?" }
    static var axAlertInfo: String { zh
        ? "授予「辅助功能」权限后，新建的文件会自动进入重命名状态。在系统设置中开启 Go2Term，下次新建文件即生效。"
        : "With Accessibility permission, newly created files automatically enter rename mode. Turn on Go2Term in System Settings; it takes effect the next time you create a file." }
    static var axAllow: String { zh ? "前往授权" : "Open System Settings" }
    static var axLater: String { zh ? "暂不" : "Not Now" }

    // 更新
    static var autoCheckToggle: String { zh ? "启动时自动检查更新" : "Check for updates on launch" }
    static var checkUpdatesButton: String { zh ? "检查更新" : "Check for Updates" }
    static var checking: String { zh ? "正在检查更新…" : "Checking for updates…" }
    static func upToDate(_ v: String) -> String { zh ? "已是最新版本（\(v)）" : "You're up to date (\(v))" }
    static var checkFailed: String { zh ? "检查更新失败，请稍后重试" : "Update check failed, please try again later" }
    static func updateFound(_ v: String) -> String { zh ? "发现新版本 \(v)" : "Version \(v) is available" }
    static var updateInstall: String { zh ? "下载并安装" : "Download & Install" }
    static var updateNotes: String { zh ? "更新内容" : "Release Notes" }
    static var updateLater: String { zh ? "以后再说" : "Later" }
    static var updating: String { zh ? "正在下载并安装…" : "Downloading & installing…" }
    static func updateDone(_ v: String) -> String { zh
        ? "已更新到 \(v)，下次点击图标即用新版本。"
        : "Updated to \(v). The new version is used on your next click." }
    static var updateDoneTitle: String { zh ? "更新完成" : "Update Complete" }
    static var updateFailedTitle: String { zh ? "更新失败" : "Update Failed" }
    static var openDownloadPage: String { zh ? "打开下载页" : "Open Download Page" }
    static var ok: String { zh ? "好" : "OK" }
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

// macOS 26 的 Finder 启动时会丢弃 bookmark 格式的工具栏项（27 接受），必须写
// Finder 自己用的 legacy AliasRecord。Alias Manager 对 Swift 不可见，走 dlsym。
private typealias FSPathMakeRefFn = @convention(c) (UnsafePointer<UInt8>, UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Int32
private typealias FSNewAliasFn = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int16
private typealias GetHandleSizeFn = @convention(c) (UnsafeRawPointer) -> Int

func legacyAliasData(forPath path: String) -> Data? {
    guard let lib = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY),
          let pmrSym = dlsym(lib, "FSPathMakeRef"),
          let naSym = dlsym(lib, "FSNewAlias"),
          let ghsSym = dlsym(lib, "GetHandleSize") else { return nil }
    let pathMakeRef = unsafeBitCast(pmrSym, to: FSPathMakeRefFn.self)
    let newAlias = unsafeBitCast(naSym, to: FSNewAliasFn.self)
    let handleSize = unsafeBitCast(ghsSym, to: GetHandleSizeFn.self)

    var fsref = [UInt8](repeating: 0, count: 80)
    let status = path.withCString { cs in
        fsref.withUnsafeMutableBytes { buf in
            pathMakeRef(UnsafeRawPointer(cs).assumingMemoryBound(to: UInt8.self), buf.baseAddress!, nil)
        }
    }
    guard status == 0 else { return nil }
    var handle: UnsafeMutableRawPointer?
    let err = fsref.withUnsafeBytes { buf in newAlias(nil, buf.baseAddress!, &handle) }
    guard err == 0, let h = handle else { return nil }
    let size = handleSize(h)
    guard size > 0, let block = h.assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee else { return nil }
    return Data(bytes: block, count: size)  // 进程即退，Handle 不回收
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
    // 老格式优先（macOS 26 必需）；alias 创建失败时退回 bookmark（27 可用）
    guard let aliasData = legacyAliasData(forPath: appURL.path) ?? (try? appURL.bookmarkData()) else { return }
    var urlString = appURL.absoluteString
    if let ref = CFURLCreateFileReferenceURL(nil, appURL as CFURL, nil)?.takeRetainedValue() {
        urlString = CFURLGetString(ref) as String
    }
    if !urlString.hasSuffix("/") { urlString += "/" }

    // 标识符要在现有 loc 项中唯一（Finder 用尾部空格区分）
    var loc = kLocBase + " "
    while items.contains(where: { $0.id == loc }) { loc += " " }

    let itemPlist: [String: Any] = [
        "_CFURLAliasData": aliasData,
        "_CFURLString": urlString,
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

/// 诊断日志：NSLog 在 macOS 26 上不进 unified log，落盘到 /tmp/g2t.log。
/// 默认关闭，`defaults write com.panbo.Go2Term DebugLog -bool true` 开启
let g2tDebugLogEnabled = UserDefaults.standard.bool(forKey: "DebugLog")

func g2tLog(_ msg: String) {
    guard g2tDebugLogEnabled else { return }
    let line = "\(Date()) \(msg)\n"
    if let fh = FileHandle(forWritingAtPath: "/tmp/g2t.log") {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        try? fh.close()
    } else {
        try? line.write(toFile: "/tmp/g2t.log", atomically: true, encoding: .utf8)
    }
}

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
        g2tLog("finderCurrentPath ok: \(path)")
        return path
    }
    g2tLog("finderCurrentPath FAILED: \(error?.description ?? "nil result")")
    return NSHomeDirectory()
}

/// 启动事件的发送者是不是 Finder。点工具栏图标由 Finder 发起；
/// 从 Apps 启动器、聚焦、Dock、命令行等其他入口打开 → 应进设置窗口
func launchedByFinder() -> Bool {
    guard let ev = NSAppleEventManager.shared().currentAppleEvent,
          let pid = ev.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
          let sender = NSRunningApplication(processIdentifier: pid)
    else {
        g2tLog("launch sender: unknown")
        return false
    }
    g2tLog("launch sender: pid=\(pid) \(sender.bundleIdentifier ?? "?")")
    return sender.bundleIdentifier == "com.apple.finder"
}

/// 区分「点工具栏图标」和「在访达里双击 app 本体」：双击启动时 Finder 的选中项
/// 必然包含本 app 自己，点工具栏图标则不会改变选中项。后者应进设置窗口
func launchedByOpeningSelfInFinder() -> Bool {
    let source = """
    tell application "Finder"
        try
            set out to {}
            repeat with a in (get selection as alias list)
                set end of out to POSIX path of a
            end repeat
            return out
        on error
            return {}
        end try
    end tell
    """
    var error: NSDictionary?
    guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
        g2tLog("finderSelection FAILED: \(error?.description ?? "nil result")")
        return false
    }
    let me = Bundle.main.bundleURL.standardizedFileURL.path
    for i in 1...max(result.numberOfItems, 1) {
        let item = result.numberOfItems > 0 ? result.atIndex(i) : result
        guard let path = item?.stringValue else { continue }
        if URL(fileURLWithPath: path).standardizedFileURL.path == me {
            g2tLog("finderSelection contains self")
            return true
        }
    }
    return false
}

func openTerminal() {
    let terminal = UserDefaults.standard.string(forKey: kTerminalKey) ?? "iTerm"
    let path = finderCurrentPath()
    g2tLog("openTerminal: terminal=\(terminal) path=\(path)")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-a", terminal, path]
    do {
        try p.run()
        p.waitUntilExit()
        g2tLog("open exit=\(p.terminationStatus)")
    } catch {
        g2tLog("open spawn FAILED: \(error)")
    }
}

func openVSCode() {
    let path = finderCurrentPath()
    g2tLog("openVSCode: path=\(path)")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-b", "com.microsoft.VSCode", path]
    do {
        try p.run()
        p.waitUntilExit()
        g2tLog("open vscode exit=\(p.terminationStatus)")
    } catch {
        g2tLog("open vscode FAILED: \(error)")
    }
}

// MARK: - 新建文件

func uniqueNewFileURL(in dir: String) -> URL {
    let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
    var url = dirURL.appendingPathComponent("\(L10n.newFileBaseName).txt")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = dirURL.appendingPathComponent("\(L10n.newFileBaseName) \(n).txt")
        n += 1
    }
    return url
}

func createNewFileInFinder() {
    let url = uniqueNewFileURL(in: finderCurrentPath())
    guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
    if AXIsProcessTrusted() {
        beginRename()
    } else {
        maybePromptAccessibility()
    }
    // activateFileViewerSelecting 是异步投递给 Finder 的，退出太快会丢选中
    Thread.sleep(forTimeInterval: 0.3)
}

/// 给 Finder 发一个 Return 键让它进入重命名（需「辅助功能」权限）
func beginRename() {
    // activateFileViewerSelecting 是异步的，等 Finder 真正成为前台再发键
    for _ in 0..<30 where NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.finder" {
        Thread.sleep(forTimeInterval: 0.05)
    }
    Thread.sleep(forTimeInterval: 0.25)  // 等选中落定
    guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    else { return }
    // 直接投递给 Finder 进程，避免按键落到别的前台应用
    let src = CGEventSource(stateID: .combinedSessionState)
    CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)?.postToPid(finder.processIdentifier)
    CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)?.postToPid(finder.processIdentifier)
}

/// 首次新建文件且未授权时，解释一次自动重命名增强；确认后弹系统授权对话框
func maybePromptAccessibility() {
    guard !UserDefaults.standard.bool(forKey: kAXPromptedKey) else { return }
    UserDefaults.standard.set(true, forKey: kAXPromptedKey)

    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = L10n.axAlertTitle
    alert.informativeText = L10n.axAlertInfo
    alert.addButton(withTitle: L10n.axAllow)
    let later = alert.addButton(withTitle: L10n.axLater)
    later.keyEquivalent = "\u{1b}"
    if alert.runModal() == .alertFirstButtonReturn {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - 自动更新

struct Release {
    let tag: String      // 形如 "v1.5.0"
    let version: String  // 去掉 v 前缀，"1.5.0"
    let htmlURL: String
    let dmgURL: String?
    let body: String
}

/// 安装结果：成功带新版本号，失败带错误文案
enum InstallResult {
    case success(String)
    case failure(String)
}

/// 同步跑一个子进程，返回 (退出码, 合并的 stdout+stderr)
@discardableResult
func run(_ launchPath: String, _ args: [String]) -> (code: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

enum Updater {
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private static func components(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// tag/version 是否比当前版本新
    static func isNewer(_ version: String) -> Bool {
        let new = components(version), cur = components(currentVersion)
        let n = max(new.count, cur.count)
        for i in 0..<n {
            let a = i < new.count ? new[i] : 0
            let b = i < cur.count ? cur[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// 查最新 Release（回主线程）。失败/超时 → nil
    static func fetchLatestRelease(completion: @escaping (Release?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(kRepo)/releases/latest") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.setValue("Go2Term", forHTTPHeaderField: "User-Agent")  // GitHub API 强制要求
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var release: Release?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = json["assets"] as? [[String: Any]] ?? []
                let dmg = assets.compactMap { $0["browser_download_url"] as? String }
                    .first { $0.hasSuffix(".dmg") }
                release = Release(
                    tag: tag, version: version,
                    htmlURL: json["html_url"] as? String ?? kReleasePage,
                    dmgURL: dmg,
                    body: json["body"] as? String ?? "")
            }
            DispatchQueue.main.async { completion(release) }
        }.resume()
    }

    /// 下载 dmg → 校验签名/公证 → 原地替换 /Applications/Go2Term.app（回主线程）
    /// 成功返回新版本号，失败返回错误文案
    static func downloadAndInstall(_ release: Release, completion: @escaping (InstallResult) -> Void) {
        guard let dmgStr = release.dmgURL, let dmgURL = URL(string: dmgStr) else {
            completion(.failure(L10n.updateFailedTitle)); return
        }
        func fail(_ msg: String) { DispatchQueue.main.async { completion(.failure(msg)) } }
        func ok(_ v: String) { DispatchQueue.main.async { completion(.success(v)) } }

        var req = URLRequest(url: dmgURL)
        req.setValue("Go2Term", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 60
        URLSession.shared.downloadTask(with: req) { tmpURL, _, err in
            guard let tmpURL, err == nil else { fail(L10n.updateFailedTitle); return }
            // 下载文件搬到带 .dmg 后缀的临时路径，hdiutil 才认
            let dmgPath = NSTemporaryDirectory() + "Go2Term-update-\(release.version).dmg"
            try? FileManager.default.removeItem(atPath: dmgPath)
            do {
                try FileManager.default.moveItem(at: tmpURL, to: URL(fileURLWithPath: dmgPath))
            } catch { fail(L10n.updateFailedTitle); return }
            DispatchQueue.global().async {
                let result = installFromDMG(dmgPath, version: release.version)
                try? FileManager.default.removeItem(atPath: dmgPath)
                switch result {
                case .success(let v): ok(v)
                case .failure(let m): fail(m)
                }
            }
        }.resume()
    }

    /// 挂载 dmg、校验、ditto 替换、卸载。在后台线程同步执行
    private static func installFromDMG(_ dmgPath: String, version: String) -> InstallResult {
        // 挂载（不能加 -quiet：那样无 stdout，挂载点解析不到）
        let attach = run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noverify", dmgPath])
        guard attach.code == 0 else { return .failure(L10n.updateFailedTitle) }
        // 解析挂载点（/Volumes/... 那一行的最后一段以制表符分隔）
        let mount = attach.output.split(separator: "\n").compactMap { line -> String? in
            let cols = line.components(separatedBy: "\t")
            return cols.last.map { $0.trimmingCharacters(in: .whitespaces) }
        }.first { $0.hasPrefix("/Volumes/") }
        guard let mountPoint = mount else { return .failure(L10n.updateFailedTitle) }
        defer { run("/usr/bin/hdiutil", ["detach", "-quiet", mountPoint]) }

        let srcApp = mountPoint + "/Go2Term.app"
        guard FileManager.default.fileExists(atPath: srcApp) else { return .failure(L10n.updateFailedTitle) }

        // 校验：codesign 完整性 + TeamID + Gatekeeper 公证
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", srcApp]).code == 0 else {
            return .failure(L10n.updateFailedTitle)
        }
        let cs = run("/usr/bin/codesign", ["-dv", srcApp])
        guard cs.output.contains("TeamIdentifier=\(kTeamID)") else { return .failure(L10n.updateFailedTitle) }
        guard run("/usr/sbin/spctl", ["-a", "-t", "exec", srcApp]).code == 0 else {
            return .failure(L10n.updateFailedTitle)
        }

        // 原地 ditto 覆盖（不先删 → 保留 bundle inode → 工具栏 alias 不失效）
        let dst = Bundle.main.bundleURL.path
        guard run("/usr/bin/ditto", [srcApp, dst]).code == 0 else { return .failure(L10n.updateFailedTitle) }
        return .success(version)
    }
}

// MARK: - 设置窗口

/// 无边框窗口默认不能成为 key window，弹菜单的锚点窗口需要它
final class MenuAnchorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var installButton: NSButton!
    var statusLabel: NSTextField!
    var updateStatusLabel: NSTextField?

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
            // 只有「Finder 发起 + 双击的不是 app 本体」才是工具栏点击；其余入口进设置
            if !launchedByFinder() || launchedByOpeningSelfInFinder() {
                showWindow()
                return
            }
            if showActionMenuEnabled {
                // 不能内联弹菜单：popUp 的嵌套 runloop 会挂住启动栈，且激活未完成时收不到键盘
                DispatchQueue.main.async { self.showActionMenu() }
            } else {
                openTerminal()
                finishAfterAction()
            }
            return
        }
        showWindow()
    }

    /// 菜单已弹出时再次点工具栏图标 / 在访达双击 app 会发 reopen 给本进程，
    /// 不拦截会再弹一个菜单（用户报告的「两个菜单」）
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        return false
    }

    var showActionMenuEnabled: Bool {
        UserDefaults.standard.object(forKey: kShowMenuKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: kShowMenuKey)
    }

    var menuAnchor: NSWindow?
    var suppressAutoTerminate = false

    func showActionMenu() {
        // 菜单流程自管生命周期（所有分支以显式 terminate 或 showWindow 收尾），
        // 期间挂起自动 terminate——见 applicationShouldTerminateAfterLastWindowClosed 注释
        suppressAutoTerminate = true
        let menu = NSMenu()
        let open = NSMenuItem(title: L10n.menuOpenTerminal,
                              action: #selector(menuOpenTerminal(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        // 仅在装了 VS Code 时显示
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil {
            let vscode = NSMenuItem(title: L10n.menuOpenVSCode,
                                    action: #selector(menuOpenVSCode(_:)), keyEquivalent: "")
            vscode.target = self
            menu.addItem(vscode)
        }
        let newFile = NSMenuItem(title: L10n.menuNewFile,
                                 action: #selector(menuNewFile(_:)), keyEquivalent: "")
        newFile.target = self
        menu.addItem(newFile)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: L10n.menuSettings,
                                  action: #selector(menuShowConfig(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let pt = NSEvent.mouseLocation
        // accessory app 弹菜单后 Finder 会立刻抢回焦点导致菜单被关；
        // 用一个透明 key 窗口压住激活状态，菜单挂在它上面才能存活
        let anchor = MenuAnchorWindow(contentRect: NSRect(x: pt.x, y: pt.y, width: 1, height: 1),
                                      styleMask: .borderless, backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.level = .popUpMenu
        anchor.isReleasedWhenClosed = false
        menuAnchor = anchor

        NSApp.activate(ignoringOtherApps: true)
        anchor.makeKeyAndOrderFront(nil)
        // 鼠标若在菜单弹出瞬间已落在菜单内（边角死区或第一项上），后续点击会被
        // 菜单跟踪静默吞掉。把菜单顶边放到鼠标下方几个点，让鼠标从外部移入
        let menuPt = NSPoint(x: pt.x, y: pt.y - 8)
        // 延迟一拍：等激活落定，并吸收工具栏点击残留的 mouse-up（立刻弹会被它关掉）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // 同步阻塞到菜单关闭；选中项的 action 在返回前已派发完，取消则直接落到 terminate
            _ = menu.popUp(positioning: nil, at: menuPt, in: nil)
            if self.configRequested {
                self.menuAnchor?.orderOut(nil)
                self.showWindow()
                self.suppressAutoTerminate = false  // 设置窗口已可见，恢复关窗即退出
            } else {
                self.finishAfterAction()
            }
        }
    }

    @objc func menuOpenTerminal(_ sender: Any?) {
        menuAnchor?.orderOut(nil)  // 让出焦点，别挡住目标应用
        openTerminal()
    }

    @objc func menuOpenVSCode(_ sender: Any?) {
        menuAnchor?.orderOut(nil)
        openVSCode()
    }

    @objc func menuNewFile(_ sender: Any?) {
        menuAnchor?.orderOut(nil)
        createNewFileInFinder()
    }

    var configRequested = false

    @objc func menuShowConfig(_ sender: Any?) {
        // 不能在这里直接开窗口——popUp 的嵌套 runloop 还没退出；置标记，返回后处理
        configRequested = true
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

        let menuToggle = NSButton(checkboxWithTitle: L10n.showMenuToggle,
                                  target: self, action: #selector(menuToggleChanged(_:)))
        menuToggle.state = showActionMenuEnabled ? .on : .off

        let autoCheckToggle = NSButton(checkboxWithTitle: L10n.autoCheckToggle,
                                       target: self, action: #selector(autoCheckToggleChanged(_:)))
        autoCheckToggle.state = autoCheckEnabled ? .on : .off

        let checkButton = NSButton(title: L10n.checkUpdatesButton,
                                   target: self, action: #selector(checkUpdatesClicked(_:)))
        checkButton.bezelStyle = .rounded

        let updateLabel = NSTextField(labelWithString: "")
        updateLabel.font = .systemFont(ofSize: 11)
        updateLabel.textColor = .secondaryLabelColor
        updateLabel.alignment = .center
        updateStatusLabel = updateLabel

        installButton = NSButton(title: "", target: self, action: #selector(toggleInstall(_:)))
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = "\r"
        installButton.controlSize = .large

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .center

        refreshInstallState()

        let stack = NSStackView(views: [iconView, title, subtitle, terminalRow,
                                        menuToggle, autoCheckToggle,
                                        installButton, checkButton, updateLabel, statusLabel])
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

        // 打开设置窗口时，若到期则静默查一次更新（有新版才弹提示）
        checkForUpdates(manual: false)
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

    @objc func menuToggleChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: kShowMenuKey)
    }

    @objc func autoCheckToggleChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: kAutoCheckKey)
    }

    @objc func checkUpdatesClicked(_ sender: NSButton) {
        checkForUpdates(manual: true)
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

    // MARK: 更新流程

    var autoCheckEnabled: Bool {
        UserDefaults.standard.object(forKey: kAutoCheckKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: kAutoCheckKey)
    }

    /// 自动检查是否到期（开关开 且 距上次 > 24h）
    func shouldAutoCheckNow() -> Bool {
        guard autoCheckEnabled else { return false }
        if let last = UserDefaults.standard.object(forKey: kLastCheckKey) as? Date,
           Date().timeIntervalSince(last) < kUpdateCheckInterval {
            return false
        }
        return true
    }

    /// 动作（开终端/新建文件等）完成后的收尾：到期则后台查更新，
    /// 有新版弹提示（保活），否则退出进程
    func finishAfterAction() {
        menuAnchor?.orderOut(nil)
        guard shouldAutoCheckNow() else { NSApp.terminate(nil); return }
        UserDefaults.standard.set(Date(), forKey: kLastCheckKey)
        suppressAutoTerminate = true
        g2tLog("auto update check…")
        Updater.fetchLatestRelease { release in
            if let release, Updater.isNewer(release.version) {
                g2tLog("update available: \(release.version)")
                self.presentUpdatePrompt(release, terminateWhenDone: true)
            } else {
                g2tLog("no update (latest=\(release?.version ?? "?"))")
                NSApp.terminate(nil)
            }
        }
    }

    /// 设置窗口里检查更新。manual=true 时忽略节流，并在已是最新时也给出反馈
    func checkForUpdates(manual: Bool) {
        if !manual && !shouldAutoCheckNow() { return }
        UserDefaults.standard.set(Date(), forKey: kLastCheckKey)
        if manual { updateStatusLabel?.stringValue = L10n.checking }
        g2tLog("checkForUpdates(manual:\(manual)) current=\(Updater.currentVersion)")
        Updater.fetchLatestRelease { release in
            guard let release else {
                g2tLog("checkForUpdates: fetch failed")
                if manual { self.updateStatusLabel?.stringValue = L10n.checkFailed }
                return
            }
            g2tLog("checkForUpdates: latest=\(release.version) newer=\(Updater.isNewer(release.version))")
            if Updater.isNewer(release.version) {
                self.updateStatusLabel?.stringValue = ""
                self.presentUpdatePrompt(release, terminateWhenDone: false)
            } else if manual {
                self.updateStatusLabel?.stringValue = L10n.upToDate(Updater.currentVersion)
            }
        }
    }

    /// 共用更新提示框。terminateWhenDone=true 用于无设置窗口的瞬时启动路径
    func presentUpdatePrompt(_ release: Release, terminateWhenDone: Bool) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.updateFound(release.version)
        alert.informativeText = Self.notesPreview(release.body)
        alert.addButton(withTitle: L10n.updateInstall)
        alert.addButton(withTitle: L10n.updateNotes)
        alert.addButton(withTitle: L10n.updateLater)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            performUpdate(release, terminateWhenDone: terminateWhenDone)
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
            presentUpdatePrompt(release, terminateWhenDone: terminateWhenDone)  // 看完再回提示
        default:
            if terminateWhenDone { NSApp.terminate(nil) }
        }
    }

    func performUpdate(_ release: Release, terminateWhenDone: Bool) {
        showProgress(L10n.updating)
        Updater.downloadAndInstall(release) { result in
            self.closeProgress()
            switch result {
            case .success(let v):
                let a = NSAlert()
                a.messageText = L10n.updateDoneTitle
                a.informativeText = L10n.updateDone(v)
                a.addButton(withTitle: L10n.ok)
                a.runModal()
                if terminateWhenDone { NSApp.terminate(nil) }
                else { self.updateStatusLabel?.stringValue = L10n.upToDate(v) }
            case .failure(let msg):
                let a = NSAlert()
                a.messageText = L10n.updateFailedTitle
                a.informativeText = msg
                a.addButton(withTitle: L10n.openDownloadPage)
                a.addButton(withTitle: L10n.updateLater)
                if a.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: release.htmlURL) { NSWorkspace.shared.open(url) }
                if terminateWhenDone { NSApp.terminate(nil) }
                else { self.updateStatusLabel?.stringValue = "" }
            }
        }
    }

    /// 取 release notes 前几行做提示框正文
    static func notesPreview(_ body: String) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).prefix(8)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 下载安装期间的转圈进度窗口
    var progressWindow: NSWindow?

    func showProgress(_ text: String) {
        NSApp.setActivationPolicy(.regular)
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 22).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let stack = NSStackView(views: [spinner, NSTextField(labelWithString: text)])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        let w = NSWindow(contentRect: .zero, styleMask: [.titled],
                         backing: .buffered, defer: false)
        w.title = "Go2Term"
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        w.center()
        w.isReleasedWhenClosed = false
        progressWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeProgress() {
        progressWindow?.orderOut(nil)
        progressWindow = nil
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

    /// 菜单流程期间必须挂起「最后窗口关闭即退出」：选中菜单项后弹窗+anchor 都已关闭，
    /// AppKit 会调度自动 terminate，并在 NSAppleScript 等 AE 回复的嵌套 runloop 里执行,
    /// 把进程杀死在 action 半路（终端没开、文件没建）。菜单路径自己负责 terminate。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !suppressAutoTerminate
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

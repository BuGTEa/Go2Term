<p align="center">
  <img src="docs/icon.png" width="128" alt="Go2Term icon">
</p>

<h1 align="center">Go2Term</h1>

<p align="center">
  Open the current Finder folder in your terminal, from a Finder toolbar button.<br>
  A native Apple Silicon replacement for Go2Shell on macOS 26+, where Intel-only apps no longer run.
</p>

---

[English](#english) | [中文](#中文)

## English

### Features

- **One click** on the Finder toolbar icon pops up a menu: **Open Terminal Here** / **Open in VS Code Here** / **New File Here** / **Settings…** (or turn the menu off in settings for direct open-terminal)
- **New File Here** creates an empty `untitled.txt` in the current folder and selects it in Finder. On first use it offers to enable auto-rename (one-time **Accessibility** permission); decline and it simply leaves the file selected
- **Auto-update** — checks GitHub Releases on launch (throttled to once a day) and offers to download, verify (Developer ID + notarization) and install the new version in place; also a manual **Check for Updates** button in settings
- **One-click install** — no manual toolbar dragging; Go2Term writes itself into the Finder toolbar (this is reverse-engineered from Finder's native toolbar storage format, see [How it works](#how-it-works))
- Supports **iTerm2, Terminal, Warp, Ghostty, kitty, Alacritty** (auto-detected); **VS Code** menu entry shown when installed
- Native **arm64**, ~100 KB, no background process — launches, opens your terminal, quits
- English / 简体中文 (follows system language)

### Install

1. Download the `.dmg` from [Releases](../../releases), drag **Go2Term** to **Applications** (signed & notarized — opens without warnings)
2. Open Go2Term and click **Install to Finder Toolbar**. Finder relaunches with the icon in place
3. First click on the icon: approve the *"Go2Term wants to control Finder"* prompt (one time only — it's how Go2Term reads the current folder)

### Usage

| Action | How |
|---|---|
| Open terminal / VS Code / new file at current folder | Click the toolbar icon, pick from the menu |
| Settings window (terminal, menu & auto-update toggles, install/remove) | Double-click Go2Term in **Applications**, pick **Settings…** from the menu, hold **⌥** and open Go2Term, or `open -a Go2Term --args config` |
| Check for updates | Settings → **Check for Updates** (auto-checks on launch, once a day) |
| Change terminal from CLI | `defaults write com.panbo.Go2Term TerminalApp Terminal` |
| Disable the click menu from CLI | `defaults write com.panbo.Go2Term ShowActionMenu -bool false` |
| Disable auto-update check from CLI | `defaults write com.panbo.Go2Term AutoCheckUpdates -bool false` |
| Install / uninstall from CLI | `open -a Go2Term --args install` / `--args uninstall` |

### How it works

- The current folder is read from Finder via Apple Events (`insertion location`), then opened with `open -a <terminal> <path>`.
- One-click install writes Finder's toolbar preferences directly (`com.apple.finder` → `NSToolbar Configuration Browser`). Third-party toolbar items are identified as `com.apple.finder.loc` (plus trailing spaces for uniqueness) in `TB Item Identifiers`, with their location stored in `TB Item Plists` — keyed by the item's **array index**, as `{_CFURLAliasData, _CFURLString, _CFURLStringType}`. The alias data **must be a legacy Carbon AliasRecord** with a file-reference URL string — Finder on macOS 26 silently discards entries written as modern bookmark data at relaunch (macOS 27 accepts both). Since the Alias Manager is hidden from Swift, Go2Term calls `FSNewAlias` via `dlsym`. Finder is then relaunched.

### Build from source

```sh
./build.sh        # requires Xcode command line tools
ditto build.noindex/Go2Term.app /Applications/Go2Term.app
```

Signing identity is set at the top of `build.sh` — replace it with your own (or use `--sign -` for ad-hoc).

---

## 中文

### 特性

- 点一下 Finder 工具栏图标，弹出菜单：**在此处打开终端** / **在此处打开 VS Code** / **在此处新建文件** / **设置…**（设置里可关掉菜单，恢复单击直接开终端）
- **新建文件**在当前目录创建空白「未命名.txt」并在 Finder 中选中；首次使用时会询问是否启用自动重命名（一次性授予「辅助功能」权限），不授权则保持仅选中
- **自动更新**——启动时（每天最多一次）查 GitHub Release，有新版可一键下载、校验（Developer ID 签名 + 公证）并原地安装；设置里也有手动「检查更新」
- **真·一键安装**——不用手动拖工具栏，Go2Term 直接把自己写进 Finder 工具栏配置（逆向了 Finder 原生存储格式，见上方 How it works）
- 支持 **iTerm2、Terminal、Warp、Ghostty、kitty、Alacritty**（自动检测）；装了 **VS Code** 时菜单显示对应项
- 原生 **arm64**，约 100 KB，无常驻进程——启动、开终端、退出
- 中英文界面（跟随系统语言）

### 安装

1. 从 [Releases](../../releases) 下载 `.dmg`，把 **Go2Term** 拖到 **应用程序**（已签名并公证，打开无任何警告）
2. 打开 Go2Term，点 **「一键安装到 Finder 工具栏」**，Finder 重启后图标就位
3. 第一次点图标时，允许 *「Go2Term 想要控制 Finder」* 的授权（仅一次，用于读取当前目录）

### 使用

| 操作 | 方法 |
|---|---|
| 打开终端 / VS Code / 新建文件 | 点工具栏图标，从菜单中选 |
| 设置窗口（终端、菜单与自动更新开关、安装/移除） | 在「应用程序」里双击 Go2Term，菜单里选「设置…」，按住 **⌥** 打开 Go2Term，或 `open -a Go2Term --args config` |
| 检查更新 | 设置 →「检查更新」（启动时每天自动查一次） |
| 命令行换终端 | `defaults write com.panbo.Go2Term TerminalApp Terminal` |
| 命令行关闭点击菜单 | `defaults write com.panbo.Go2Term ShowActionMenu -bool false` |
| 命令行关闭自动更新检查 | `defaults write com.panbo.Go2Term AutoCheckUpdates -bool false` |
| 命令行安装/卸载 | `open -a Go2Term --args install` / `--args uninstall` |

## License

[MIT](LICENSE)

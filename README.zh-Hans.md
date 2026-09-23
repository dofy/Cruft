# Cruft

[English](README.md) · **简体中文** · [繁體中文](README.zh-Hant.md)

一个小小的原生 **macOS 应用**，清掉开发机上堆出来的那些 *cruft*——Xcode DerivedData、
各工具链缓存（npm/pnpm/yarn、Cargo、Go、Gradle、Maven、pip、SwiftPM）、系统缓存、日志、
Homebrew/CocoaPods/gem 残留，以及废纸篓——外加两个扫描器：长期未动的项目构建产物，和
遗留的安装包。清单式界面、逐项体积估算、以及一份释放空间的报告。

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/Swift-5-orange)
![ui](https://img.shields.io/badge/UI-SwiftUI-green)

## 它做什么

原生侧边栏里六个页面：**清理**、**项目产物**、**安装包**、**应用清理**、**背景 App**、
**恢复历史**。

### 清理页

要跑什么完全由你挑，每个任务都是一个开关。命令行工具缺失（`brew`、`mas`、`pod`、`gem`、
`pnpm`、`go`）的任务会变灰；工具链缓存那几行只在对应缓存目录真的存在时才出现。

#### 更新 —— *默认关*

| 任务 | 执行 |
|------|------|
| Homebrew | `brew update` + `upgrade` + `upgrade --cask --greedy` |
| App Store 应用 | `mas upgrade` |

#### 开发缓存 —— *默认开（Maven 除外）*

| 任务 | 目标 |
|------|------|
| npm | `~/.npm/_cacache` |
| pnpm | `pnpm store prune` |
| yarn | `~/Library/Caches/Yarn` |
| Cargo | `~/.cargo/registry/{cache,src}` |
| Go | `go clean -cache -modcache`（modcache 只读，须经 `go` 删除） |
| Gradle | `~/.gradle/caches` |
| Maven | `~/.m2/repository` —— *默认关*（全量重新下载成本高） |
| pip | `~/Library/Caches/pip` |
| SwiftPM | `~/Library/Caches/org.swift.swiftpm` |

#### 清理 —— *默认开*

| 任务 | 目标 |
|------|------|
| CocoaPods 缓存 | `pod cache clean --all` |
| Xcode | DerivedData、Archives、Products、无效模拟器、旧的 iOS DeviceSupport（保留最新） |
| 系统缓存 | `~/Library/Caches` |
| 应用日志 | `~/Library/Logs` |
| 废纸篓 | `~/.Trash` |
| Homebrew | `brew cleanup` |
| Ruby gem | `gem cleanup` |

联网 / 更新型任务默认不勾选；本地清理型任务默认勾选。

### 项目产物页

扫描 `~/Works`、`~/Projects`、`~/Developer` 里的构建 / 依赖目录（`node_modules`、`.next`、
`dist`、`build`、`target`、`.build`、`venv`、`.venv`、`vendor`、`Pods`、`DerivedData`），
逐个列出体积与最后修改时间。最近 7 天动过的项目默认**不勾选**，免得把正在做的树误删。
勾选项进**废纸篓**（可恢复），不是硬删。

### 安装包页

扫描 `~/Downloads` 和 `~/Desktop` 里遗留的 `.dmg` / `.pkg`。全部默认不勾选——逐个由你确认。
勾选项进**废纸篓**。

### 应用清理页

扫描 `/Applications` 和 `~/Applications`，再把选中的应用与已知的用户级 Library 位置比对。
Bundle ID 精确匹配的默认勾选；仅名称匹配的作为低置信度候选列出、默认不勾选。应用本体与
确认过的关联文件一起进废纸篓。

Cruft 不安装特权 helper。管理员归属、受保护的应用会被报为失败，而不是触发提权删除。

### 恢复历史

文件型清理、项目产物、安装包与应用清理会把原路径和废纸篓路径存进
`~/Library/Application Support/Cruft/deletion-history.json`。只要文件还在废纸篓里，
整批就能恢复。原位置已有的文件永不覆盖。

命令型任务（`brew`、各包管理器命令、`simctl`、Docker prune）和清空废纸篓仍然不可恢复。

## 界面

- **体积估算** —— 每个可清理目录显示当前占用，后台计算，跑完重新估算。
- **逐项详情** —— 每行的 ⓘ 按钮弹出该任务具体触碰的路径 / 命令。
- **可折叠日志** —— 控制台面板（默认折叠、运行时自动展开）实时输出任务日志。
- **释放空间报告** —— 页脚显示这次回收了多少。
- **确认闸门** —— 每次清理都要确认，并说明哪些操作可恢复。
- **操作历史** —— 每次清理追加到 `~/Library/Logs/Cruft/operations.log`（时间戳、释放字节、任务）。
- **原生维护控制台界面** —— 可调宽侧边栏、存储仪表、分组表面、系统材质、SF Symbols，支持浅色 / 深色。
- **统一权限闸门** —— 启动时检查完全磁盘访问，且不枚举清理目录。未授权前扫描与清理都停在一个应用内提示后面。

## 界面多语言

界面提供 English、简体中文、繁體中文，跟随系统语言。App 内没有语言选择器——请在
「系统设置 → 通用 → 语言与地区」里针对单个 App 设置。

- 源语言是 `en`，Swift 代码里的每个 `defaultValue` 都是英文。
- 文案放在 `Sources/Localizable.xcstrings`；完全磁盘访问与各目录的权限说明放在
  `Sources/InfoPlist.xcstrings`（英文基准来自 `project.yml` 里的 `INFOPLIST_KEY_*`）。
- `./Scripts/check-localization.sh`（也是 CI 的一步）会在缺 key、缺译文、有孤儿条目，或
  Swift 里硬编码中文时失败。
- 同时当 `Identifiable.id` 用的枚举 rawValue（`CleanupCategory`、`AppMatchConfidence`）
  是稳定的 ASCII 标识，不是界面文案。
- `deletion-history.json` 除文案外还存 **key**（`titleKey`、`taskKeys`），所以一种语言下
  写的恢复点，换语言后照样能按当前语言渲染。这个改动之前写的记录没有 key，回落到当时
  存下来的文案。
- `~/Library/Logs/Cruft/operations.log` 是诊断日志，格式固定为英文，不随界面语言变。

## 安全性

- 清理页的文件型删除经 Swift `FileManager` 移到废纸篓；单个受保护文件被跳过，不中断整次运行。
- 扫描页的删除（项目产物、安装包）经 `trashItem` 移到**废纸篓**，清空废纸篓前都可恢复。
- 清理目标限于用户自有位置（`~/Library/...`、`~/.Trash`、用户目录下的缓存）。应用清理页还可以
  移动你显式选中的 `/Applications` 里的应用本体；它绝不扫描或删除 `/Library`、`/System`
  这类大范围系统目录。
- Cruft 申请**完全磁盘访问**，因为 macOS 对应用数据、日志、下载、桌面和废纸篓分别保护。
  这个权限由 macOS 管理；权限检查通过前，Cruft 不会扫描这些位置。
- 应用**不沙盒** —— 它需要调用 `brew`/`mas`/`pod`/`gem`/`go`/`pnpm`/`xcrun`，并删除你用户目录里的缓存文件。

## 构建与运行

需要 Xcode 16+ 和 [xcodegen](https://github.com/yonaskolb/XcodeGen)
（`brew install xcodegen`）。改过 `project.yml` 之后重新生成入库的 `.xcodeproj`。

```bash
xcodegen generate                # 重新生成 Cruft.xcodeproj
open Cruft.xcodeproj             # 然后在 Xcode 里 Run（⌘R）
```

或者从命令行：

```bash
xcodebuild -project Cruft.xcodeproj -scheme Cruft -configuration Release build
```

测试与本地化门禁：

```bash
xcodebuild test -project Cruft.xcodeproj -scheme Cruft \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./Scripts/check-localization.sh
```

把构建装进 `/Applications`：

```bash
./Scripts/install-local.sh
```

请用这个脚本，不要自己拷贝构建产物。`project.yml` 走 ad-hoc 签名，而 TCC 只能把 ad-hoc
签名钉在二进制的 cdhash 上，所以应用一重新构建，完全磁盘访问授权就会静默失效——开关看着
还开着，应用却报告没有文件访问权限。脚本用自签的 `Cruft Local Development` 证书签名
（首次运行时在登录钥匙串里创建），TCC 钉的是这个证书，授权就能跨重新构建存活。

## 项目结构

```
Sources/
├── CruftApp.swift          # @main App 入口与窗口尺寸
├── ContentView.swift       # 应用外壳、侧边栏、功能导航
├── FeatureViews.swift      # 清理 / 扫描 / 应用 / 背景 / 历史各页面
├── RowViews.swift          # 可复用的任务、扫描、应用、BTM、历史行
├── DesignSystem.swift      # 配色、表面、存储仪表、控件
├── FolderAccess.swift      # 完全磁盘访问探测、提示与设置跳转
├── AppCleaner.swift        # 已安装应用与保守的关联文件扫描
├── DeletionHistory.swift   # 持久化的可恢复批次与恢复逻辑
├── CleanerViewModel.swift  # @MainActor 状态 + 运行循环 + 历史
├── CleanerEngine.swift     # 把每个任务映射到 shell / 文件操作
├── Scanner.swift           # 项目产物 + 安装包扫描器，ScanViewModel
├── Shell.swift             # Process 运行器 + FileManager 清理 + moveToTrash
├── Models.swift            # CleanupKind / CleanupItem
├── Localizable.xcstrings   # 界面文案，en（源）+ zh-Hans + zh-Hant
├── InfoPlist.xcstrings     # 各项权限说明的本地化
└── Assets.xcassets/        # 应用图标
Tests/CruftTests.swift      # 匹配、路径守卫与恢复测试
Scripts/check-localization.sh  # 字符串目录门禁（CI 也跑）
project.yml                 # xcodegen 规格
```

## License

MIT，见 [LICENSE](./LICENSE)。

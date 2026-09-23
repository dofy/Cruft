# Cruft

[English](README.md) · [简体中文](README.zh-Hans.md) · **繁體中文**

一個小小的原生 **macOS App**，清掉開發機上堆出來的那些 *cruft* —— Xcode DerivedData、
各工具鏈快取（npm/pnpm/yarn、Cargo、Go、Gradle、Maven、pip、SwiftPM）、系統快取、記錄、
Homebrew/CocoaPods/gem 殘留，以及垃圾桶 —— 再加兩個掃描器：長期沒動的專案建置產物，以及
留下來的安裝檔。清單式介面、逐項體積估算，還有一份釋出空間的報告。

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/Swift-5-orange)
![ui](https://img.shields.io/badge/UI-SwiftUI-green)

## 它做什麼

原生側邊欄裡六個頁面：**清理**、**專案產物**、**安裝檔**、**App 清理**、**背景 App**、
**還原記錄**。

### 清理頁

要跑什麼完全由你挑，每個任務都是一個開關。指令列工具缺失（`brew`、`mas`、`pod`、`gem`、
`pnpm`、`go`）的任務會變灰；工具鏈快取那幾行只在對應快取目錄真的存在時才出現。

#### 更新 —— *預設關*

| 任務 | 執行 |
|------|------|
| Homebrew | `brew update` + `upgrade` + `upgrade --cask --greedy` |
| App Store 的 App | `mas upgrade` |

#### 開發快取 —— *預設開（Maven 除外）*

| 任務 | 目標 |
|------|------|
| npm | `~/.npm/_cacache` |
| pnpm | `pnpm store prune` |
| yarn | `~/Library/Caches/Yarn` |
| Cargo | `~/.cargo/registry/{cache,src}` |
| Go | `go clean -cache -modcache`（modcache 是唯讀的，必須經由 `go` 刪除） |
| Gradle | `~/.gradle/caches` |
| Maven | `~/.m2/repository` —— *預設關*（全量重新下載成本高） |
| pip | `~/Library/Caches/pip` |
| SwiftPM | `~/Library/Caches/org.swift.swiftpm` |

#### 清理 —— *預設開*

| 任務 | 目標 |
|------|------|
| CocoaPods 快取 | `pod cache clean --all` |
| Xcode | DerivedData、Archives、Products、無效的模擬器、舊的 iOS DeviceSupport（保留最新） |
| 系統快取 | `~/Library/Caches` |
| App 記錄 | `~/Library/Logs` |
| 垃圾桶 | `~/.Trash` |
| Homebrew | `brew cleanup` |
| Ruby gem | `gem cleanup` |

連網／更新型任務預設不勾選；本機清理型任務預設勾選。

### 專案產物頁

掃描 `~/Works`、`~/Projects`、`~/Developer` 裡的建置／依賴目錄（`node_modules`、`.next`、
`dist`、`build`、`target`、`.build`、`venv`、`.venv`、`vendor`、`Pods`、`DerivedData`），
逐個列出體積與最後修改時間。最近 7 天動過的專案預設**不勾選**，免得把正在做的樹誤刪。
勾選的項目進**垃圾桶**（可還原），不是硬刪。

### 安裝檔頁

掃描 `~/Downloads` 和 `~/Desktop` 裡留下的 `.dmg` / `.pkg`。全部預設不勾選 —— 逐個由你確認。
勾選的項目進**垃圾桶**。

### App 清理頁

掃描 `/Applications` 和 `~/Applications`，再把選中的 App 與已知的使用者層級 Library 位置
比對。Bundle ID 精確相符的預設勾選；只有名稱相符的列為低信心候選、預設不勾選。App 本體
與確認過的關聯檔案會一起進垃圾桶。

Cruft 不安裝特權 helper。管理者擁有、受保護的 App 會被回報為失敗，而不是觸發提權刪除。

### 還原記錄

檔案型清理、專案產物、安裝檔與 App 清理會把原路徑和垃圾桶路徑存進
`~/Library/Application Support/Cruft/deletion-history.json`。只要檔案還在垃圾桶裡，
整批就能還原。原位置已有的檔案永不覆蓋。

指令型任務（`brew`、各套件管理器指令、`simctl`、Docker prune）和清空垃圾桶仍然無法還原。

## 介面

- **體積估算** —— 每個可清理目錄顯示目前佔用，在背景計算，跑完重新估算。
- **逐項細節** —— 每一行的 ⓘ 按鈕會彈出該任務具體會碰到的路徑／指令。
- **可折疊記錄** —— 主控台面板（預設折疊、執行時自動展開）即時輸出任務記錄。
- **釋出空間報告** —— 頁尾顯示這次回收了多少。
- **確認閘門** —— 每次清理都要確認，並說明哪些操作可以還原。
- **操作記錄** —— 每次清理都追加到 `~/Library/Logs/Cruft/operations.log`（時間戳、釋出位元組、任務）。
- **原生維護主控台介面** —— 可調寬側邊欄、儲存空間量表、分組表面、系統材質、SF Symbols，支援淺色／深色。
- **統一權限閘門** —— 啟動時檢查完全取用磁碟，而且不會枚舉任何目錄。授權之前，掃描與清理都停在一個 App 內提示後面。

## 介面多語言

介面提供 English、简体中文、繁體中文，跟隨系統語言。App 內沒有語言選擇器 —— 請在
「系統設定 → 一般 → 語言與地區」裡針對單一 App 設定。

- 源語言是 `en`，Swift 程式碼裡的每個 `defaultValue` 都是英文。
- 文案放在 `Sources/Localizable.xcstrings`；完全取用磁碟與各資料夾的權限說明放在
  `Sources/InfoPlist.xcstrings`（英文基準來自 `project.yml` 裡的 `INFOPLIST_KEY_*`）。
- `./Scripts/check-localization.sh`（也是 CI 的一步）會在缺 key、缺譯文、有孤兒條目，或
  Swift 裡硬編碼中文時失敗。
- 同時當 `Identifiable.id` 用的列舉 rawValue（`CleanupCategory`、`AppMatchConfidence`）
  是穩定的 ASCII 識別碼，不是介面文案。
- `deletion-history.json` 除了文案還存 **key**（`titleKey`、`taskKeys`），所以在一種語言下
  寫的還原點，換語言之後照樣能用當前語言呈現。這個改動之前寫的記錄沒有 key，會回落到當時
  存下來的文案。
- `~/Library/Logs/Cruft/operations.log` 是診斷記錄，格式固定為英文，不隨介面語言變。

## 安全性

- 清理頁的檔案型刪除經 Swift `FileManager` 移到垃圾桶；單一受保護的檔案會被略過，不會中斷整次執行。
- 掃描頁的刪除（專案產物、安裝檔）經 `trashItem` 移到**垃圾桶**，清空垃圾桶之前都能還原。
- 清理目標限於使用者自己的位置（`~/Library/...`、`~/.Trash`、個人資料夾下的快取）。App 清理頁
  另外可以移動你明確選中的 `/Applications` 裡的 App 本體；它絕不掃描或刪除 `/Library`、
  `/System` 這類大範圍系統目錄。
- Cruft 申請**完全取用磁碟**，因為 macOS 對 App 資料、記錄、下載、桌面和垃圾桶分別保護。
  這個權限由 macOS 管理；權限檢查通過之前，Cruft 不會掃描這些位置。
- App **不在沙盒中** —— 它需要呼叫 `brew`/`mas`/`pod`/`gem`/`go`/`pnpm`/`xcrun`，並刪除你個人資料夾裡的快取檔案。

## 建置與執行

需要 Xcode 16+ 和 [xcodegen](https://github.com/yonaskolb/XcodeGen)
（`brew install xcodegen`）。改過 `project.yml` 之後要重新產生入庫的 `.xcodeproj`。

```bash
xcodegen generate                # 重新產生 Cruft.xcodeproj
open Cruft.xcodeproj             # 然後在 Xcode 裡 Run（⌘R）
```

或者從指令列：

```bash
xcodebuild -project Cruft.xcodeproj -scheme Cruft -configuration Release build
```

測試與本機化門禁：

```bash
xcodebuild test -project Cruft.xcodeproj -scheme Cruft \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
./Scripts/check-localization.sh
```

把建置結果安裝到 `/Applications`：

```bash
./Scripts/install-local.sh
```

請用這個腳本，不要自己複製建置產物。`project.yml` 走 ad-hoc 簽章，而 TCC 只能把 ad-hoc
簽章釘在二進位檔的 cdhash 上，所以 App 一重新建置，完全取用磁碟的授權就會靜默失效 ——
開關看起來還開著，App 卻回報沒有檔案取用權限。腳本用自簽的 `Cruft Local Development`
憑證簽章（首次執行時在登入鑰匙串裡建立），TCC 釘的是這張憑證，授權就能跨重新建置存活。

## 專案結構

```
Sources/
├── CruftApp.swift          # @main App 入口與視窗尺寸
├── ContentView.swift       # App 外殼、側邊欄、功能導覽
├── FeatureViews.swift      # 清理／掃描／App／背景／記錄各頁面
├── RowViews.swift          # 可重用的任務、掃描、App、BTM、記錄列
├── DesignSystem.swift      # 配色、表面、儲存空間量表、控制項
├── FolderAccess.swift      # 完全取用磁碟偵測、提示與設定跳轉
├── AppCleaner.swift        # 已安裝 App 與保守的關聯檔案掃描
├── DeletionHistory.swift   # 持久化的可還原批次與還原邏輯
├── CleanerViewModel.swift  # @MainActor 狀態 + 執行迴圈 + 記錄
├── CleanerEngine.swift     # 把每個任務對映到 shell／檔案操作
├── Scanner.swift           # 專案產物 + 安裝檔掃描器，ScanViewModel
├── Shell.swift             # Process 執行器 + FileManager 清理 + moveToTrash
├── Models.swift            # CleanupKind / CleanupItem
├── Localizable.xcstrings   # 介面文案，en（源）+ zh-Hans + zh-Hant
├── InfoPlist.xcstrings     # 各項權限說明的本機化
└── Assets.xcassets/        # App 圖像
Tests/CruftTests.swift      # 比對、路徑守衛與還原測試
Scripts/check-localization.sh  # 字串目錄門禁（CI 也會跑）
project.yml                 # xcodegen 規格
```

## License

MIT，見 [LICENSE](./LICENSE)。

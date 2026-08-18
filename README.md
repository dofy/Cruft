# Cruft

A small native **macOS app** that clears the *cruft* a developer machine piles
up — Xcode DerivedData, toolchain caches (npm/pnpm/yarn, Cargo, Go, Gradle,
Maven, pip, SwiftPM), system caches, logs, Homebrew/CocoaPods/gem leftovers, and
the Trash — plus scanners for stale project build artifacts and leftover
installers. Checklist UI, per-task size estimates, and a report of the space
reclaimed.

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/Swift-5-orange)
![ui](https://img.shields.io/badge/UI-SwiftUI-green)

## What it does

Three panes, switched from a segmented control: **清理 (Clean)**, **项目产物
(Project artifacts)**, **安装包 (Installers)**.

### Clean pane

Pick exactly what to run. Every task is a toggle. Tasks whose CLI tool is missing
(`brew`, `mas`, `pod`, `gem`, `pnpm`, `go`) grey out; toolchain-cache rows only
appear when that toolchain's cache directory actually exists.

#### Update — *off by default*

| Task | Runs |
|------|------|
| Homebrew | `brew update` + `upgrade` + `upgrade --cask --greedy` |
| App Store apps | `mas upgrade` |

#### Developer caches — *on by default (except Maven)*

| Task | Target |
|------|--------|
| npm | `~/.npm/_cacache` |
| pnpm | `pnpm store prune` |
| yarn | `~/Library/Caches/Yarn` |
| Cargo | `~/.cargo/registry/{cache,src}` |
| Go | `go clean -cache -modcache` (modcache is read-only, so cleaned via `go`) |
| Gradle | `~/.gradle/caches` |
| Maven | `~/.m2/repository` — *off by default* (full re-download is costly) |
| pip | `~/Library/Caches/pip` |
| SwiftPM | `~/Library/Caches/org.swift.swiftpm` |

#### Clean — *on by default*

| Task | Target |
|------|--------|
| CocoaPods cache | `pod cache clean --all` |
| Xcode | DerivedData, Archives, Products, unavailable simulators, old iOS DeviceSupport (keeps latest) |
| System caches | `~/Library/Caches` |
| Application logs | `~/Library/Logs` |
| Trash | `~/.Trash` |
| Homebrew | `brew cleanup` |
| Ruby gems | `gem cleanup` |

Network/update tasks start unchecked; local cleanup tasks start checked.

### Project artifacts pane

Scans `~/Works`, `~/Projects`, `~/Developer` for build/dependency directories
(`node_modules`, `.next`, `dist`, `build`, `target`, `.build`, `venv`, `.venv`,
`vendor`, `Pods`, `DerivedData`), listing each with size and last-modified age.
Projects touched within the last 7 days start **unselected** to avoid nuking an
active tree. Selected items go to the **Trash** (recoverable), not a hard delete.

### Installers pane

Scans `~/Downloads` and `~/Desktop` for leftover `.dmg` / `.pkg` files. All start
unselected — you confirm each. Selected items go to the **Trash**.

## Interface

- **Size estimates** — each cleanable directory shows its current disk usage,
  computed in the background and re-estimated after a run.
- **Per-task details** — an ⓘ button on every row opens a popover listing the
  exact paths / commands that task touches.
- **Collapsible log** — a console pane (collapsed by default, auto-expands during
  a run) streams task output live.
- **Freed-space report** — the footer shows how much was reclaimed.
- **Confirmation gate** — deletions are irreversible, so a run must be confirmed.
- **Operation history** — each Clean run is appended to
  `~/Library/Logs/Cruft/operations.log` (timestamp, freed bytes, tasks).
- **Fixed width** — the window width is locked (no zoom / full screen); only the
  height is resizable.

## Safety

- Clean-pane deletions run through Swift's `FileManager`, not `rm -rf`, so a
  single protected file is skipped instead of aborting the whole run.
- Scanner-pane deletions (project artifacts, installers) move to the **Trash**
  via `trashItem`, so they are recoverable until the Trash is emptied.
- Only user-level paths are touched (`~/Library/...`, `~/.Trash`, home-directory
  caches). System-level `/Library/Logs` and the like are left alone.
- The app is **not sandboxed** — it needs to invoke `brew`/`mas`/`pod`/`gem`/
  `go`/`pnpm`/`xcrun` and delete cache files in your home directory.

## Build & Run

Requires Xcode 16+ and [xcodegen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated, not committed.

```bash
xcodegen generate                # regenerate Cruft.xcodeproj
open Cruft.xcodeproj             # then Run (⌘R) in Xcode
```

Or from the command line:

```bash
xcodebuild -project Cruft.xcodeproj -scheme Cruft -configuration Release build
```

## Project layout

```
Sources/
├── CruftApp.swift          # @main App entry + window sizing
├── ContentView.swift       # SwiftUI UI (3-pane switcher, checklist, scanners, log, footer)
├── CleanerViewModel.swift  # @MainActor state + run loop + history
├── CleanerEngine.swift     # maps each task to shell / file actions
├── Scanner.swift           # project-artifact + installer scanners, ScanViewModel
├── Shell.swift             # Process runner + FileManager cleaner + moveToTrash
├── Models.swift            # CleanupKind / CleanupItem
└── Assets.xcassets/        # app icon
project.yml                 # xcodegen spec
```

## License

MIT. See [LICENSE](./LICENSE).

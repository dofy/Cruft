# CleanMyMac

A simple native **macOS app** to clean up the junk files generated during daily
development work — Xcode DerivedData, caches, logs, Homebrew leftovers, and more.
Rewritten from the original shell script into a SwiftUI app with a checklist UI,
live log, and a report of the disk space freed.

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/Swift-5-orange)

## Features

Pick exactly what to run. Unavailable tools (missing `brew`, `mas`, …) auto-disable.

**Update**
- **Homebrew** — `brew update && upgrade && upgrade --cask --greedy`
- **App Store** — `mas upgrade`

**Clean**
- **CocoaPods cache** — `pod cache clean --all`
- **Xcode** — DerivedData, Archives, Products, unavailable simulators, old iOS DeviceSupport (keeps latest)
- **System caches** — `~/Library/Caches`
- **Application logs** — `~/Library/Logs`
- **Trash** — `~/.Trash`
- **Homebrew cleanup** — `brew cleanup`
- **Ruby gems** — `gem cleanup`

File deletions run through Swift's `FileManager` (not `rm -rf`) so a single
protected file just gets skipped instead of aborting the whole run.

## Interface

- **Size estimates** — each cleanable directory shows its current disk usage,
  computed in the background, and re-estimated after a run.
- **Per-task details** — an ⓘ button on every row opens a popover listing the
  exact paths / commands that task touches.
- **Live log** — output streams into a console pane while tasks run.
- **Freed-space report** — the footer shows how much was reclaimed.
- **Confirmation gate** — deletions are irreversible, so a run must be confirmed.
- **Fixed window** — the window is a fixed size (non-resizable, no zoom / full
  screen) to keep the layout tidy.
- **Auto-disable** — tasks whose CLI tool is missing grey out automatically.

## Build & Run

Requires Xcode 16+ and [xcodegen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated, not committed.

```bash
xcodegen generate                 # regenerate CleanMyMac.xcodeproj
open CleanMyMac.xcodeproj         # then Run (⌘R) in Xcode
```

Or build from the command line:

```bash
xcodebuild -project CleanMyMac.xcodeproj -scheme CleanMyMac -configuration Release build
```

The app is **not sandboxed** — it needs to invoke `brew`/`mas`/`pod`/`gem` and
delete cache files in your home directory.

## Project layout

```
Sources/
├── CleanMyMacApp.swift     # @main App entry
├── ContentView.swift       # SwiftUI UI (checklist, log, footer)
├── CleanerViewModel.swift  # @MainActor state + run loop
├── CleanerEngine.swift     # maps each task to shell / file actions
├── Shell.swift             # Process runner + FileManager cleaner
└── Models.swift            # CleanupKind / CleanupItem
project.yml                 # xcodegen spec
cleanmymac.sh               # original script (legacy, kept for reference)
```

## Legacy CLI

The original one-shot script still works if you prefer the terminal:

```bash
sh cleanmymac.sh
```

## License

MIT. See [LICENSE](./LICENSE).

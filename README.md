# MacPilot

A personal all-in-one Mac utility. Native SwiftUI, no dependencies. Requires macOS 13+.

## Build & run
1. Install Xcode (or just the command line tools: `xcode-select --install`).
2. In this folder:
   ```
   ./build.sh            # builds build/MacPilot.app
   open build/MacPilot.app
   ./build.sh --install  # optional: copies to /Applications
   ```
Or open `Package.swift` in Xcode and press Run.

## What's in v0.1
- **Dashboard** – live CPU, memory, disk, battery (refreshes every 2s)
- **Cleaner** – size + clear of ~/Library/Caches, empty Trash (Finder will ask for Automation permission)
- **Toggles** – Keep Awake (caffeinate), show hidden files in Finder
- **Clipboard** – text history, in memory only, click to re-copy
- **Menu bar** – live CPU %, keep-awake toggle, open window

## Layout
- `MacPilotApp.swift` – app entry, window + menu bar extra
- `SystemStats.swift` – Mach/IOKit readers
- `Tools.swift` – shell helpers, cleaner, toggles
- `ClipboardStore.swift`, `ContentView.swift` – clipboard + UI

## Adding a module
Add a case to `Panel` in ContentView.swift, create a view, add it to the `switch`.

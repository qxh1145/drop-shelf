<div align="center">

# DropShelf

### A lightweight temporary drag-and-drop shelf for macOS

Collect files and folders in one floating Shelf, then drag them wherever you need.

<br>

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5%2B-F05138?logo=swift&logoColor=white)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-blue)
![Status](https://img.shields.io/badge/status-active%20development-orange)

<!-- Replace this with your real project logo later -->
<!-- <img src="docs/assets/logo.png" alt="DropShelf logo" width="120"> -->

</div>

---

## Overview

**DropShelf** is a lightweight macOS utility inspired by temporary drag-and-drop shelf workflows.

Instead of repeatedly switching between Finder windows, you can temporarily collect files and folders in a floating Shelf and move them all when you are ready.

### Core workflow

```text
Shake the mouse
      ↓
Shelf appears near the cursor
      ↓
Drop files / folders into the Shelf
      ↓
Collect multiple items
      ↓
Drag them to Finder or another app
```

DropShelf is built natively with **SwiftUI** and **AppKit** to provide a macOS-first experience.

> [!NOTE]
> DropShelf is currently under active development. APIs, UI, settings, and interaction behavior may change.

---

## Demo

<!-- Recommended: add a short GIF to docs/assets/demo.gif -->

<!--
<p align="center">
  <img src="docs/assets/demo.gif" alt="DropShelf demo" width="760">
</p>
-->

_Add a short GIF or screen recording here showing: shake mouse → Shelf appears → drop files → drag them back out._

---

## Features

- Temporary floating Shelf for files and folders
- Mouse gesture to quickly create a Shelf
- Drop multiple files and folders into one place
- Drag items from the Shelf into Finder or compatible apps
- Remove individual items
- Clear and close the Shelf
- Drag handle for repositioning the Shelf
- **AirDrop All**
- **Zip All…**
- Native macOS menu integration
- Menu bar integration
- Translucent material-style interface
- Light and Dark Mode support
- Native drag-and-drop behavior

---

## Installation

### Download a Release

When packaged builds are available:

1. Open the repository's **Releases** page.
2. Download the latest `.dmg`, `.zip`, or `.app`.
3. Extract the archive if necessary.
4. Move:

```text
DropShelf.app
```

to:

```text
/Applications
```

5. Launch DropShelf.

### macOS security warning

Development or unsigned builds may be blocked by Gatekeeper.

If you trust the build, open:

```text
System Settings
→ Privacy & Security
```

and allow DropShelf to open.

DropShelf may also request macOS permissions required for mouse monitoring or other system-level interactions.

---

# Usage

## 1. Launch DropShelf

Open `DropShelf.app`.

DropShelf is designed to behave like a lightweight utility rather than a traditional document-based macOS app.

## 2. Open a Shelf

Perform the configured mouse gesture.

The floating Shelf appears close to the cursor.

## 3. Add files

Drag one or more files or folders from Finder onto the Shelf.

```text
Finder
  │
  │ drag
  ▼
┌─────────────────────────────┐
│          DropShelf          │
│                             │
│  File A   File B   Folder C │
└─────────────────────────────┘
```

## 4. Drag items out

Drag an item from DropShelf into:

- Finder
- Desktop
- another folder
- another application that accepts file drops

## 5. Remove an item

Use the **×** button on an item to remove it from the current Shelf.

This removes the reference from DropShelf; it does **not** delete the original file.

## 6. Move the Shelf

Drag the handle at the top of the Shelf.

## 7. Additional actions

Open the **•••** menu.

Available actions currently include:

| Action | Description |
|---|---|
| AirDrop All | Opens the AirDrop flow for items on the Shelf |
| Zip All… | Creates a ZIP archive from Shelf items |

## 8. Close the Shelf

Click the close button in the upper-right corner.

The current Shelf contents are cleared when the Shelf is closed.

---

# Contributing

Contributions are welcome.

You can help with:

- bug fixes
- UI polish
- accessibility
- drag-and-drop behavior
- performance
- macOS integration
- tests
- documentation
- new Shelf actions

For large behavioral or architectural changes, consider opening an Issue first.

---

# Contributor Setup

## Requirements

You will need:

- macOS
- Xcode
- Git
- Xcode Command Line Tools

The latest stable Xcode release is recommended.

Check Git:

```bash
git --version
```

Check Command Line Tools:

```bash
xcode-select -p
```

Install them if necessary:

```bash
xcode-select --install
```

---

## Clone the repository

```bash
git clone <repository-url>
cd DropShelf
```

Replace `<repository-url>` with the repository's actual Git URL.

Example:

```bash
git clone https://github.com/USERNAME/DropShelf.git
cd DropShelf
```

---

## Open in Xcode

From Terminal:

```bash
open DropShelf.xcodeproj
```

Or:

```text
Xcode
→ File
→ Open…
→ DropShelf.xcodeproj
```

If the project later uses an Xcode workspace, open the `.xcworkspace` file instead.

---

## Build and run

In Xcode:

1. Select the **DropShelf** scheme.
2. Select **My Mac** as the destination.
3. Press:

```text
⌘R
```

or click **Run ▶**.

To clean the build:

```text
Product
→ Clean Build Folder
```

Shortcut:

```text
⇧⌘K
```

---

# Project Structure

The current codebase is organized by responsibility:

```text
DropShelf
├── App
│   ├── DropShelfApp
│   ├── AppDelegate
│   └── MenuBarController
│
├── Mouse
│   └── Mouse gesture / monitoring logic
│
├── Shelf
│   ├── ShelfItem
│   ├── ShelfManager
│   ├── ShelfPanel
│   ├── ShelfDropHostingView
│   ├── ShelfView
│   └── ShelfItemView
│
├── Settings
│   ├── AppPreferences
│   ├── SettingsView
│   └── SettingsWindowController
│
├── Resources
│   └── Info
│
├── Assets.xcassets
│
└── DropShelfTests
```

## App

Contains application lifecycle and top-level integration.

Typical responsibilities include:

- startup
- app delegate behavior
- shared service initialization
- menu bar integration

## Mouse

Contains the macOS mouse-monitoring and gesture logic used to trigger the Shelf.

## Shelf

The core feature area of DropShelf.

It includes:

- Shelf state
- item models
- floating window behavior
- SwiftUI Shelf interface
- drag-and-drop handling
- item selection/removal
- AirDrop and ZIP actions

## Settings

Contains app preferences and settings-window related code.

## Assets.xcassets

Contains:

- app icons
- custom menu icons
- visual assets

## DropShelfTests

Contains automated tests.

---

# Architecture

DropShelf intentionally combines:

```text
SwiftUI
   +
AppKit
```

SwiftUI is used where declarative UI works well.

AppKit is used for macOS-specific behavior where lower-level control is useful or necessary.

Examples include:

- floating `NSPanel` behavior
- cursor management
- native window dragging
- global/local mouse events
- drag-and-drop integration
- macOS menus
- system services

This hybrid architecture helps DropShelf remain native while avoiding unnecessary abstractions around macOS APIs.

---

# Development Workflow

Start from the latest development branch:

```bash
git checkout develop
git pull origin develop
```

Create a dedicated branch:

```bash
git checkout -b feature/my-feature
```

Examples:

```bash
git checkout -b feature/multi-select
git checkout -b feature/keyboard-shortcuts
git checkout -b fix/shelf-position
git checkout -b fix/drag-preview
git checkout -b refactor/mouse-monitor
```

Inspect changes before committing:

```bash
git status
git diff
```

Commit:

```bash
git add .
git commit -m "feat: add multi-item selection"
```

Push:

```bash
git push -u origin feature/my-feature
```

Then open a Pull Request.

---

# Commit Convention

DropShelf recommends **Conventional Commits**.

| Prefix | Usage |
|---|---|
| `feat:` | New functionality |
| `fix:` | Bug fix |
| `refactor:` | Internal restructuring |
| `docs:` | Documentation |
| `test:` | Tests |
| `chore:` | Maintenance |
| `style:` | Formatting / visual-only adjustments |

Examples:

```text
feat: add AirDrop action to shelf menu
fix: prevent shelf from closing during drag
fix: keep shelf inside visible screen bounds
refactor: extract mouse monitoring service
docs: improve contributor setup
test: add shelf manager tests
```

---

# Pull Request Guidelines

Keep Pull Requests focused.

A good PR should:

- solve one clear problem
- explain what changed
- explain why the change is needed
- include screenshots or video for UI changes
- build successfully
- avoid unrelated refactors
- include tests when practical

Suggested PR template:

```markdown
## What changed

Describe the implementation.

## Why

Describe the problem being solved.

## Testing

- [ ] Project builds successfully
- [ ] Tested adding a single file
- [ ] Tested adding multiple files/folders
- [ ] Tested dragging items back into Finder
- [ ] Tested removing an item
- [ ] Tested Shelf close/clear behavior
- [ ] Tested Light Mode
- [ ] Tested Dark Mode

## Screenshots / Video

Add screenshots or a short recording for UI changes.

## Notes

Mention limitations, follow-up work, or important implementation details.
```

---

# Testing

Run automated tests with:

```text
⌘U
```

Before submitting a Pull Request, manually verify the core workflow.

### Core regression checklist

- [ ] App launches successfully
- [ ] Mouse gesture opens a Shelf
- [ ] Shelf appears in the expected screen position
- [ ] Single file can be dropped into the Shelf
- [ ] Multiple files can be dropped into the Shelf
- [ ] Folders can be dropped into the Shelf
- [ ] Files can be dragged back into Finder
- [ ] Individual items can be removed
- [ ] Shelf can be repositioned
- [ ] AirDrop All works
- [ ] Zip All works
- [ ] Shelf closes correctly
- [ ] Shelf clears correctly
- [ ] A new Shelf can be created after closing
- [ ] UI behaves correctly in Light Mode
- [ ] UI behaves correctly in Dark Mode

---

# Debugging

## Xcode console

When DropShelf is running from Xcode, use the Debug Console for logs and runtime errors.

## macOS Console

You can also open Console.app:

```bash
open -a Console
```

## Open Terminal in the project folder

From Finder:

```text
Right click project folder
→ Services
→ New Terminal at Folder
```

Or:

```bash
cd /path/to/DropShelf
```

---

# Assets

Add custom images and icons to:

```text
Assets.xcassets
```

For monochrome macOS menu icons, vector assets are preferred.

Recommended configuration:

```text
Format: SVG or PDF vector
Render As: Template Image
```

Template images allow macOS to automatically apply appropriate menu tinting for Light and Dark Mode.

---

# Code Style

When contributing:

- prefer small, focused Swift types
- keep business/state logic out of SwiftUI views where possible
- use descriptive names
- prefer native macOS frameworks over unnecessary dependencies
- use SwiftUI for declarative presentation
- use AppKit when platform-specific control is required
- avoid force unwraps unless the invariant is guaranteed
- keep UI behavior consistent with macOS conventions
- keep DropShelf lightweight

---

# Privacy & Permissions

DropShelf is designed as a local macOS utility.

Features involving mouse monitoring or system interaction may require macOS permissions.

When adding a permission-sensitive feature:

1. request only the minimum permission required
2. clearly explain why the permission is needed
3. add the appropriate usage description where required
4. avoid collecting data unrelated to the feature
5. avoid transmitting user data unless explicitly necessary and documented

---

# Roadmap

Some possible future improvements:

- [ ] configurable mouse gestures
- [ ] keyboard shortcut to create a Shelf
- [ ] richer multi-selection
- [ ] improved drag previews
- [ ] additional Shelf actions
- [ ] better multi-monitor positioning
- [ ] animation polish
- [ ] accessibility improvements
- [ ] persistent preferences
- [ ] improved Finder integration
- [ ] automated UI tests
- [ ] signed and notarized releases

The roadmap is flexible while the core Shelf interaction is being stabilized.

---

# Reporting Bugs

When reporting a bug, please include:

- macOS version
- Mac model / architecture if relevant
- DropShelf version or commit
- steps to reproduce
- expected behavior
- actual behavior
- screenshots or video when useful
- relevant Xcode / Console logs

A good reproduction report makes issues significantly easier to fix.

---

# License

A license has not yet been specified in this README.

Before publishing the project broadly, add a `LICENSE` file and update this section.

Common choices for open-source Swift projects include:

- MIT
- Apache-2.0
- GPL-3.0

---

# Acknowledgements

DropShelf is inspired by the temporary drag-and-drop shelf interaction pattern available in macOS productivity tools such as **Dropover**.

DropShelf is an independent project and is not affiliated with Dropover or Apple.

---

<div align="center">

### Built natively for macOS

**SwiftUI · AppKit · Swift**

</div>

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
- Optional shake trigger and a customizable global keyboard shortcut
- Optional Dock icon
- Drop multiple files and folders into one place
- Drop or paste text, web links, and images: they become `.txt`, `.webloc`, and `.png` files
- Per-item Quick Look, Open, Show in Finder, Copy, Copy Path, and Share
- Keyboard control: Space, Delete, Return, arrows, Esc, Command-A/C/V/O
- Recent Shelves follow files that are renamed or moved
- Several Shelves at once: **New Shelf** (Command-N), drag items between Shelves
- Batch convert and batch rename the selected items
- Image Tools: resize, compress, and remove metadata (location, camera info)
- Open the Shelf at the pointer or where you last left it, snap to screen edges, Keep on Screen
- Search (Command-F) filters Shelf items and Recent Shelves
- Finder Services, Open With / Dock drop, `dropshelf://` links, and Shortcuts actions
- English and Vietnamese, following the macOS language setting
- Daily update check against GitHub Releases
- Drag items from the Shelf into Finder or compatible apps
- Remove individual items
- Clear and close the Shelf
- Drag handle for repositioning the Shelf
- **AirDrop All**
- **Zip All…**
- **Recent Shelves** history retained for 72 hours
- Global **Command-Shift-H** shortcut for recent shelves
- Custom Shelf names and pinned history that does not expire
- Fast access to pinned shelves from the menu bar
- Optional close-when-empty and 10-second inactivity auto-hide behaviors
- Per-item native image and video conversion with content-based format detection
- Native macOS menu integration
- Menu bar integration
- Translucent material-style interface
- Light and Dark Mode support
- Native drag-and-drop behavior
- Three-step first-run onboarding with an interactive shake practice
- Reopen the guide any time from the menu bar with **Getting Started…**

---

## Installation

### Download a Release

1. Open the repository's **Releases** page.
2. Download the latest `DropShelf-x.y.z.dmg`.
3. Open the DMG and drag:

```text
DropShelf.app
```

to:

```text
/Applications
```

4. Launch DropShelf.

DropShelf checks GitHub once a day for a newer release and offers its download
page. Turn this off in **Settings → General**, or check by hand from the menu bar
with **Check for Updates…**.

### macOS security warning

Release builds are signed ad hoc, not with an Apple Developer ID, so Gatekeeper
blocks the first launch.

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
On first launch, a short guide explains the Finder workflow, lets you practice
the shake gesture, and summarizes the keyboard shortcuts. Closing the guide does not mark it complete; choose **Skip**
or finish the guide to dismiss it permanently. You can reopen it later from the
menu bar with **Getting Started…**.

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
| Recent Shelves… | Shows Shelf sessions closed during the last 72 hours |

Each file item also has its own **•••** menu. For supported single-frame images,
choose **Convert to** and then an available target format. DropShelf asks for a
destination folder, creates a new collision-free output file, and leaves the
source untouched. Current native conversions are HEIC/HEIF/HEICS → JPEG/PNG,
JPEG → PNG/HEIC, PNG → JPEG, and MOV ↔ MP4 when the existing codecs are
compatible with the target container. PDF → PNG/JPEG renders every page at
144 DPI, while JPEG/PNG/HEIC → PDF creates a one-page PDF. Unsupported or risky
targets are not shown.

For a multi-page PDF, DropShelf creates one image per page using names such as
`Document - Page 1.png`, then reveals all generated files in Finder.

CSV/XLSX conversion is intentionally not exposed: CSV cannot preserve workbook
sheets, formulas, styles, charts, or reliable cell types, while XLSX → CSV needs
an explicit sheet and data-loss policy.

## 8. Keyboard shortcuts

Click the Shelf once to give it keyboard focus.

| Key | Action |
|---|---|
| Space / Command-Y | Quick Look the selection |
| Return / Command-O | Open the selection |
| Delete | Remove the selection from the Shelf (files are not deleted) |
| ← / → (Shift to extend) | Move the selection |
| Command-A | Select all |
| Command-C | Copy the selected files |
| Command-V | Paste files, text, links, or images |
| Command-N | Open a new Shelf beside the current one |
| Command-F | Search items (or Recent Shelves); Esc closes the search |
| Esc | Clear selection, then hide the Shelf (items are kept) |

Double-click an item to open it.

## 9. Multiple Shelves

Choose **••• → New Shelf**, press **Command-N** on a Shelf, or use **New Shelf**
in the menu bar. The new Shelf opens beside the current one. Drag an item from
one Shelf to another to move it. Shaking the pointer or pressing the activation
shortcut brings back the Shelf you used last. Every other Shelf with items is
listed under **Open Shelves** in the menu bar.

## 10. Batch convert and rename

Select several items (Command-click), then open any selected item's **•••** menu:

- **Convert N Items to** lists only the formats that every selected file supports.
  Choose a destination folder once. All outputs are revealed together.
- **Rename N Items…** renames the files on disk to `Name 1.ext`, `Name 2.ext`, …
  in Shelf order. Extensions are kept. If any target name is already taken,
  nothing is renamed.

## 11. Image Tools

For JPEG, PNG, HEIC, and TIFF images, the item **•••** menu has **Image Tools**.
They act on the whole selection when the item is selected:

- **Resize**: Large (2048 px), Medium (1024 px), or Small (512 px) on the longest side.
- **Compress**: re-encodes JPEG and HEIC at 60% quality.
- **Remove Metadata**: strips location, camera, and other metadata. The
  orientation is kept. JPEG and PNG pixels are copied without recompression.

Results are saved next to the original as `Name (1024px).jpg`,
`Name (compressed).jpg`, or `Name (no metadata).jpg`, then added to the Shelf.
Originals are never changed.

## 12. Shelf position

- **Settings → Shelf → Open Shelf** chooses where shaking or the shortcut shows
  the Shelf: near the pointer, or where you last dragged it.
- **Snap to screen edges** docks a Shelf dropped close to an edge.
- **••• → Keep on Screen** keeps that Shelf visible. It is not auto-hidden, Esc does
  not hide it, and it stays open when empty. Closing the Shelf turns this off.

## 13. Search

Click the magnifying glass or press **Command-F**. On a Shelf, the field filters
items by file name. Select All, arrow keys, AirDrop All, and Zip All then act on
the matching items only. In Recent Shelves, it matches Shelf names and file names.

## 14. Add files from other apps

- **Services**: right-click files in Finder and choose **Services → Add to DropShelf**.
  Selected text or links in other apps use **Add Selection to DropShelf**. If the
  entries don't appear, enable them in **System Settings → Keyboard → Keyboard
  Shortcuts → Services**.
- **Open With / Dock**: open files with DropShelf, or drop them on its Dock icon.
- **Links**:

| URL | Action |
|---|---|
| `dropshelf://open` | Show the current Shelf |
| `dropshelf://new` | Open a new Shelf |
| `dropshelf://history` | Show Recent Shelves |
| `dropshelf://add?path=/path/to/file&path=…` | Add files to the current Shelf |

  For example: `open "dropshelf://add?path=$HOME/Desktop/report.pdf"`
- **Shortcuts**: **Add Files to DropShelf**, **Open DropShelf**, and
  **New DropShelf Shelf** actions.

## 15. Close the Shelf

Click the close button in the upper-right corner.

The current Shelf contents are cleared when the Shelf is closed. DropShelf keeps
only their file references in **Recent Shelves** for 72 hours; it never copies or
moves the original files. Open **••• → Recent Shelves…** or press **Command-Shift-H**
to restore a recent Shelf. Missing or deleted files are removed from history
automatically. Use **••• → Name Shelf…** before closing to add a memorable name,
then click the pin button beside **•••** to keep that Shelf beyond 72 hours. You
can also pin or unpin an entry inside Recent Shelves. The menu bar's **Pinned
Shelves** submenu shows each Shelf's name, date, item count, and file summary;
restoring one preserves its memorable name.

DropShelf uses an adaptive Shelf layout: file actions appear on hover, multiple
selection gets a compact status bar, and valid Finder drags receive an accent
drop target. Recent Shelves are grouped into Pinned, Today, Yesterday, and
Earlier sections. Settings use a compact sidebar for General, Activation, Shelf,
History, and About.

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

## Localization

User-facing strings live in `DropShelf/Resources/Localizable.xcstrings`
(English source, Vietnamese translation). Wrap new strings in SwiftUI literals or
`String(localized:)`, then add the translation in Xcode's String Catalog editor.
To preview another language, edit the scheme and set **Run → Options → App
Language**.

---

## Publishing a release

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) and commit.
2. Tag the commit with the same version and push the tag:

```bash
git tag v1.8.0 && git push origin v1.8.0
```

The **Release** workflow checks that the tag matches `MARKETING_VERSION`, builds
the app, signs it ad hoc, packages `DropShelf-1.8.0.dmg`, and publishes a GitHub
release with generated notes. Installed copies see it on their next update check.

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
├── Conversion
│   ├── FileFormat
│   └── ConversionService
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


# Acknowledgements

DropShelf is inspired by the temporary drag-and-drop shelf interaction pattern available in macOS productivity tools such as **Dropover**.

DropShelf is an independent project and is not affiliated with Dropover or Apple.

---

<div align="center">

### Built natively for macOS

**SwiftUI · AppKit · Swift**

</div>

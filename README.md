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


# Acknowledgements

DropShelf is inspired by the temporary drag-and-drop shelf interaction pattern available in macOS productivity tools such as **Dropover**.

DropShelf is an independent project and is not affiliated with Dropover or Apple.

---

<div align="center">

### Built natively for macOS

**SwiftUI · AppKit · Swift**

</div>

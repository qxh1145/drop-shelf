# DropShelf

A focused native macOS MVP for temporarily holding Finder file and folder references during drag and drop.

## Run

1. Open `DropShelf.xcodeproj` in Xcode.
2. Select the **DropShelf** scheme and **My Mac**.
3. Press **Run** (`⌘R`).

The app is an agent app, so it does not show a Dock icon. Use the DropShelf icon in the menu bar to open Settings or quit the app. Settings includes launch-at-login and shake-sensitivity controls. Drag one or more files in Finder, shake the pointer left/right, and drop them onto the shelf. Command-click items to form a group, then drag an item or the selected group back to Finder. Use the **…** menu in the Shelf header to AirDrop every item or create one ZIP containing them all. An empty shelf remains open; use the shelf's close button to close and clear it.

## Notes

- DropShelf retains in-memory file URLs only. It never copies, moves, imports, uploads, or persists files.
- There is no polling or background timer. The global drag listener is armed only while Finder is the active app, and shake processing is throttled to 120 Hz with constant-size state.
- Shelf and Settings windows are created only when needed and released after they are closed. File thumbnails use a bounded 64-entry / 3 MiB cache that is cleared with the Shelf.
- App Nap remains enabled; DropShelf does not create a long-lived `ProcessInfo` activity assertion.
- The App Sandbox capability is intentionally disabled for this MVP so dropped file URLs remain usable for the lifetime of the app without persistent security-scoped bookmarks.

## macOS permission

Depending on the macOS version and privacy state, global drag monitoring may require **Input Monitoring** permission. If shaking a dragged Finder item does not open the shelf, go to **System Settings → Privacy & Security → Input Monitoring**, enable DropShelf, then quit and reopen it. If macOS instead lists DropShelf under **Accessibility**, enable it there as well.

For the most reliable launch-at-login behavior, move `DropShelf.app` to `/Applications` before enabling that option. The included downloadable build is ad-hoc signed, not Developer ID notarized, so the first launch may require Control-clicking the app and choosing **Open**.

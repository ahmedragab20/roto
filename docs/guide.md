# roto guide

How to build roto, grant its permissions, and use each tool. For every config key, see [config.md](config.md). For why roto exists, see [why.md](why.md).

## Contents

- [Requirements](#requirements)
- [Build and run](#build-and-run)
- [Signing (so Accessibility sticks)](#signing-so-accessibility-sticks)
- [Window movement and focus](#window-movement-and-focus)
- [Shortcut troubleshooting](#shortcut-troubleshooting)
- [App shortcuts](#app-shortcuts)
- [Clipboard history and emoji](#clipboard-history-and-emoji)
- [Window switcher](#window-switcher)
- [Cheatsheet](#cheatsheet)
- [Customize shortcuts](#customize-shortcuts)
- [Emoji catalog](#emoji-catalog)

## Requirements

- macOS 14+
- Swift 6 Command Line Tools (`xcode-select --install` is enough; Xcode is not required)

## Build and run

```bash
make run          # build, bundle, open build/roto.app
make test         # core and native UI tests (Swift Testing; test-only dependency)
make install      # copy to /Applications/roto.app
```

On first launch, grant **Accessibility**, shown as **Device Control and Data Access** on macOS 27. roto uses this access only to move, focus, close, and minimize windows and to synthesize paste / unicode insertion.

The menu bar icon (the roto mark) exposes Keyboard Shortcuts…, Customize Shortcuts…, Switch Windows…, Reload config, Open config, Launch at login, permission state, and Quit. Accessibility status is checked again whenever you open the menu, so grants and revocations made in System Settings do not leave a stale label.

## Signing (so Accessibility sticks)

Changes to an ad-hoc-signed build (`codesign -s -`) can invalidate its Accessibility approval. System Settings may still show an enabled entry for the previous build even though the new executable is not trusted.

Create a stable local identity once:

1. Open **Keychain Access**, not Passwords. In the menu bar at the top of the screen, choose **Keychain Access → Certificate Assistant → Create a Certificate…**.
2. Set **Name** to `roto-dev`, **Identity Type** to **Self Signed Root**, and **Certificate Type** to **Code Signing**. Use the **login** keychain if asked.
3. If the certificate is untrusted, double-click it, expand **Trust**, and set **Code Signing → Always Trust**, leaving other trust settings unchanged. Close the window and authenticate locally if asked.

Quit any running copy of roto, then build with that identity:

```bash
CODESIGN_IDENTITY=roto-dev make run
```

Keep the private key in Keychain Access; there is no need to export it or add signing certificates to the repository.

Then approve Accessibility for that identity once. Keep using the same certificate for subsequent builds; the bundle script automatically selects `roto-dev` when available.

If window actions or pasting stop working after a rebuild, quit roto, remove its outdated entry from **System Settings → Privacy & Security → Accessibility** (or **Device Control and Data Access**), and add and enable the exact app bundle you launch (`build/roto.app` for local builds, or `/Applications/roto.app` for an installed copy). Then reopen roto without rebuilding again. Merely seeing an enabled entry with the same name does not verify the current executable’s approval. In older builds, **Reload config** refreshes a stale menu label, but does not repair approval or grant event-posting access.

## Window movement and focus

The default display shortcuts do two different things:

| Keys | Action |
| --- | --- |
| ⌃⌥⌘← / ⌃⌥⌘→ | Move the focused window to the previous / next display |
| ⌃⌥⇧← / ⌃⌥⇧→ | Focus a window on the previous / next display; do not move it |
| ⌃⌥⇧H/J/K/L | Focus the nearest window left / down / up / right |

Displays cycle left-to-right, then bottom-to-top for displays with the same horizontal origin. Moving preserves relative position and size where possible, while keeping the requested frame within the destination’s usable area (excluding the Dock and menu bar). A window straddling unequal-height displays is assigned by its center, or by largest overlap if its center lies in a desktop gap. A fully off-desktop window uses the nearest display.

Some apps enforce minimum sizes or refuse move/resize requests, especially in native full-screen mode. roto reads back the actual size before the final positioning step and keeps the top-left corner reachable when a window cannot fit. An unmet request appears under **Last window action** in the menu; a successful subsequent move/resize clears it. Exit native full-screen or try another app to distinguish app restrictions from shortcut problems.

Display focus chooses the frontmost eligible window on the adjacent display in the current visible Spaces. An empty adjacent display, or a single-display setup, leaves focus unchanged. Newer roto commands cancel pending delayed window raises and activation fallbacks from older requests.

## Shortcut troubleshooting

1. Check **Accessibility: granted** in the menu. If it is missing after rebuilding, follow [Signing](#signing-so-accessibility-sticks).
2. Look for **Shortcut … unavailable** or a **Global shortcut handler unavailable** warning. These include the macOS error code; a valid config does not guarantee macOS accepted every global shortcut. Choose another combination if it is reserved, then use **Reload config** to retry. Successfully registered shortcuts remain active.
3. For movement problems, check **Last window action** and use the move keys rather than the focus keys above.
4. A config error keeps the last good config active. Physical aliases such as `ctrl+alt+.` and `ctrl+alt+period` cannot be assigned twice, even across different sections.

`make test` covers geometry, validation, callback cancellation, registration failures, and frame-write behavior with controlled native boundaries. It does not certify another app’s Accessibility implementation or system shortcut reservations. After a rebuild, test both move directions across the connected displays, rapid focus changes, and popup/app shortcuts using disposable windows and non-sensitive text. Test close, quit, and clipboard deletion only on disposable data.

## App shortcuts

`[hotkeys.apps]` maps a hotkey to an app, given as a bundle id (`com.mitchellh.ghostty`), an app name (`Ghostty`), or a path to an `.app`. Find a bundle id with `osascript -e 'id of app "Ghostty"'`.

- Not running: launches it.
- Running but not in front: brings it forward. If none of its windows are visible on this Space, it behaves like a Dock click: it restores a minimized window, switches to the Space with its window, or opens a new window.
- Already in front: `[apps] when_focused` decides. `cycle` (default) brings its next window forward, `hide` hides the app, `none` does nothing.

## Clipboard history and emoji

The popups open with the `[hotkeys] clipboard` / `emoji` combos. The app you were typing in keeps focus, so ↵ pastes (clipboard) or types the emoji straight into the field you were in. Without Accessibility permission macOS blocks the paste: the popup shows a banner, and the entry is still on the clipboard for ⌘V.

Both popups keep a fixed viewport: longer results scroll instead of increasing the window height.

Every word you type must match (in any order), matching ignores case and accents, and it tolerates small typos in words of 5+ letters. Clipboard results list whole-word matches first, newest first; emoji results favor commonly used and recently used emoji.

**Clipboard**

| Key | Action |
| --- | --- |
| ↵ | Paste into the previous app |
| ⌘↵ / ⌘C | Copy without pasting (⌘C copies the entry when no search text is selected) |
| ⌘1–⌘9 | Paste the Nth entry |
| ⌘⌫ | Delete the entry |
| ⌘Y | Quick Look the image or file; press it again to close the preview |
| ⌘O | Open the image or file in its default app (Preview for images and PDFs) |
| ↑ ↓, ⌃P ⌃N | Move |
| ⌘↑ ⌘↓, Home, End | First / last |
| Page Up / Page Down | Move 8 rows |
| Double-click | Paste |
| esc | Clear search, then close |

The clipboard popup shows a preview of the selected entry (full text, image, or file list) with its source app and time; it records text, images, and copied files.

Quick Look belongs to the popup that opened it: closing the popup closes the preview with it, and clicking away closes both.

**Emoji**

| Key | Action |
| --- | --- |
| ↵ / click | Type the emoji into the previous app |
| ⌘↵ | Copy |
| Arrow keys, ⌃P ⌃N | Move in the grid |
| ⇥ / ⇧⇥ | Next / previous group (when not searching) |
| Page Up / Page Down | Move 6 rows |
| esc | Clear search, then close |

With an empty search the grid starts with Recently Used, then each Unicode group; hovering an emoji shows its name in the footer.

## Window switcher

`[hotkeys] windows` opens a searchable list of open windows: the current window first, then the rest front to back, then minimized windows, windows of hidden apps, and apps with no window on this Space. The window behind the current one is preselected, so the hotkey then ↵ flips back like ⌘⇥. Search matches window titles and app names. The list is rebuilt in the background when you switch apps, so it is already in the right order when the popup opens instead of reshuffling a moment after.

The right pane shows the window's app, size, position, display, and state, with a map of where it sits across your displays. Live window previews are optional: "Show live window previews…" asks for Screen Recording, and only the selected window is captured, in memory.

**Keys**

| Key | Action |
| --- | --- |
| ↵ | Switch to the window |
| ⌘1–⌘9 | Switch to window 1–9 |
| ⌘W | Close the window |
| ⌘M | Minimize or restore |
| ⌘H | Hide or show the app |
| ⌘Q | Quit the app |
| ↑ ↓, ⌃P ⌃N | Move |
| Page Up / Page Down | Move 8 rows |
| esc | Clear search, then close |

Windows on other Spaces are not listed one by one; their app appears as a "No windows on this Space" row, and choosing it lets macOS switch to that app.

## Cheatsheet

Keyboard Shortcuts… in the menu bar, or `[hotkeys] cheatsheet`, lists every shortcut from your current config (popups, apps, window layout, displays, focus) plus the keys inside each popup. Type to filter; click **Customize Shortcuts…** or press ⌘, to edit keymaps.

## Customize shortcuts

Open **Customize Shortcuts…** from the menu bar or cheatsheet. Filter the list, choose a window action, edit an app target, or change a shortcut directly. **Add Window**, **Add App**, and **Add Popup** create bindings; the trash button removes one. The window action menu includes all built-in actions and layouts already defined in your config.

Click **Record** and press a combination with Control, Option, Shift, or Command. roto pauses its hotkeys while listening so the shortcut does not run its action. Esc stops recording; you can also type a combo such as `ctrl+alt+t`. macOS and other apps can reserve shortcuts that roto cannot capture or register.

Click **Save** or press ⌘S to validate and apply the draft. **Cancel** (Esc when not recording) discards it. Clicking away only hides the draft; reopen the editor to continue. If the file changed elsewhere, **Discard & Reload**, then reapply your edits. To change layout geometry or non-keymap settings, use **Open config…**. See [Keymap editor](config.md#keymap-editor) for validation and saving details.

## Emoji catalog

`Sources/Roto/Resources/emoji.json` is committed. Rebuild it from Unicode/CLDR with:

```bash
make gen-emoji
```

That script is the only network use in the repo and is not part of the running app. Keywords come from CLDR annotations, including derived annotations for sequences such as flags and ZWJ emoji. At launch, roto keeps only glyphs present in Apple Color Emoji (so missing-font tofu never appears) and drops the Israeli flag plus Jewish and Christian signs.

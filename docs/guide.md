# roto guide

How to build roto, grant its permissions, and use each tool. For every config key, see [config.md](config.md). For why roto exists, see [why.md](why.md).

## Contents

- [Requirements](#requirements)
- [Build and run](#build-and-run)
- [Signing (so Accessibility sticks)](#signing-so-accessibility-sticks)
- [App shortcuts](#app-shortcuts)
- [Clipboard history and emoji](#clipboard-history-and-emoji)
- [Window switcher](#window-switcher)
- [Cheatsheet](#cheatsheet)
- [Emoji catalog](#emoji-catalog)

## Requirements

- macOS 14+
- Swift 6 Command Line Tools (`xcode-select --install` is enough; Xcode is not required)

## Build and run

```bash
make run          # build, bundle, open build/roto.app
make test         # RotoCore unit tests (Swift Testing; test-only dependency)
make install      # copy to /Applications/roto.app
```

On first launch, grant **Accessibility**. roto uses it only to move, focus, close, and minimize windows and to synthesize paste / unicode insertion.

The menu bar icon (the roto mark) exposes Keyboard Shortcuts…, Switch Windows…, Reload config, Open config, Launch at login, permission state, and Quit.

## Signing (so Accessibility sticks)

Ad-hoc signing (`codesign -s -`) changes the code identity on every rebuild, and macOS will ask for Accessibility again.

Create a stable local identity once:

```bash
# Keychain Access → Certificate Assistant → Create a Certificate
# Name: roto-dev  Identity Type: Self Signed Root  Certificate Type: Code Signing
export CODESIGN_IDENTITY="roto-dev"
make run
```

Then approve Accessibility for that identity once.

## App shortcuts

`[hotkeys.apps]` maps a hotkey to an app, given as a bundle id (`com.mitchellh.ghostty`), an app name (`Ghostty`), or a path to an `.app`. Find a bundle id with `osascript -e 'id of app "Ghostty"'`.

- Not running: launches it.
- Running but not in front: brings it forward. If none of its windows are visible on this Space, it behaves like a Dock click: it restores a minimized window, switches to the Space with its window, or opens a new window.
- Already in front: `[apps] when_focused` decides. `cycle` (default) brings its next window forward, `hide` hides the app, `none` does nothing.

## Clipboard history and emoji

The popups open with the `[hotkeys] clipboard` / `emoji` combos. The app you were typing in keeps focus, so ↵ pastes (clipboard) or types the emoji straight into the field you were in. Without Accessibility permission macOS blocks the paste: the popup shows a banner, and the entry is still on the clipboard for ⌘V.

Every word you type must match (in any order), matching ignores case and accents, and it tolerates small typos in words of 5+ letters. Clipboard results list whole-word matches first, newest first; emoji results favor commonly used and recently used emoji.

**Clipboard**

| Key | Action |
| --- | --- |
| ↵ | Paste into the previous app |
| ⌘↵ / ⌘C | Copy without pasting (⌘C copies the entry when no search text is selected) |
| ⌘1–⌘9 | Paste the Nth entry |
| ⌘⌫ | Delete the entry |
| ⌘Y | Quick Look the image or file |
| ⌘O | Open the image or file in its default app (Preview for images and PDFs) |
| ↑ ↓, ⌃P ⌃N | Move |
| ⌘↑ ⌘↓, Home, End | First / last |
| Page Up / Page Down | Move 8 rows |
| Double-click | Paste |
| esc | Clear search, then close |

The clipboard popup shows a preview of the selected entry (full text, image, or file list) with its source app and time; it records text, images, and copied files.

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

`[hotkeys] windows` opens a searchable list of open windows: the current window first, then the rest front to back, then minimized windows, windows of hidden apps, and apps with no window on this Space. The window behind the current one is preselected, so the hotkey then ↵ flips back like ⌘⇥. Search matches window titles and app names.

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

Keyboard Shortcuts… in the menu bar, or `[hotkeys] cheatsheet`, lists every shortcut from your current config (popups, apps, window layout, displays, focus) plus the keys inside each popup. Type to filter; ⌘, opens the config file.

## Emoji catalog

`Sources/Roto/Resources/emoji.json` is committed. Rebuild it from Unicode/CLDR with:

```bash
make gen-emoji
```

That script is the only network use in the repo and is not part of the running app. Keywords come from CLDR annotations, including derived annotations for sequences such as flags and ZWJ emoji. At launch, roto keeps only glyphs present in Apple Color Emoji (so missing-font tofu never appears) and drops the Israeli flag plus Jewish and Christian signs.

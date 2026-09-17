# Configuration

roto reads `~/.config/roto/config.toml`. If the file is missing, it is created from the bundled default. Edits are picked up automatically. A bad file never kills the app: the last good config stays active and the menu bar icon shows the error.

## Keymap editor

Choose **Customize Shortcuts…** from the menu bar or the cheatsheet (⌘,). The popup edits all configurable keymaps:

- `[hotkeys.window]`: add, change, or remove bindings for built-in window actions and existing `layout:NAME` layouts.
- `[hotkeys.apps]`: add, change, or remove bindings using a bundle ID, app name, or `.app` path.
- `[hotkeys]`: change, remove, or add the `clipboard`, `emoji`, `windows`, and `cheatsheet` shortcuts. Each popup can have one shortcut; removing it disables that hotkey.

Type a combo directly, or click **Record** and press it. Recording requires a modifier and uses the same physical key positions as TOML hotkeys. roto’s global hotkeys pause only while recording; Esc or **Stop Recording** ends recording without changing the previous combo. Shortcuts reserved by macOS or another app may not reach the recorder; typing a combo does not override those reservations.

**Save** (⌘S) validates the entire draft, writes `config.toml`, and reloads it. Invalid keys, duplicate physical combos (including aliases), missing app targets, and unknown window actions cannot be saved. **Cancel** or Esc outside recording discards the draft. Clicking away hides the popup but keeps the draft for the next time you open it; nothing is written until Save. **Discard & Reload** replaces the draft with the current file.

If the file changes externally while you edit, saving is refused rather than overwriting it. Reload and reapply your changes. A broken config must be fixed through **Open config…** first. The editor does not edit layout geometry, other settings, or the fixed navigation keys inside popups.

Saving replaces keymap assignments while preserving unrelated settings, standalone comments, and section headers. Inline comments on rewritten keymap assignments are not retained. Symlinked config files stay symlinks. The editor supports the section-based format shown below, including quoted headers and keys; inline or dotted keymap assignments (such as `hotkeys.clipboard = "ctrl+alt+v"`) are refused without changing the file. Move those assignments into the corresponding sections using **Open config…**, then reload.

## File reference

```toml
[general]
launch_at_login = false
popup_screen = "primary"             # primary (default) | cursor | frontmost

[window]
gap = 0                              # pixels inset from the display's visible frame

[window.layouts]
editor = { x = 0.0, y = 0.0, w = 0.6, h = 1.0 }

[hotkeys.window]
"ctrl+alt+left" = "half-left"
"ctrl+alt+right" = "half-right"
"ctrl+alt+up" = "half-top"
"ctrl+alt+down" = "half-bottom"
"ctrl+alt+u" = "quarter-top-left"
"ctrl+alt+i" = "quarter-top-right"
"ctrl+alt+j" = "quarter-bottom-left"
"ctrl+alt+k" = "quarter-bottom-right"
"ctrl+alt+d" = "third-left"
"ctrl+alt+f" = "third-center"
"ctrl+alt+g" = "third-right"
"ctrl+alt+shift+d" = "two-thirds-left"
"ctrl+alt+shift+g" = "two-thirds-right"
"ctrl+alt+enter" = "maximize"
"ctrl+alt+shift+enter" = "almost-maximize"
"ctrl+alt+c" = "center"              # keep size, center on the current display
"ctrl+alt+shift+c" = "center-large"  # centered, 86% tall, 80% wide (capped on ultrawide screens)
"ctrl+alt+cmd+right" = "next-display"
"ctrl+alt+cmd+left" = "prev-display"
"ctrl+alt+shift+h" = "focus-left"
"ctrl+alt+shift+l" = "focus-right"
"ctrl+alt+shift+k" = "focus-up"
"ctrl+alt+shift+j" = "focus-down"
"ctrl+alt+shift+right" = "focus-next-display"
"ctrl+alt+shift+left" = "focus-prev-display"
"ctrl+alt+e" = "layout:editor"

[hotkeys.apps]                       # bundle id, app name, or path to an .app
"ctrl+alt+t" = "com.apple.Terminal"
"ctrl+alt+b" = "Safari"

[hotkeys]
clipboard = "ctrl+alt+v"
emoji = "ctrl+alt+period"
windows = "ctrl+alt+w"                # window switcher
cheatsheet = "ctrl+alt+slash"         # every shortcut, also in the menu bar

[apps]
when_focused = "cycle"               # app hotkey on an app already in front: cycle | hide | none

[clipboard]
history_size = 200
max_age_days = 60                    # drop entries older than this; 0 keeps them forever
persist = true                       # ~/Library/Application Support/roto/clipboard.json + clipboard-images/ (0600); false → memory only
include_images = true
ignore_apps = ["com.1password.1password"]

[emoji]
skin_tone = "default"                # default | light | medium-light | medium | medium-dark | dark
```

Hotkey tokens: `ctrl`/`control`, `alt`/`option`/`opt`, `cmd`/`command`, `shift`, plus a key (`left`, `enter`, `period`, `a`–`z`, `0`–`9`, `f1`–`f20`, …). At least one modifier is required. Duplicate combos are a config error.

## Window actions

Values for `[hotkeys.window]`:

| Action | Moves or focuses |
| --- | --- |
| `half-left` | Left half |
| `half-right` | Right half |
| `half-top` | Top half |
| `half-bottom` | Bottom half |
| `quarter-top-left` | Top-left quarter |
| `quarter-top-right` | Top-right quarter |
| `quarter-bottom-left` | Bottom-left quarter |
| `quarter-bottom-right` | Bottom-right quarter |
| `third-left` | Left third |
| `third-center` | Center third |
| `third-right` | Right third |
| `two-thirds-left` | Left two thirds |
| `two-thirds-right` | Right two thirds |
| `maximize` | Maximize |
| `almost-maximize` | Almost maximize |
| `center-large` | Center, large: 86% of the height, 80% of the width, at most 1.6× as wide as tall |
| `center` | Center, keep size |
| `next-display` | Move window to next display |
| `prev-display` | Move window to previous display |
| `focus-left` | Focus window to the left |
| `focus-right` | Focus window to the right |
| `focus-up` | Focus window above |
| `focus-down` | Focus window below |
| `focus-next-display` | Focus next display |
| `focus-prev-display` | Focus previous display |
| `layout:NAME` | A layout defined under `[window.layouts]` |

## Reloading

roto watches `~/.config/roto/config.toml` and applies edits right away. A config with errors never stops the app: the last good config stays active, and the menu bar icon shows the error. The cheatsheet (⌃⌥/) always lists the shortcuts currently in effect.

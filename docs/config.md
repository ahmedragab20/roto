# Configuration

roto reads `~/.config/roto/config.toml`. If the file is missing, it is created from the bundled default. Edits are picked up automatically. A bad file never kills the app: the last good config stays active and the menu bar icon shows the error.

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

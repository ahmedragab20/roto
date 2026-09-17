<p align="center">
  <img src="docs/assets/icon-256.png" width="128" height="128" alt="roto app icon">
</p>

<h1 align="center">roto</h1>

<p align="center">
  <strong>Spotlight searches. roto does the rest.</strong><br>
  Windows, apps, clipboard, and emoji in one native, local-only menu bar agent for macOS.
</p>

<p align="center">
  <a href="https://ahmedragab20.github.io/roto/">Website</a> ·
  <a href="docs/why.md">Why roto</a> ·
  <a href="docs/guide.md">Guide</a> ·
  <a href="docs/config.md">Config</a> ·
  <a href="PRIVACY.md">Privacy</a>
</p>

## Stop fixing Spotlight

Spotlight is good at search. What people miss on a Mac is everything else: snapping a window to a third, getting back last hour's copy, typing an emoji, jumping to the terminal with one chord. The usual fix is a bigger launcher that rebuilds search to add those, or a stack of single-purpose apps with their own permissions, updaters, and shortcuts.

roto keeps Spotlight and replaces the stack. Read the whole argument in [Stop fixing Spotlight](docs/why.md).

## The tools

Each tool has its own hotkey and opens directly. No palette, no extensions, no account.

| Tool | Default key | What it does |
| --- | --- | --- |
| Window layout | ⌃⌥← ⌃⌥→ ⌃⌥↑ ⌃⌥↓ … | Halves, thirds, quarters, maximize, center, next display |
| Window focus | ⌃⌥⇧H/J/K/L | Focus the window to the left, right, above, or below |
| App hotkeys | ⌃⌥T, ⌃⌥B, your own | Open, focus, or cycle an app with one chord |
| Window switcher | ⌃⌥W | Every open window, searchable, with an inspector |
| Clipboard history | ⌃⌥V | Text, images, and files; pastes straight into the field you were in |
| Emoji picker | ⌃⌥. | Types the emoji where your cursor is |
| Cheatsheet | ⌃⌥/ | Every shortcut in your config, also in the menu bar |

## Native, fast, small

Swift on AppKit, SwiftUI, the Accessibility API, and ScreenCaptureKit. No Electron, no web views, no helper processes. One dependency, a TOML parser, compiled in.

| Measure | Result |
| --- | --- |
| Memory at idle, all popups built | about 30 MB |
| CPU at idle | about 0.1% |
| App size | about 5 MB |
| Emoji search per keystroke | 4.7 ms median |
| Clipboard search, 200 entries including ten 1 MB texts | 0.7 ms median |

Measured on an M1 Pro running macOS 27, release build.

It behaves like a Mac app: Liquid Glass popups on macOS 26 and later, paste that lands in the app you were in without stealing its focus, keyboard-layout-aware ⌘V, VoiceOver labels, Reduce Motion, and Increase Contrast.

## Install

Requires macOS 14 or later and the Swift command line tools (`xcode-select --install`; Xcode is not required).

```bash
git clone https://github.com/ahmedragab20/roto.git
cd roto
make install                  # build, bundle, copy to /Applications/roto.app
open /Applications/roto.app
```

On first launch, allow roto under **System Settings → Privacy & Security → Accessibility**. It is the only permission roto needs. To keep that permission across rebuilds, sign with a local certificate; see [Signing](docs/guide.md#signing-so-accessibility-sticks).

Press ⌃⌥/ to see every shortcut.

## Configure

roto reads `~/.config/roto/config.toml`, creates it on first run, and reloads it when you save. A mistake never breaks the app: the last good config stays active and the menu bar icon shows the error.

```toml
[hotkeys.apps]                       # bundle id, app name, or path to an .app
"ctrl+alt+t" = "com.mitchellh.ghostty"
"ctrl+alt+b" = "Safari"

[apps]
when_focused = "cycle"               # pressing again: cycle | hide | none
```

Every key and value is in the [config reference](docs/config.md).

## What roto won't do

- Search files, apps, or the web. Spotlight does that well.
- Plugins, extension stores, AI features, or sync.
- Signed downloads or auto-update. You build it from source.
- Run on macOS older than 14.

## Privacy

The app contains no network code: no analytics, no accounts, no update checks. Clipboard history stays on your Mac in files only you can read. Details in [PRIVACY.md](PRIVACY.md).

## Development

```bash
make run          # build, bundle, and open build/roto.app
make test         # RotoCore unit tests (Swift Testing)
make brand        # redraw the icon and brand assets from BrandMark.swift
make gen-emoji    # rebuild emoji.json from Unicode and CLDR (network, dev only)
```

- `Sources/RotoCore`: config, search, clipboard history, window math, and the brand mark. No AppKit; covered by unit tests.
- `Sources/Roto`: the menu bar app, popups, hotkeys, and system integration.
- `docs/`: the [guide](docs/guide.md), [config reference](docs/config.md), [why roto](docs/why.md), [brand guide](docs/brand.md), and the website.

## License

MIT. See [LICENSE](LICENSE). The name and icon are described in the [brand guide](docs/brand.md).

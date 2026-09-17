# Stop fixing Spotlight

**Spotlight searches. roto does the rest.**

This is why roto exists, and why it leaves Spotlight alone.

## Spotlight is good at its job

Spotlight finds apps, files, settings, and quick answers. It ships with every Mac, indexes on your machine, and costs nothing. roto does not try to beat it at any of that.

## The gaps are not search problems

What people miss on a Mac is rarely about finding things:

- Put this window on the left half, or the right third, without reaching for the mouse.
- Get back the thing you copied five minutes ago.
- Type an emoji into the field you are already in.
- Jump to "the terminal" or "the browser" with one chord.
- See every open window and pick one.
- Remember which shortcut does what.

None of these is a search. Moving a window should not start with a text box.

## Two ways people fix it

**Replace Spotlight with a bigger launcher.** Launchers like Raycast and Alfred are excellent software. But to add window moves and clipboard history, they first rebuild the search you already have, and then keep growing: extension stores, sync, subscriptions, AI tiers. You end up with two launchers competing for ⌘Space and far more surface than the job needs.

**Stack single-purpose apps.** A window tiler, a clipboard manager, an emoji picker, an app launcher, a window switcher. Five apps means five permission prompts, five updaters, five settings windows, five processes idling in memory, and five sets of shortcuts that can collide.

Both fixes treat Spotlight as the thing to fix. It isn't. The pile of fixes is.

## roto replaces the fixes

roto keeps Spotlight for search and replaces the pile around it with one small menu bar agent:

| Tool | Default key | What it does |
| --- | --- | --- |
| Window layout | ⌃⌥← ⌃⌥→ ⌃⌥↑ ⌃⌥↓ … | Halves, thirds, quarters, maximize, large centered (⌃⌥⇧C), center, next display |
| Window focus | ⌃⌥⇧H/J/K/L | Focus the window to the left, right, above, or below |
| App hotkeys | your choice | Open, focus, or cycle an app with one chord |
| Window switcher | ⌃⌥W | Every open window, searchable, with an inspector |
| Clipboard history | ⌃⌥V | Text, images, and files; pastes straight into the field you were in |
| Emoji picker | ⌃⌥. | Types the emoji where your cursor is |
| Cheatsheet | ⌃⌥/ | Every shortcut you have configured, one key away |

Each tool has its own hotkey and opens directly. There is no palette to type into first, no extensions, and no account.

## Native, fast, small

roto is Swift, built on AppKit, SwiftUI, the Accessibility API, and ScreenCaptureKit. No Electron, no web views, no JavaScript runtime, no helper processes. Its only dependency is a TOML parser, compiled in.

Measured on an M1 Pro running macOS 27, release build:

| Measure | Result |
| --- | --- |
| Memory at idle, all popups built | about 30 MB |
| App size | about 5 MB |
| Emoji search, 1,909 emoji, per keystroke | 4.7 ms median (5.7 ms p95) |
| Clipboard search, 200 entries including ten 1 MB texts | 0.7 ms median |

A few choices keep it that way:

- Popups are built once at launch and reused. A hotkey shows a window; it does not build one.
- Search text is folded (case, accents, width) once, when an entry arrives, not on every keystroke.
- Copied images are stored once by content and, by default, kept on disk, so a history full of screenshots does not sit in memory.
- Thumbnails are decoded off the main thread and downsampled, never at full size.

It also behaves like a Mac app should:

- Liquid Glass popups on macOS 26 and later.
- Pastes and types into the app you were in without stealing its focus.
- Follows your keyboard layout, so ⌘V lands correctly on Dvorak or AZERTY.
- Respects Reduce Motion and Increase Contrast, and labels every list and grid for VoiceOver.

## Local only

The app contains no network code. No analytics, no accounts, no update checks. Your config is one TOML file you can read, diff, and keep in your dotfiles. Clipboard history stays on your Mac, in files only you can read. See [PRIVACY.md](../PRIVACY.md).

## What roto will not do

- Search files, apps, or the web. That is Spotlight's job, and it does it well.
- Plugins, extension stores, AI features, or sync.
- Signed downloads or auto-update. You build it from source with one `make run`.
- Run on macOS older than 14.

If you need those, a full launcher is the right tool. If you only ever installed one to patch the gaps, you can uninstall the patches.

**Keep Spotlight. Replace the fixes.**

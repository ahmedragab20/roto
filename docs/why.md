# Replace the stack

**⌘Space, and everything after it.**

This is why roto exists, and why it is one app instead of six.

## The gaps are small, and there are many

What people miss on a Mac is rarely one big feature. It is a handful of small ones:

- Open an app by typing a few letters, typos included, with the one you use most on top.
- Put this window on the left half, or the right third, without reaching for the mouse.
- Get back the thing you copied five minutes ago.
- Type an emoji into the field you are already in.
- Jump to "the terminal" or "the browser" with one chord.
- See every open window and pick one.
- Remember which shortcut does what.

Only the first is a search. Moving a window should not start with a text box.

## Two ways people fix it

**Install a bigger launcher.** Launchers like Raycast and Alfred are excellent software. But they put everything behind one text box, then keep growing: extension stores, sync, subscriptions, AI tiers. You get far more surface than the job needs.

**Stack single-purpose apps.** An app launcher, a window tiler, a clipboard manager, an emoji picker, a window switcher. Five apps means five permission prompts, five updaters, five settings windows, five processes idling in memory, and five sets of shortcuts that can collide.

Both work. Both leave you maintaining a pile.

## roto replaces the stack

roto takes ⌘Space for app search and covers the rest with one small menu bar agent:

| Tool | Default key | What it does |
| --- | --- | --- |
| App search | ⌘Space | Find and open any installed app; forgives typos and learns what you open |
| Window layout | ⌃⌥← ⌃⌥→ ⌃⌥↑ ⌃⌥↓ … | Halves, thirds, quarters, maximize, large centered (⌃⌥⇧C), center, next display |
| Window focus | ⌃⌥⇧H/J/K/L | Focus the window to the left, right, above, or below |
| App hotkeys | your choice | Open, focus, or cycle an app with one chord |
| Window switcher | ⌃⌥W | Every open window, searchable, with an inspector |
| Clipboard history | ⌃⌥V | Text, images, and files; pastes straight into the field you were in |
| Emoji picker | ⌃⌥. | Types the emoji where your cursor is |
| Cheatsheet | ⌃⌥/ | Every shortcut you have configured, one key away |

Each tool has its own hotkey and opens directly. There is no palette to type into first, no extensions, and no account.

Spotlight stays installed for files and the web. Give it another key, or open it from the menu bar.

## Native, fast, small

roto is Swift, built on AppKit, SwiftUI, the Accessibility API, and ScreenCaptureKit. No Electron, no web views, no JavaScript runtime, no helper processes. It has two dependencies, both compiled in: a TOML parser, and [fff](https://github.com/dmtrKovalenko/fff), the Rust search library behind app search.

Measured on an M1 Pro running macOS 27, release build:

| Measure | Result |
| --- | --- |
| Memory at idle, all popups built | about 30 MB |
| App size | about 10 MB (fff is about half) |
| App search, 96 apps, per keystroke | 0.04 ms median (0.15 ms p95) |
| Emoji search, 1,909 emoji, per keystroke | 0.9 ms median (1.1 ms p95) |
| Clipboard search, 200 entries including ten 1 MB texts | 0.7 ms median |

A few choices keep it that way:

- Popups are built once at launch and reused. A hotkey shows a window; it does not build one.
- App search answers in the same frame as the keystroke. Scanning for new apps happens in the background, never while you type.
- Search text is folded (case, accents, width) once, when an entry arrives, not on every keystroke.
- Search rules an entry out by its characters before doing any fuzzy work, so a typo-tolerant match is only attempted where the letters could line up at all.
- Copied images are stored once by content and, by default, kept on disk, so a history full of screenshots does not sit in memory.
- Thumbnails are decoded off the main thread and downsampled, never at full size.
- Asking macOS whether roto may paste costs a round trip to the permission daemon, about 6 ms. The answer is cached and refreshed off the main thread, so no popup waits on one to open.
- Nothing polls the main thread while a popup is up. The watch for another app taking the keyboard runs on a background queue.

It also behaves like a Mac app should:

- Liquid Glass popups on macOS 26 and later.
- Pastes and types into the app you were in without stealing its focus.
- Follows your keyboard layout, so ⌘V lands correctly on Dvorak or AZERTY.
- Respects Reduce Motion and Increase Contrast, and labels every list and grid for VoiceOver.

## Local only

The app contains no network code. No analytics, no accounts, no update checks. Your config is one TOML file you can read, diff, and keep in your dotfiles. Clipboard history stays on your Mac, in files only you can read. See [PRIVACY.md](../PRIVACY.md).

## What roto will not do

- Search files or the web. App search covers apps only, for now.
- Plugins, extension stores, AI features, or sync.
- Signed downloads or auto-update. You build it from source with one `make run`.
- Run on macOS older than 14.

If you need those, a full launcher is the right tool. If you only ever installed one to patch the gaps, you can uninstall the patches.

**One app. One config. No stack.**

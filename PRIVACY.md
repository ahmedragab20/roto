# Privacy

roto never collects, stores remotely, or transmits any data.

- There is no analytics, crash reporting, update check, telemetry, or account system.
- The application source under `Sources/` contains no network APIs (`URLSession`, `Network`, `NWConnection`, or similar).
- Clipboard history is saved locally by default (`clipboard.persist = true`): entries in `~/Library/Application Support/roto/clipboard.json` and copied images in `clipboard-images/` next to it, all mode `0600`. Images are deleted once they fall out of history. Set `clipboard.persist = false` to keep history in memory only; roto then removes the saved images.
- Config lives at `~/.config/roto/config.toml` on your machine.
- Accessibility permission is used only to move, focus, close, and minimize windows, to list window titles in the window switcher, and to synthesize paste / unicode insertion into the frontmost app. roto does not read document contents.
- Screen Recording is optional. roto asks for it only when you click "Show live window previews…" in the window switcher, and captures only the selected window, kept in memory.
- A copied image is written to a private temporary folder only when you Quick Look or open it from clipboard history; the folder is cleared the next time roto starts.

The only network use in this repository is the optional developer script `scripts/gen-emoji.swift`, which downloads public Unicode/CLDR tables so `emoji.json` can be regenerated offline. That script is not part of the running app; the JSON it produces is committed and loaded from disk.

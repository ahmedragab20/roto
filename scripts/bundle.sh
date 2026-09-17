#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product roto

APP="$ROOT/build/roto.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/roto" "$APP/Contents/MacOS/roto"
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/brand/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundle (emoji.json, config.default.toml).
if [[ -d "$ROOT/.build/release/roto_Roto.bundle" ]]; then
  cp -R "$ROOT/.build/release/roto_Roto.bundle" "$APP/Contents/Resources/"
fi

# Also copy resources next to the main bundle so Bundle.main can find them.
if [[ -f "$ROOT/Sources/Roto/Resources/emoji.json" ]]; then
  cp "$ROOT/Sources/Roto/Resources/emoji.json" "$APP/Contents/Resources/emoji.json"
fi
if [[ -f "$ROOT/Sources/Roto/Resources/config.default.toml" ]]; then
  cp "$ROOT/Sources/Roto/Resources/config.default.toml" "$APP/Contents/Resources/config.default.toml"
fi

# Ad-hoc signatures change on every build, and macOS then silently drops the
# Accessibility grant. Prefer the stable local identity when it exists.
if [[ -z "${CODESIGN_IDENTITY:-}" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"roto-dev"'; then
  CODESIGN_IDENTITY="roto-dev"
fi
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  echo "warning: ad-hoc signing; Accessibility must be granted again after this build (see README → Signing)" >&2
fi
codesign -s "$IDENTITY" --force --deep "$APP"
echo "Built $APP"

#!/bin/bash
#
# Builds duskpaper.app from the Swift package.
#
#   ./build.sh                # release build into ./build/duskpaper.app
#   ./build.sh --install      # ...and copy it into /Applications
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

CONFIG="release"
INSTALL=0

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --debug) CONFIG="debug" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

APP_NAME="duskpaper"
# .noindex suffix keeps Spotlight from indexing build output, so searching
# "duskpaper" in Finder doesn't turn up app bundles inside the project.
BUILD_DIR="$ROOT/build.noindex"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [ ! -f "$BINARY" ]; then
  echo "Build product not found at $BINARY" >&2
  exit 1
fi

echo "==> Assembling bundle"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Icon
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# Sign ad-hoc so macOS grants the app a stable identity (needed for the
# "launch at login" login item).
echo "==> Signing"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || codesign --force --sign - "$APP_DIR"

# Make the bundle executable look like a normal app to LaunchServices.
touch "$APP_DIR"

echo "==> Built $APP_DIR"

if [ "$INSTALL" -eq 1 ]; then
  echo "==> Installing into /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
  echo "==> Installed /Applications/$APP_NAME.app"
fi

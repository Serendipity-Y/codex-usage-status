#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/macos/CodexUsageStatus"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CodexUsageStatus.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
VERSION="${VERSION:-0.1.0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-io.github.codexusagestatus.app}"

detect_hardware_arch() {
  local machine
  machine="$(uname -m)"

  if [[ "$machine" == "x86_64" ]]; then
    if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]; then
      echo "arm64"
      return
    fi
  fi

  echo "$machine"
}

BUILD_ARCH="${BUILD_ARCH:-$(detect_hardware_arch)}"

case "$BUILD_ARCH" in
  arm64 | x86_64)
    ;;
  *)
    echo "Unsupported BUILD_ARCH '$BUILD_ARCH'. Use arm64 or x86_64." >&2
    exit 1
    ;;
esac

TRIPLE="${BUILD_ARCH}-apple-macosx${MACOSX_DEPLOYMENT_TARGET}"
BUILD_ARGS=(
  --package-path "$SWIFT_DIR"
  -c release
  --triple "$TRIPLE"
)

swift build "${BUILD_ARGS[@]}"
BINARY_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY_PATH="$BINARY_DIR/CodexUsageStatus"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Build succeeded, but expected binary was not found at $BINARY_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/CodexUsageStatus"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsageStatus</string>
  <key>CFBundleIdentifier</key>
  <string>__BUNDLE_IDENTIFIER__</string>
  <key>CFBundleName</key>
  <string>Codex Usage Status</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__VERSION__</string>
  <key>LSMinimumSystemVersion</key>
  <string>__MIN_MACOS__</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>MIT</string>
</dict>
</plist>
PLIST

/usr/bin/sed -i '' "s/__VERSION__/$VERSION/g" "$CONTENTS_DIR/Info.plist"
/usr/bin/sed -i '' "s/__MIN_MACOS__/$MACOSX_DEPLOYMENT_TARGET/g" "$CONTENTS_DIR/Info.plist"
/usr/bin/sed -i '' "s/__BUNDLE_IDENTIFIER__/$BUNDLE_IDENTIFIER/g" "$CONTENTS_DIR/Info.plist"

codesign --force --sign "$CODESIGN_IDENTITY" "$APP_DIR" >/dev/null

echo "$APP_DIR"

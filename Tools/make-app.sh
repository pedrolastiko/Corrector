#!/usr/bin/env bash
#
# Builds Corrector.app — a real, double-clickable macOS bundle.
#
# SwiftPM cannot emit an.app, so this assembles one around the release binary:
# the standard Contents/{MacOS,Resources} layout, an Info.plist, the generated
# icon, and an ad-hoc code signature so Gatekeeper will run it locally.
#
#./Tools/make-app.sh [output-dir]      # default:./dist
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
APP="$OUT/Corrector.app"
# Read from the source rather than keeping a second copy here: the bundle's
# version and the one shown in the app had already drifted apart once.
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' \
  "$ROOT/Sources/CorrectorAppCore/Release.swift" | head -1)"
if [ -z "$VERSION" ]; then
  echo "could not read the version from Sources/CorrectorAppCore/Release.swift" >&2
  exit 1
fi

cd "$ROOT"

echo "==> Building release binaries"
swift build -c release --product CorrectorApp
swift build -c release --product corrector
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Generating icon"
if [ ! -f "$ROOT/Assets/Corrector.icns" ]; then
  swift "$ROOT/Tools/make-icon.swift" "$ROOT/Assets"
  iconutil -c icns "$ROOT/Assets/Corrector.iconset" -o "$ROOT/Assets/Corrector.icns"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/CorrectorApp" "$APP/Contents/MacOS/Corrector"
# Ship the CLI inside the bundle too, so one artefact carries both front ends.
# It must NOT be called "corrector": macOS filesystems are case-insensitive by
# default, so that name is the same file as the GUI binary above and would
# silently overwrite it.
cp "$BIN_DIR/corrector" "$APP/Contents/MacOS/corrector-cli"
cp "$ROOT/Assets/Corrector.icns" "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM puts the CLI's sample documents in a side bundle; carry it along so
# `Corrector.app/Contents/MacOS/corrector check memo` keeps working.
if [ -d "$BIN_DIR/Corrector_corrector.bundle" ]; then
  cp -R "$BIN_DIR/Corrector_corrector.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>Corrector</string>
    <key>CFBundleDisplayName</key>           <string>Corrector</string>
    <key>CFBundleExecutable</key>            <string>Corrector</string>
    <key>CFBundleIdentifier</key>            <string>dev.corrector.app</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>CFBundleIconName</key>              <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>        <string>13.0</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Corrector. MIT licensed.</string>
    <!-- macOS Services: right-click on selected text anywhere.
         NSReturnTypes on the first one is what lets macOS substitute the
         corrected text for the selection in the originating app.
         These titles are read by the system at registration time, so they
         cannot follow the in-app Interface picker. -->
    <key>NSServices</key>
    <array>
      <dict>
        <key>NSMenuItem</key>
        <dict><key>default</key><string>Corriger la sélection</string></dict>
        <key>NSMessage</key>    <string>correctSelection</string>
        <key>NSPortName</key>   <string>Corrector</string>
        <!-- Both spellings on purpose: the legacy pasteboard name and the
             modern UTI. Applications publish one or the other, and a service
             that names only NSStringPboardType is invisible to those that
             offer public.utf8-plain-text. -->
        <key>NSSendTypes</key>
        <array>
          <string>public.utf8-plain-text</string>
          <string>public.plain-text</string>
          <string>NSStringPboardType</string>
        </array>
        <key>NSReturnTypes</key>
        <array>
          <string>public.utf8-plain-text</string>
          <string>public.plain-text</string>
          <string>NSStringPboardType</string>
        </array>
      </dict>
      <dict>
        <key>NSMenuItem</key>
        <dict><key>default</key><string>Ouvrir dans Corrector</string></dict>
        <key>NSMessage</key>    <string>openInCorrector</string>
        <key>NSPortName</key>   <string>Corrector</string>
        <key>NSSendTypes</key>
        <array>
          <string>public.utf8-plain-text</string>
          <string>public.plain-text</string>
          <string>NSStringPboardType</string>
        </array>
      </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeName</key>  <string>Plain Text</string>
        <key>CFBundleTypeRole</key>  <string>Editor</string>
        <key>LSItemContentTypes</key>
        <array><string>public.plain-text</string></array>
      </dict>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Registering Services"
# Launch Services only discovers Services from apps it knows about, and pbs
# caches aggressively — both need a nudge after a rebuild.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" 2>/dev/null || true
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP" && echo "    signature OK"

echo
echo "Built $APP"
du -sh "$APP" | sed 's/^/    /'
echo
echo "Run it:   open \"$APP\""
echo "CLI:      \"$APP/Contents/MacOS/corrector-cli\" check memo"
